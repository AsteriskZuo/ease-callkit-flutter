import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:em_chat_callkit/chat_callkit.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_chat_manager.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_rtc_manager.dart';

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
    return _rtc.initRTC();
  }

  Future<void> releaseRTC() {
    return _rtc.releaseRTC();
  }

  Future<String> startSingleCall(
    String userId, {
    String? inviteMessage,
    ChatCallKitCallType type = ChatCallKitCallType.audio_1v1,
    Map<String, String>? ext,
  }) {
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
    return _chat.startInviteUsers(userIds, inviteMessage, ext);
  }

  Future<void> answerCall(String callId) {
    return _chat.answerCall(callId);
  }

  Future<void> hangup(String callId) async {
    await _chat.hangup(callId);
  }

  Future<void> answer(String callId) async {
    return _chat.answerCall(callId);
  }

  void addEventListener(ChatCallKitObserver handler) {
    if (handlers.contains(handler)) return;
    handlers.add(handler);
  }

  void removeEventListener(ChatCallKitObserver handler) {
    handlers.remove(handler);
  }

  void clearAllEventListeners() {
    handlers.clear();
  }

  Future<void> fetchToken() async {
    if (_chat.model.hasJoined) return;
    if (_chat.model.curCall == null ||
        _rtc.agoraAppId == null ||
        rtcTokenHandler == null) return;

    Map<String, int> agoraToken = await rtcTokenHandler!.call(
      _chat.model.curCall!.channel,
      _rtc.agoraAppId!,
    );

    if (agoraToken.isEmpty) {
      throw ChatCallKitError.process(
          ChatCallKitErrorProcessCode.fetchTokenFail, 'fetch token fail');
    }

    if (_chat.model.curCall == null) {}

    String? username = ChatCallKitClient.getInstance.currentUserId;

    if (username == null) return;

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
          await _chat.clearCurrentCallInfo();
          await _rtc.clearCurrentCallInfo();
        }
        break;
      case ChatCallKitCallState.outgoing:
        {
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
          if (_chat.model.curCall == null) return;
          await _rtc.initEngine();
          if (_chat.model.curCall != null) {
            if (_chat.model.curCall!.callType !=
                ChatCallKitCallType.audio_1v1) {
              await _rtc.enableVideo();
              await _rtc.startPreview();
            }

            for (var value in handlers) {
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
          if (_chat.model.curCall == null) return;
          if (_chat.model.curCall!.callType == ChatCallKitCallType.multi &&
              _chat.model.curCall!.isCaller) {
            // 多人主叫时，需要开启摄像头
            await _rtc.enableVideo();
            await _rtc.startPreview();
            try {
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
      await fetchToken();
    } on ChatCallKitError catch (e) {
      onError(e);
    }
  }

  void onCallEndReason(String callId, ChatCallKitCallEndReason reason) {
    for (var value in handlers) {
      value.onCallEnd.call(callId, reason);
    }
  }

  void onAnswer(String callId) {
    for (var value in handlers) {
      value.onAnswer.call(callId);
    }
  }

  void onError(ChatCallKitError error) {
    for (var value in handlers) {
      value.onError.call(error);
    }
  }

  void onUserRemoved(
      String callId, String userId, ChatCallKitCallEndReason reason) {
    for (var value in handlers) {
      value.onUserRemoved.call(callId, userId, reason);
    }
  }
}

extension RTCEvent on ChatCallKitManagerImpl {
  void onJoinChannelSuccess() async {
    if (_chat.model.curCall == null) return;
    await setDefaultModeType();
    _chat.onCurrentUserJoined();
    if (_chat.model.curCall != null) {
      String channel = _chat.model.curCall!.channel;
      for (var value in handlers) {
        value.onJoinedChannel.call(channel);
      }
    }
  }

  void onLeaveChannel() {
    _chat.model.curCall = null;
  }

  void onUserJoined(int remoteUid) async {
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
    if (_chat.model.curCall != null) {
      for (var value in handlers) {
        value.onUserMuteVideo.call(remoteUid, muted);
      }
    }
  }

  void onUserMuteAudio(int remoteUid, bool muted) {
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
