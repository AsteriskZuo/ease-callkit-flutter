import 'dart:async';

import 'package:em_chat_callkit/chat_callkit_define.dart';
import 'package:em_chat_callkit/chat_callkit_error.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_call.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_call_model.dart';
import 'package:em_chat_callkit/inherited/tools/call_define.dart';
import 'package:em_chat_callkit/inherited/tools/chat_callkit_tools.dart' as tools;
import 'package:flutter/foundation.dart';

String kAction = "action";
String kChannelName = "channelName";
String kCallType = "type";
String kCallerDevId = "callerDevId";
String kCallId = "callId";
String kTs = "ts";
String kMsgType = "msgType";
String kCalleeDevId = "calleeDevId";
String kCallStatus = "status";
String kCallResult = "result";
String kInviteAction = "invite";
String kAlertAction = "alert";
String kConfirmRingAction = "confirmRing";
String kCancelCallAction = "cancelCall";
String kAnswerCallAction = "answerCall";
String kConfirmCalleeAction = "confirmCallee";
String kVideoToVoice = "videoToVoice";
String kBusyResult = "busy";
String kAcceptResult = "accept";
String kRefuseResult = "refuse";
String kMsgTypeValue = "rtcCallWithAgora";
String kExt = "ext";

class AgoraChatEventHandler {
  final void Function(ChatCallKitError error) onError;
  final void Function(String callId, ChatCallKitCallEndReason reason)
      onCallEndReason;
  final VoidCallback onCallAccept;
  final void Function(
    String callId,
    String userId,
    ChatCallKitCallEndReason reason,
  ) onUserRemoved;

  final void Function(String callId) onAnswer;

  AgoraChatEventHandler({
    required this.onError,
    required this.onCallEndReason,
    required this.onCallAccept,
    required this.onUserRemoved,
    required this.onAnswer,
  });
}

typedef MessageWillSendHandler = void Function(ChatCallKitMessage message);

/// 流程：
/// 1. invite
///               2. receive invite
///               3. send alerting
/// 4. receive alerting
/// 5. send confirm ring
///               6. receive confirm ring
///               7. send refuse / answer
/// 8. receive, send device id to callee.
class AgoraChatManager {
  MessageWillSendHandler? onMessageWillSend;

  AgoraChatManager(
    this.handler, {
    required ChatCallKitStateChange stateChange,
    MessageWillSendHandler? messageWillSendHandler,
  }) {
    registerChatEvent();
    onMessageWillSend = messageWillSendHandler;
    model = ChatCallKitCallModel(stateChanged: stateChange);
  }

  late ChatCallKitCallModel model;
  final String key = "ChatCallKit";
  final AgoraChatEventHandler handler;
  Duration timeoutDuration = const Duration(seconds: 30);

  /// 应答 timer，当呼出时需要把callId和计时器放到map中，计时器终止时移除callId。
  /// 目的是确保被叫方收到的通话有效，
  /// 场景：对方收到离线的呼叫消息，需要判断当前呼叫是否有效，则将收到的callId发送给主叫方，
  ///      主叫方收到后，判断map中是否存在对应的callId，如果不存在，则表示本callId对应的通话无效，反之则为有效，之后将结果告知被叫方。
  final Map<String, Timer> callTimerDic = {};
  final Map<String, Timer> alertTimerDic = {};
  Timer? ringTimer;

  Timer? confirmTimer;

  bool get busy {
    return model.curCall != null && model.state != ChatCallKitCallState.idle;
  }

  void chatLog(String method, ChatCallKitMessage msg) {
    tools.log("AgoraChatManager: chat method: $method, ${msg.toJson().toString()}");
  }

  void onCurrentUserJoined() {
    model.hasJoined = true;
  }

  void clearInfo() {
    if (model.curCall != null) {
      model.state = ChatCallKitCallState.idle;
    }
  }

  void onStateChange(ChatCallKitCallState state) {
    model.state = state;
  }

  Future<void> clearCurrentCallInfo() async {
    clearAllTimer();
    model.hasJoined = false;
    model.curCall = null;
    model.recvCalls.clear();
  }

  void parseMsg(ChatCallKitMessage message) async {
    Map ext = message.attributes ?? {};
    if (!ext.containsKey(kMsgType)) return;

    final from = message.from!;
    final msgType = ext[kMsgType];
    final callId = ext[kCallId] ?? "";
    final result = ext[kCallResult] ?? "";
    final callerDevId = ext[kCallerDevId] ?? "";
    final calleeDevId = ext[kCalleeDevId] ?? "";
    final channel = ext[kChannelName] ?? "";

    final isValid = ext[kCallStatus] ?? false;
    num type = ext[kCallType] ?? 0;

    final callType = ChatCallKitCallType.values[type.toInt()];
    Map<String, String>? callExt = (ext[kExt] ?? {}).cast<String, String>();

    // 收到邀请
    void parseInviteMsgExt() {
      tools.log("AgoraChatManager: Receive Invite Message, parseInviteMsgExt called, callId: "
      "callId: $callId, from: $from, callerDevId: $callerDevId, "
      "calleeDevId: $calleeDevId, channel: $channel, isValid: $isValid, "
      "type: $type, callExt: $callExt");

      // 已经在通话中或者呼叫中。直接返回
      if (model.curCall?.callId == callId || callTimerDic.containsKey(callId)) {
        tools.log("AgoraChatManager: Already in call or call timer contains callId, return");
        return;
      }
      // 如果忙碌，直接返回 kBusyResult
      if (busy) {
        tools.log("AgoraChatManager: Busy, send kBusyResult to caller");
        sendAnswerMsg(from, callId, kBusyResult, callerDevId);
        return;
      }

      // 将邀请放到收到的call中
      model.recvCalls[callId] = ChatCallKitCall(
        callId: callId,
        remoteUserAccount: from,
        remoteCallDevId: callerDevId,
        callType: callType,
        isCaller: false,
        channel: channel,
        ext: callExt,
      );

      tools.log("AgoraChatManager: Send Alert Message to Caller, sendAlertMsgToCaller called, from: $from, callId: $callId, callerDevId: $callerDevId");
      // 发送应答
      sendAlertMsgToCaller(from, callId, callerDevId);
      // 启动应答计时器
      alertTimerDic[callId] =
          Timer.periodic(const Duration(seconds: 5), (timer) {
        // 时间到，取消应答计时
        timer.cancel();
        alertTimerDic.remove(callId);
      });
    }

    // 收到邀请应答
    void parseAlertMsgExt() {
      tools.log("AgoraChatManager: Receive Alert Message, parseAlertMsgExt called, callId: $callId, from: $from, callerDevId: $callerDevId, calleeDevId: $calleeDevId");
      // 判断是我发送的邀请收到应答
      if (model.curDevId == callerDevId) {
        // 判断应答是否与本地存储数据呼应
        if (model.curCall?.callId == callId && callTimerDic.containsKey(from)) {
          // 告知对方，应答验证通过, 告知对方当前通话有效
          sendConfirmRingMsgToCallee(from, callId, true, calleeDevId);
        }
      } else {
        // 告知应答方，应答验证未通过，当前通话已经过期或者无效
        sendConfirmRingMsgToCallee(from, callId, false, calleeDevId);
      }
    }

    // 收到回复，可以确定通话有效，此处如果非忙可以弹窗。
    void parseConfirmRingMsgExt() {
      tools.log("AgoraChatManager: Receive Confirm Ring Message, parseConfirmRingMsgExt called, callId: $callId, from: $from, callerDevId: $callerDevId, calleeDevId: $calleeDevId");
      if (alertTimerDic.containsKey(callId) && calleeDevId == model.curDevId) {
        alertTimerDic.remove(callId)?.cancel();
        if (busy) {
          tools.log("AgoraChatManager: Busy, send kBusyResult to caller");
          sendAnswerMsg(from, callId, kBusyResult, callerDevId);
          return;
        }
        if (model.recvCalls.containsKey(callId)) {
          // 验证通话有效，可以变为alerting状态, 如果无效则不需要处理
          if (isValid) {
            tools.log("AgoraChatManager: Confirm Ring Message is valid, set model.curCall and model.state to alerting");
            model.curCall = model.recvCalls[callId];
            model.recvCalls.clear();
            model.state = ChatCallKitCallState.alerting;
            alertTimerDic.forEach((key, value) {
              value.cancel();
            });
            alertTimerDic.clear();
          }
          model.recvCalls.remove(callId);
          ringTimer = Timer.periodic(timeoutDuration, (timer) {
            timer.cancel();
            ringTimer = null;
            if (model.curCall?.callId == callId) {
              tools.log("AgoraChatManager: No response, call end reason: remoteNoResponse");
              handler.onCallEndReason.call(
                model.curCall!.callId,
                ChatCallKitCallEndReason.remoteNoResponse,
              );
              model.state = ChatCallKitCallState.idle;
            }
          });
        }
      }
    }

    // 收到呼叫取消
    void parseCancelCallMsgExt() {
      tools.log("AgoraChatManager: Receive Cancel Call Message, parseCancelCallMsgExt called, callId: $callId, from: $from, callerDevId: $callerDevId, calleeDevId: $calleeDevId");
      // 如当前已经应答，但还未加入会议，取消所以计时，并告知上层呼叫停止
      if (model.curCall?.callId == callId) {
        confirmTimer?.cancel();
        confirmTimer = null;
        tools.log("AgoraChatManager: Cancel Call Message is valid, call end reason: remoteCancel");
        handler.onCallEndReason
            .call(model.curCall!.callId, ChatCallKitCallEndReason.remoteCancel);
        model.state = ChatCallKitCallState.idle;
      } else {
        model.recvCalls.remove(callId);
      }
      alertTimerDic.remove(callId)?.cancel();
    }

    // 收到结果应答
    void parseAnswerMsgExt() {
      tools.log("AgoraChatManager: Receive Answer Message, parseAnswerMsgExt called, callId: $callId, from: $from, callerDevId: $callerDevId, calleeDevId: $calleeDevId");
      if (model.curCall?.callId == callId && model.curDevId == callerDevId) {
        // 如果为多人模式
        if (model.curCall?.callType == ChatCallKitCallType.multi) {
          // 对方拒绝
          if (result != kAcceptResult) {
            removeUser(from, ChatCallKitCallEndReason.busy);
          }

          Timer? timer = callTimerDic.remove(from);
          if (timer != null) {
            timer.cancel();
            sendConfirmAnswerMsgToCallee(from, callId, result, calleeDevId);
            if (result == kAcceptResult) {
              model.state = ChatCallKitCallState.answering;
              ringTimer?.cancel();
              ringTimer = null;
            }
          }
          onAnswer();
        } else {
          // 非多人模式，是呼出状态时
          if (model.state == ChatCallKitCallState.outgoing) {
            if (result == kAcceptResult) {
              model.state = ChatCallKitCallState.answering;
              ringTimer?.cancel();
              ringTimer = null;
            } else {
              handler.onCallEndReason.call(
                model.curCall!.callId,
                result == kRefuseResult
                    ? ChatCallKitCallEndReason.refuse
                    : ChatCallKitCallEndReason.busy,
              );
              model.state = ChatCallKitCallState.idle;
            }
          }
          onAnswer();
          // 用于被叫方多设备的情况，被叫方收到后可以进行仲裁，只有收到这条后被叫方才能进行通话
          sendConfirmAnswerMsgToCallee(from, callId, result, calleeDevId);
        }
      }
    }

    void parseConfirmCalleeMsgExt() {
      tools.log("AgoraChatManager: Receive Confirm Callee Message, parseConfirmCalleeMsgExt called, callId: $callId, from: $from, callerDevId: $callerDevId, calleeDevId: $calleeDevId");
      if (model.state == ChatCallKitCallState.alerting &&
          model.curCall?.callId == callId) {
        confirmTimer?.cancel();
        confirmTimer = null;
        if (model.curDevId == calleeDevId) {
          if (result == kAcceptResult) {
            model.state = ChatCallKitCallState.answering;
            ringTimer?.cancel();
            ringTimer = null;
            if (model.curCall?.callType != ChatCallKitCallType.audio_1v1) {
              // 更新本地摄像头数据
            }
            handler.onCallAccept.call();
            // 此处要开始获取声网token。
          } else {
            model.state = ChatCallKitCallState.idle;
            handler.onCallEndReason.call(model.curCall!.callId,
                ChatCallKitCallEndReason.handleOnOtherDevice);
          }
        }
      } else {
        if (model.recvCalls.remove(callId) != null) {
          alertTimerDic.remove(callId)?.cancel();
        }
      }
    }

    void parseVideoToVoiceMsg() {}

    if (msgType == kMsgTypeValue) {
      String action = ext[kAction];
      tools.log("AgoraChatManager: action:-----------$action, ${ext.toString()}");
      if (action == kInviteAction) {
        parseInviteMsgExt();
      } else if (action == kAlertAction) {
        parseAlertMsgExt();
      } else if (action == kCancelCallAction) {
        parseCancelCallMsgExt();
      } else if (action == kAnswerCallAction) {
        parseAnswerMsgExt();
      } else if (action == kConfirmRingAction) {
        parseConfirmRingMsgExt();
      } else if (action == kConfirmCalleeAction) {
        parseConfirmCalleeMsgExt();
      } else if (action == kVideoToVoice) {
        parseVideoToVoiceMsg();
      }
    }
  }

  Future<void> sendInviteMsgToCallee(
    String userId,
    ChatCallKitCallType type,
    String callId,
    String channel,
    String? inviteMessage,
    Map<String, String>? ext,
  ) async {
    tools.log("AgoraChatManager: Send Invite Message to Callee, sendInviteMsgToCallee called, userId: $userId, type: $type, callId: $callId, channel: $channel, inviteMessage: $inviteMessage, ext: $ext");
    String sType = 'voice';
    if (type == ChatCallKitCallType.multi) {
      sType = 'conference';
    } else if (type == ChatCallKitCallType.video_1v1) {
      sType = 'video';
    }
    final msg = ChatCallKitMessage.createTxtSendMessage(
      targetId: userId,
      content: inviteMessage ?? 'invite info: $sType',
    );
    Map<String, dynamic> attr = {
      kMsgType: kMsgTypeValue,
      kAction: kInviteAction,
      kCallId: callId,
      kCallType: type.index,
      kCallerDevId: model.curDevId,
      kChannelName: channel,
      kTs: ts
    };
    if (ext != null) {
      attr[kExt] = ext;
    }

    msg.attributes = attr;
    onMessageWillSend?.call(msg);
    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
    //chatLog("sendInviteMsgToCallee", msg);
  }

  void sendAlertMsgToCaller(
      String callerId, String callId, String devId) async {
    tools.log("AgoraChatManager: Send Alert Message to Caller, sendAlertMsgToCaller called, callerId: $callerId, callId: $callId, devId: $devId");
    ChatCallKitMessage msg = ChatCallKitMessage.createCmdSendMessage(
      targetId: callerId,
      action: "rtcCall",
      deliverOnlineOnly: true,
    );
    Map<String, dynamic> attributes = {
      kMsgType: kMsgTypeValue,
      kAction: kAlertAction,
      kCallId: callId,
      kCalleeDevId: model.curDevId,
      kCallerDevId: devId,
      kTs: ts,
    };
    msg.attributes = attributes;
    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
    //chatLog("sendAlertMsgToCaller", msg);
  }

  void sendConfirmRingMsgToCallee(
      String userId, String callId, bool isValid, String calleeDevId) {
    tools.log("AgoraChatManager: Send Confirm Ring Message to Callee, sendConfirmRingMsgToCallee called, userId: $userId, callId: $callId, isValid: $isValid, calleeDevId: $calleeDevId");
    ChatCallKitMessage msg = ChatCallKitMessage.createCmdSendMessage(
      targetId: userId,
      action: "rtcCall",
      deliverOnlineOnly: true,
    );
    Map<String, dynamic> attributes = {
      kMsgType: kMsgTypeValue,
      kAction: kConfirmRingAction,
      kCallId: callId,
      kCallerDevId: model.curDevId,
      kCallStatus: isValid,
      kTs: ts,
      kCalleeDevId: calleeDevId,
    };
    msg.attributes = attributes;

    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
    //chatLog("sendConfirmRingMsgToCallee", msg);
  }

  void sendAnswerMsg(
      String remoteUserId, String callId, String result, String devId) async {
    tools.log("AgoraChatManager: Send Answer Message to Callee, sendAnswerMsg called, remoteUserId: $remoteUserId, callId: $callId, result: $result, devId: $devId");
    ChatCallKitMessage msg = ChatCallKitMessage.createCmdSendMessage(
        targetId: remoteUserId, action: "rtcCall");
    Map<String, dynamic> attributes = {
      kMsgType: kMsgTypeValue,
      kAction: kAnswerCallAction,
      kCallId: callId,
      kCalleeDevId: model.curDevId,
      kCallerDevId: devId,
      kCallResult: result,
      kTs: ts,
    };

    msg.attributes = attributes;
    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
    confirmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      timer.cancel();
      confirmTimer = null;
    });

    //chatLog("sendAnswerMsg", msg);
  }

  void sendConfirmAnswerMsgToCallee(
      String userId, String callId, String result, String devId) async {
    tools.log("AgoraChatManager: Send Confirm Answer Message to Callee, sendConfirmAnswerMsgToCallee called, userId: $userId, callId: $callId, result: $result, devId: $devId");
    ChatCallKitMessage msg = ChatCallKitMessage.createCmdSendMessage(
      targetId: userId,
      action: "rtcCall",
    );

    Map<String, dynamic> attributes = {
      kMsgType: kMsgTypeValue,
      kAction: kConfirmCalleeAction,
      kCallId: callId,
      kCallerDevId: model.curDevId,
      kCalleeDevId: devId,
      kCallResult: result,
      kTs: ts,
    };
    msg.attributes = attributes;
    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
    //chatLog("sendConfirmAnswerMsgToCallee", msg);
  }

  void sendCancelCallMsgToCallee(String userId, String callId) {
    tools.log("AgoraChatManager: Send Cancel Call Message to Callee, sendCancelCallMsgToCallee called, userId: $userId, callId: $callId");
    final msg = ChatCallKitMessage.createCmdSendMessage(
        targetId: userId, action: 'rtcCall');
    msg.attributes = {
      kMsgType: kMsgTypeValue,
      kAction: kCancelCallAction,
      kCallId: callId,
      kCallerDevId: model.curDevId,
      kTs: ts,
    };

    ChatCallKitClient.getInstance.chatManager.sendMessage(msg);
  }

  void registerChatEvent() {
    unregisterChatEvent();
    ChatCallKitClient.getInstance.chatManager.addEventHandler(
        key,
        ChatCallKitEventHandler(
          onCmdMessagesReceived: onMessageReceived,
          onMessagesReceived: onMessageReceived,
        ));

    ChatCallKitClient.getInstance.chatManager.addMessageEvent(
        key,
        ChatCallKitMessageEvent(
          onError: (msgId, msg, error) {
            handler.onError(ChatCallKitError.im(error.code, error.description));
          },
          onSuccess: (msgId, msg) {
            //chatLog("onSuccess", msg);
            tools.log("AgoraChatManager: onSuccess, msgId: $msgId}");
          },
        ));
  }

  void unregisterChatEvent() {
    ChatCallKitClient.getInstance.chatManager.removeEventHandler(key);
    ChatCallKitClient.getInstance.chatManager.removeMessageEvent(key);
  }

  void onMessageReceived(List<ChatCallKitMessage> list) {
    for (var msg in list) {
      parseMsg(msg);
    }
  }

  int get ts => DateTime.now().millisecondsSinceEpoch;

  void clearAllTimer() {
    callTimerDic.forEach((key, value) {
      value.cancel();
    });
    callTimerDic.clear();

    alertTimerDic.forEach((key, value) {
      value.cancel();
    });
    alertTimerDic.clear();

    confirmTimer?.cancel();
    confirmTimer = null;

    ringTimer?.cancel();
    ringTimer = null;
  }

  void dispose() {
    unregisterChatEvent();
    clearAllTimer();
  }

  Future<String> startSingleCall(
    String userId, {
    String? inviteMessage,
    ChatCallKitCallType type = ChatCallKitCallType.audio_1v1,
    int? agoraUid,
    Map<String, String>? ext,
  }) async {
    if (userId.isEmpty) {
      throw ChatCallKitError.process(
          ChatCallKitErrorProcessCode.invalidParam, 'Require remote userId');
    }
    if (busy) {
      throw ChatCallKitError.process(
          ChatCallKitErrorProcessCode.busy, 'Current is busy');
    }
    model.curCall = ChatCallKitCall(
      callId: tools.ChatCallKitTools.randomStr,
      channel: tools.ChatCallKitTools.randomStr,
      remoteUserAccount: userId,
      callType: type,
      isCaller: true,
      ext: ext,
    );

    model.state = ChatCallKitCallState.outgoing;

    await sendInviteMsgToCallee(
      userId,
      type,
      model.curCall?.callId ?? "",
      model.curCall?.channel ?? "",
      inviteMessage,
      ext,
    );

    if (!callTimerDic.containsKey(userId)) {
      callTimerDic[userId] = Timer.periodic(
        timeoutDuration,
        (timer) {
          timer.cancel();
          callTimerDic.remove(userId);
          if (model.curCall != null) {
            sendCancelCallMsgToCallee(userId, model.curCall!.callId);
            if (model.curCall!.callType != ChatCallKitCallType.multi) {
              handler.onCallEndReason(model.curCall!.callId,
                  ChatCallKitCallEndReason.remoteNoResponse);
              model.state = ChatCallKitCallState.idle;
            }
          }
        },
      );
    }

    return model.curCall!.callId;
  }

  void removeUser(String userId, ChatCallKitCallEndReason reason) {
    if (model.curCall != null) {
      handler.onUserRemoved(model.curCall!.callId, userId, reason);
    }
  }

  void onAnswer() {
    if (model.curCall?.callId != null) {
      handler.onAnswer(model.curCall!.callId);
    }
  }

  Future<String> startInviteUsers(
    List<String> userIds,
    String? inviteMessage,
    Map<String, String>? ext,
  ) async {
    tools.log("AgoraChatManager: Start Invite Users, startInviteUsers called, userIds: $userIds, inviteMessage: $inviteMessage, ext: $ext");
    if (userIds.isEmpty) {
      throw ChatCallKitError.process(
          ChatCallKitErrorProcessCode.invalidParam, 'Require remote userId');
    }

    if (model.curCall != null) {
      for (var element in userIds) {
        if (model.curCall!.allUserAccounts.values.contains(element)) {
          continue;
        }
        sendInviteMsgToCallee(
          element,
          model.curCall!.callType,
          model.curCall!.callId,
          model.curCall!.channel,
          inviteMessage,
          ext,
        );

        callTimerDic[element] = Timer.periodic(timeoutDuration, (timer) {
          timer.cancel();
          callTimerDic.remove(element);
          if (model.curCall != null) {
            sendCancelCallMsgToCallee(element, model.curCall!.callId);
            removeUser(element, ChatCallKitCallEndReason.remoteNoResponse);
          }
        });
      }
    } else {
      model.curCall = ChatCallKitCall(
        callId: tools.ChatCallKitTools.randomStr,
        callType: ChatCallKitCallType.multi,
        isCaller: true,
        channel: tools.ChatCallKitTools.randomStr,
        ext: ext,
      );

      model.state = ChatCallKitCallState.answering;
      for (var element in userIds) {
        sendInviteMsgToCallee(
          element,
          model.curCall!.callType,
          model.curCall!.callId,
          model.curCall!.channel,
          inviteMessage,
          ext,
        );

        callTimerDic[element] = Timer.periodic(timeoutDuration, (timer) {
          timer.cancel();
          callTimerDic.remove(element);
          if (model.curCall != null) {
            sendCancelCallMsgToCallee(element, model.curCall!.callId);
            removeUser(element, ChatCallKitCallEndReason.remoteNoResponse);
          }
        });
      }
    }

    return model.curCall!.callId;
  }

  Future<void> hangup(String callId) async {
    tools.log("AgoraChatManager: Hangup, hangup called, callId: $callId");
    if (model.curCall?.callId == callId) {
      clearAllTimer();
      if (model.state == ChatCallKitCallState.answering) {
        handler.onCallEndReason(callId, ChatCallKitCallEndReason.hangup);
      } else if (model.state == ChatCallKitCallState.outgoing) {
        sendCancelCallMsgToCallee(
          model.curCall!.remoteUserAccount!,
          model.curCall!.callId,
        );
        handler.onCallEndReason(callId, ChatCallKitCallEndReason.cancel);
      } else if (model.state == ChatCallKitCallState.alerting) {
        sendAnswerMsg(
          model.curCall!.remoteUserAccount!,
          model.curCall!.callId,
          kRefuseResult,
          model.curCall!.remoteCallDevId!,
        );
        handler.onCallEndReason(callId, ChatCallKitCallEndReason.refuse);
      }
      model.state = ChatCallKitCallState.idle;
    }
  }

  Future<void> answerCall(String callId) async {
    tools.log("AgoraChatManager: Answer Call, answerCall called, callId: $callId");
    if (model.curCall?.callId == callId) {
      if (model.curCall!.isCaller == true) {
        return;
      }
      onAnswer();
      sendAnswerMsg(
        model.curCall!.remoteUserAccount!,
        callId,
        kAcceptResult,
        model.curCall!.remoteCallDevId!,
      );
    }
  }
}
