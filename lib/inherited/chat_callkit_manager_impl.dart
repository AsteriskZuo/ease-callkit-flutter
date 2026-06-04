import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:em_chat_callkit/chat_callkit.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_chat_manager.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_rtc_manager.dart';
import 'package:em_chat_callkit/inherited/tools/chat_callkit_tools.dart' as tools;

class ChatCallKitManagerImpl {
  static ChatCallKitManagerImpl? _instance;
  static ChatCallKitManagerImpl get instance {
    _instance ??= ChatCallKitManagerImpl();
    return _instance!;
  }

  List<ChatCallKitObserver> handlers = [];
  RtcTokenHandler? rtcTokenHandler;
  UserMapperHandler? userMapperHandler;

  late final AgoraChatManager _chat;
  late final AgoraRTCManager _rtc;

  ChatCallKitManagerImpl() {
    _chat = AgoraChatManager(
      AgoraChatEventHandler(
        onCallAccept: () {
          onCallAccept();
        },
        onCallEndReason: (callId, reason) {
          onCallEndReason(callId, reason);
        },
        onError: (error) {
          onError(error);
        },
        onUserRemoved: (callId, userId, reason) {
          onUserRemoved(callId, userId, reason);
        },
        onAnswer: (callId) {
          onAnswer(callId);
        },
      ),
      stateChange: (newState, preState) {
        stateChanged(
          newState,
          preState,
        );
      },
      messageWillSendHandler: (message) {
        for (var value in handlers) {
          value.onInviteMessageWillSend.call(message);
        }
      },
    );

    _rtc = AgoraRTCManager(
      RTCEventHandler(
        onJoinChannelSuccess: () {
          onJoinChannelSuccess();
        },
        onActiveSpeaker: (uid) {
          onActiveSpeaker(uid);
        },
        onError: (err, msg) {
          onRTCError(err, msg);
        },
        onFirstRemoteVideoDecoded: (agoraUid, width, height) {
          onFirstRemoteVideoDecoded(agoraUid, width, height);
        },
        onLeaveChannel: () {
          onLeaveChannel();
        },
        onUserJoined: (agoraUid) {
          onUserJoined(agoraUid);
        },
        onRemoteVideoStateChanged: (agoraUid, state, reason) {
          onRemoteVideoStateChanged(agoraUid, state, reason);
        },
        onUserLeaved: (agoraUid) {
          onUserLeaved(agoraUid);
        },
        onUserMuteAudio: (agoraUid, muted) {
          onUserMuteAudio(agoraUid, muted);
        },
        onUserMuteVideo: (agoraUid, muted) {
          onUserMuteVideo(agoraUid, muted);
        },
      ),
    );
  }

  set agoraAppId(String agoraAppId) {
    _rtc.agoraAppId = agoraAppId;
  }

  set callTimeout(Duration duration) {
    _chat.timeoutDuration = duration;
  }

  // 用于设置通话的默认状态
  Future<void> setDefaultModeType() async {
    if (_chat.model.curCall!.callType == ChatCallKitCallType.audio_1v1) {
      await _rtc.disableSpeaker();
    }
  }

  Future<void> initRTC() {
    tools.log("ChatCallKitManagerImpl: initRTC called");
    return _rtc.initRTC();
  }

  Future<void> releaseRTC() {
    tools.log("ChatCallKitManagerImpl: releaseRTC called");
    return _rtc.releaseRTC();
  }

  Future<String> startSingleCall(
    String userId, {
    String? inviteMessage,
    ChatCallKitCallType type = ChatCallKitCallType.audio_1v1,
    Map<String, String>? ext,
  }) {
    tools.log("ChatCallKitManagerImpl: startSingleCall called, userId: $userId, type: $type, ext: $ext, inviteMessage: $inviteMessage");
    return _chat.startSingleCall(
      userId,
      inviteMessage: inviteMessage,
      type: type,
      ext: ext,
    );
  }

  Future<String> startInviteUsers(
    List<String> userIds,
    String? inviteMessage,
    Map<String, String>? ext,
  ) {
    tools.log("ChatCallKitManagerImpl: startInviteUsers called, userIds: $userIds, inviteMessage: $inviteMessage, ext: $ext");
    return _chat.startInviteUsers(userIds, inviteMessage, ext);
  }

  Future<void> answerCall(String callId) {
    tools.log("ChatCallKitManagerImpl: answerCall called, callId: $callId");
    return _chat.answerCall(callId);
  }

  Future<void> hangup(String callId) async {
    tools.log("ChatCallKitManagerImpl: hangup called, callId: $callId");
    await _chat.hangup(callId);
  }

  Future<void> answer(String callId) async {
    tools.log("ChatCallKitManagerImpl: answer called, callId: $callId");
    return _chat.answerCall(callId);
  }

  void addEventListener(ChatCallKitObserver handler) {
    tools.log("ChatCallKitManagerImpl: addEventListener called");
    if (handlers.contains(handler)) return;
    handlers.add(handler);
  }

  void removeEventListener(ChatCallKitObserver handler) {
    tools.log("ChatCallKitManagerImpl: removeEventListener called");
    handlers.remove(handler);
  }

  void clearAllEventListeners() {
    tools.log("ChatCallKitManagerImpl: clearAllEventListeners called");
    handlers.clear();
  }

  Future<void> fetchToken() async {
    tools.log("ChatCallKitManagerImpl: fetchToken called");
    if (_chat.model.hasJoined) return;
    if (_chat.model.curCall == null ||
        _rtc.agoraAppId == null ||
        rtcTokenHandler == null) return;

    Map<String, int> agoraToken = await rtcTokenHandler!.call(
      _chat.model.curCall!.channel,
      _rtc.agoraAppId!,
    );

    tools.log("ChatCallKitManagerImpl: fetchToken called, agoraToken: $agoraToken");

    if (agoraToken.isEmpty) {
      throw ChatCallKitError.process(
          ChatCallKitErrorProcessCode.fetchTokenFail, 'fetch token fail');
    }

    if (_chat.model.curCall == null) {}

    String? username = ChatCallKitClient.getInstance.currentUserId;

    if (username == null) return;

    tools.log(
      "ChatCallKitManagerImpl: joinChannel called, "
      "callType: ${_chat.model.curCall!.callType}, "
      "agoraToken: ${agoraToken.keys.first}, "
      "channel: ${_chat.model.curCall!.channel}, "
      "agoraUid: ${_chat.model.agoraUid ?? agoraToken.values.first}"
    );
    await _rtc.joinChannel(
      _chat.model.curCall!.callType,
      agoraToken.keys.first,
      _chat.model.curCall!.channel,
      _chat.model.agoraUid ?? agoraToken.values.first,
    );
  }
}

extension ChatEvent on ChatCallKitManagerImpl {
  Future<ChatCallKitUserMapper?> updateUserMapper(int agoraUid) async {
    String? userId = ChatCallKitClient.getInstance.currentUserId;

    if (userId == null ||
        ChatCallKitClient.getInstance.options?.appKey == null ||
        _chat.model.curCall?.channel == null) {
      return null;
    }

    ChatCallKitUserMapper? mapper =
        await userMapperHandler?.call(_chat.model.curCall!.channel, agoraUid);

    if (_chat.model.curCall != null &&
        mapper != null &&
        mapper.channel == _chat.model.curCall!.channel) {
      if (_chat.model.curCall!.channel != mapper.channel) return null;

      _chat.model.curCall!.allUserAccounts.addAll(mapper.infoMapper);
    }

    return mapper;
  }

  void stateChanged(
      ChatCallKitCallState newState, ChatCallKitCallState preState) async {
    switch (newState) {
      case ChatCallKitCallState.idle:
        {
          tools.log("ChatCallKitManagerImpl:stateChanged: state changed to idle");
          await _chat.clearCurrentCallInfo();
          await _rtc.clearCurrentCallInfo();
        }
        break;
      case ChatCallKitCallState.outgoing:
        {
          tools.log("ChatCallKitManagerImpl:stateChanged: state changed to outgoing");
          if (_chat.model.curCall == null) return;
          if (_chat.model.curCall?.callType != ChatCallKitCallType.audio_1v1) {
            await _rtc.enableVideo();
            await _rtc.startPreview();
          }
          try {
            await fetchToken();
          } on ChatCallKitError catch (e) {
            onError(e);
          }
        }
        break;
      case ChatCallKitCallState.alerting:
        {
          tools.log("ChatCallKitManagerImpl:stateChanged: state changed to alerting");
          if (_chat.model.curCall == null) return;
          await _rtc.initEngine();
          tools.log("ChatCallKitManagerImpl: initEngine called");
          if (_chat.model.curCall != null) {
            if (_chat.model.curCall!.callType !=
                ChatCallKitCallType.audio_1v1) {
              tools.log("ChatCallKitManagerImpl: enable video");
              await _rtc.enableVideo();
              await _rtc.startPreview();
            }

            for (var value in handlers) {
              tools.log(
                "ChatCallKitManagerImpl: onReceiveCall called, "
                "remoteUserAccount: ${_chat.model.curCall!.remoteUserAccount}, "
                "callId: ${_chat.model.curCall!.callId}, "
                "callType: ${_chat.model.curCall!.callType}, "
                "ext: ${_chat.model.curCall!.ext}"
              );
              value.onReceiveCall.call(
                _chat.model.curCall!.remoteUserAccount!,
                _chat.model.curCall!.callId,
                _chat.model.curCall!.callType,
                _chat.model.curCall!.ext,
              );
            }
          }
        }
        break;
      case ChatCallKitCallState.answering:
        {
          tools.log("ChatCallKitManagerImpl:stateChanged: state changed to answering");
          if (_chat.model.curCall == null) return;
          if (_chat.model.curCall!.callType == ChatCallKitCallType.multi &&
              _chat.model.curCall!.isCaller) {
            // 多人主叫时，需要开启摄像头
            tools.log("ChatCallKitManagerImpl: enable video");
            await _rtc.enableVideo();
            await _rtc.startPreview();
            try {
              tools.log("ChatCallKitManagerImpl: fetchToken called");
              await fetchToken();
            } on ChatCallKitError catch (e) {
              onError(e);
            }
          }
        }
        break;
    }
  }

  void onCallAccept() async {
    try {
      tools.log("ChatCallKitManagerImpl: onCallAccept called");
      await fetchToken();
    } on ChatCallKitError catch (e) {
      onError(e);
    }
  }

  void onCallEndReason(String callId, ChatCallKitCallEndReason reason) {
    tools.log("ChatCallKitManagerImpl: onCallEndReason called, callId: $callId, reason: $reason");
    for (var value in handlers) {
      value.onCallEnd.call(callId, reason);
    }
  }

  void onAnswer(String callId) {
    tools.log("ChatCallKitManagerImpl: onAnswer called, callId: $callId");
    for (var value in handlers) {
      value.onAnswer.call(callId);
    }
  }

  void onError(ChatCallKitError error) {
    tools.log("ChatCallKitManagerImpl: onError called, error: $error");
    for (var value in handlers) {
      value.onError.call(error);
    }
  }

  void onUserRemoved(
      String callId, String userId, ChatCallKitCallEndReason reason) {
    tools.log("ChatCallKitManagerImpl: onUserRemoved called, callId: $callId, userId: $userId, reason: $reason");
    for (var value in handlers) {
      value.onUserRemoved.call(callId, userId, reason);
    }
  }
}

extension RTCEvent on ChatCallKitManagerImpl {
  void onJoinChannelSuccess() async {
    tools.log("ChatCallKitManagerImpl: onJoinChannelSuccess called");
    if (_chat.model.curCall == null) return;

    await setDefaultModeType();
    tools.log("ChatCallKitManagerImpl: setDefaultModeType called");

    _chat.onCurrentUserJoined();
    tools.log("ChatCallKitManagerImpl: onCurrentUserJoined called");

    if (_chat.model.curCall != null) {
      String channel = _chat.model.curCall!.channel;
      tools.log("ChatCallKitManagerImpl: onJoinedChannel called, channel: $channel");

      for (var value in handlers) {
        value.onJoinedChannel.call(channel);
      }
    }
  }

  void onLeaveChannel() {
    tools.log("ChatCallKitManagerImpl: onLeaveChannel called");
    _chat.model.curCall = null;
  }

  void onUserJoined(int remoteUid) async {
    tools.log("ChatCallKitManagerImpl: onUserJoined called, remoteUid: $remoteUid");
    ChatCallKitUserMapper? mapper = await updateUserMapper(remoteUid);
    if (_chat.model.curCall != null) {
      if (_chat.model.curCall?.callType == ChatCallKitCallType.multi) {
        mapper?.infoMapper.forEach((key, value) {
          _chat.callTimerDic.remove(value)?.cancel();
        });
      } else {
        _chat.callTimerDic
            .remove(_chat.model.curCall!.remoteUserAccount)
            ?.cancel();
      }

      for (var value in handlers) {
        value.onUserJoined.call(remoteUid, mapper?.infoMapper[remoteUid]);
      }
    }
  }

  void onUserLeaved(int remoteUid) {
    tools.log("ChatCallKitManagerImpl: onUserLeaved called, remoteUid: $remoteUid");
    if (_chat.model.curCall != null) {
      String? userId = _chat.model.curCall?.allUserAccounts.remove(remoteUid);
      for (var value in handlers) {
        value.onUserLeaved.call(remoteUid, userId);
      }
      if (_chat.model.curCall!.callType != ChatCallKitCallType.multi) {
        if (_chat.model.curCall != null) {
          for (var value in handlers) {
            value.onCallEnd.call(
                _chat.model.curCall!.callId, ChatCallKitCallEndReason.hangup);
          }
        }

        _chat.clearInfo();
      }
    }
  }

  void onUserMuteVideo(int remoteUid, bool muted) {
    tools.log("ChatCallKitManagerImpl: onUserMuteVideo called, remoteUid: $remoteUid, muted: $muted");
    if (_chat.model.curCall != null) {
      for (var value in handlers) {
        value.onUserMuteVideo.call(remoteUid, muted);
      }
    }
  }

  void onUserMuteAudio(int remoteUid, bool muted) {
    tools.log("ChatCallKitManagerImpl: onUserMuteAudio called, remoteUid: $remoteUid, muted: $muted");
    if (_chat.model.curCall != null) {
      for (var value in handlers) {
        value.onUserMuteAudio.call(remoteUid, muted);
      }
    }
  }

  void onFirstRemoteVideoDecoded(int remoteUid, int width, int height) {
    // String? userId = _chat.model.curCall!.allUserAccounts[remoteUid];
    // if (_chat.model.curCall != null) {
    //   handlerMap.forEach((key, value) {
    //     value.onFirstRemoteVideoDecoded?.call(remoteUid, userId, width, height);
    //   });
    // }
  }

  void onRemoteVideoStateChanged(
      int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason) {}

  void onActiveSpeaker(int uid) {
    // String? userId = _chat.model.curCall!.allUserAccounts[uid];
    // handlerMap.forEach((key, value) {
    //   value.onActiveSpeaker?.call(uid, userId);
    // });
  }

  void onRTCError(ErrorCodeType err, String desc) {
    tools.log("ChatCallKitManagerImpl: onRTCError called, err: $err, desc: $desc");
    if (err == ErrorCodeType.errTokenExpired ||
        err == ErrorCodeType.errInvalidToken ||
        err == ErrorCodeType.errFailed) {
      for (var value in handlers) {
        if (err == ErrorCodeType.errTokenExpired) {
          value.onError.call(ChatCallKitError.rtc(err.index, "Token expired"));
        } else if (err == ErrorCodeType.errInvalidToken) {
          value.onError.call(ChatCallKitError.rtc(err.index, "Invalid token"));
        } else {
          value.onError.call(ChatCallKitError.rtc(err.index,
              "General error with no classified reason. Try calling the method again"));
        }
      }
    } else {
      if (err == ErrorCodeType.errFailed) {
        for (var value in handlers) {
          value.onError.call(ChatCallKitError.rtc(
              ChatCallKitErrorProcessCode.general,
              "General error with no classified reason. Try calling the method again"));
        }
      }

      for (var value in handlers) {
        value.onCallEnd
            .call(_chat.model.curCall?.callId, ChatCallKitCallEndReason.err);
      }
    }
    _chat.clearInfo();
  }
}

extension RTCAction on ChatCallKitManagerImpl {
  Future<void> startPreview() => _rtc.startPreview();
  Future<void> stopPreview() => _rtc.stopPreview();
  Future<void> switchCamera() => _rtc.switchCamera();
  Future<void> enableLocalView() => _rtc.enableLocalView();
  Future<void> disableLocalView() => _rtc.disableLocalView();
  Future<void> enableAudio() => _rtc.enableAudio();
  Future<void> disableAudio() => _rtc.disableAudio();
  Future<void> enableVideo() => _rtc.enableVideo();
  Future<void> disableVideo() => _rtc.disableVideo();
  Future<void> mute() => _rtc.mute();
  Future<void> unMute() => _rtc.unMute();
  Future<void> speakerOn() => _rtc.enableSpeaker();
  Future<void> speakerOff() => _rtc.disableSpeaker();

  AgoraVideoView? getLocalVideoView() {
    return _rtc.localView();
  }

  AgoraVideoView? getRemoteVideoView(int agoraUid) {
    if (_chat.model.curCall != null) {
      String channel = _chat.model.curCall!.channel;
      return _rtc.remoteView(agoraUid, channel);
    }
    return null;
  }

  List<AgoraVideoView> getRemoteVideoViews() {
    List<AgoraVideoView> list = [];
    return list;
  }
}
