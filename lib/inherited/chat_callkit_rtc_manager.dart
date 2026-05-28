import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:em_chat_callkit/chat_callkit.dart';
import 'package:em_chat_callkit/inherited/tools/chat_callkit_log.dart';
import 'package:em_chat_callkit/inherited/tools/chat_callkit_tools.dart'
    as tools;
import 'package:flutter/material.dart';

class RTCOptions {
  final AudioScenarioType? audioScenarioType;
  final ChannelProfileType? channelProfile;
  final int? areaCode;
  final VideoEncoderConfiguration? videoEncoderConfig;
  final AudioSessionOperationRestriction? audioSessionOperationRestriction;

  RTCOptions({
    this.audioScenarioType,
    this.channelProfile,
    this.areaCode,
    this.videoEncoderConfig,
    this.audioSessionOperationRestriction,
  });
}

class RTCEventHandler {
  RTCEventHandler({
    this.onError,
    this.onJoinChannelSuccess,
    this.onLeaveChannel,
    this.onUserJoined,
    this.onUserLeaved,
    this.onUserMuteVideo,
    this.onUserMuteAudio,
    this.onFirstRemoteVideoDecoded,
    this.onRemoteVideoStateChanged,
    this.onActiveSpeaker,
  });

  final void Function(
    ErrorCodeType err,
    String msg,
  )? onError;

  final VoidCallback? onJoinChannelSuccess;
  final VoidCallback? onLeaveChannel;
  final void Function(int remoteUid)? onUserJoined;
  final void Function(int userId)? onUserLeaved;
  final void Function(int remoteUid, bool muted)? onUserMuteVideo;
  final void Function(int remoteUid, bool muted)? onUserMuteAudio;
  final void Function(int remoteUid, int width, int height)?
      onFirstRemoteVideoDecoded;
  final void Function(
          int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason)?
      onRemoteVideoStateChanged;
  final void Function(int uid)? onActiveSpeaker;
}

class AgoraRTCManager {
  void rtcLog(String method, ChatCallKitMessage msg) {
    tools.log(
        "AgoraRTCManager: rtc method: $method, ${msg.toJson().toString()}");
  }

  AgoraRTCManager(
    this.handler,
  ) {
    _handler = RtcEngineEventHandler(
      onUserEnableLocalVideo: (connection, remoteUid, enabled) {},
      onUserEnableVideo: (connection, remoteUid, enabled) {},
      onLocalVideoStats: (connection, stats) {},
      onVideoDeviceStateChanged: (deviceId, deviceType, deviceState) {},
      onVideoStopped: () {},
      onLocalVideoStateChanged: (source, state, error) {},
      onRemoteVideoStats: (connection, stats) {},
      onVideoPublishStateChanged:
          (source, channel, oldState, newState, elapseSinceLastState) {},
      onVideoSizeChanged:
          (connection, sourceType, uid, width, height, rotation) {},
      onVideoSubscribeStateChanged:
          (channel, uid, oldState, newState, elapseSinceLastState) {},
      onError: (err, msg) {
        handler.onError?.call(ErrorCodeType.errFailed, msg);
      },
      onJoinChannelSuccess: (connection, elapsed) {
        handler.onJoinChannelSuccess?.call();
      },
      onLeaveChannel: (connection, stats) {
        handler.onLeaveChannel?.call();
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        handler.onUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        handler.onUserLeaved?.call(remoteUid);
      },
      onUserMuteVideo: (
        connection,
        remoteUid,
        muted,
      ) {
        handler.onUserMuteVideo?.call(remoteUid, muted);
      },
      onUserMuteAudio: (
        connection,
        remoteUid,
        muted,
      ) {
        handler.onUserMuteAudio?.call(remoteUid, muted);
      },
      onFirstRemoteVideoDecoded: (
        connection,
        remoteUid,
        width,
        height,
        elapsed,
      ) {
        handler.onFirstRemoteVideoDecoded?.call(remoteUid, width, height);
      },
      onRemoteVideoStateChanged: (
        connection,
        remoteUid,
        state,
        reason,
        elapsed,
      ) {
        handler.onRemoteVideoStateChanged?.call(remoteUid, state, reason);
      },
      onActiveSpeaker: (
        connection,
        uid,
      ) {
        handler.onActiveSpeaker?.call(uid);
      },
    );
  }
  bool _engineHasInit = false;
  Future<void>? _engineInitializing;
  RTCOptions? options;
  String? agoraAppId;
  late RtcEngine _engine;
  final RTCEventHandler handler;
  RtcEngineEventHandler? _handler;

  Future<void> initEngine() async {
    tools.log("AgoraRTCManager: in initEngine, engineHasInit: $_engineHasInit");
    tools.log("AgoraRTCManager: in initEngine, engineInitializing: $_engineInitializing");

    if (_engineHasInit) return;
    if (_engineInitializing != null) return _engineInitializing;

    tools.log("AgoraRTCManager: in initEngine, called");

    _engineInitializing = _initEngine();
    try {
      await _engineInitializing;
    } finally {
      _engineInitializing = null;
    }

    tools.log("AgoraRTCManager: in initEngine, end");
  }

  Future<void> _initEngine() async {
    RtcEngine? engine;
    try {
      final String callkitLogPath =
          await ChatCallKitLogger.instance.getCurrentLogFilePath();
      final String rtcLogPath =
          '${File(callkitLogPath).parent.path}/agorasdk.log';
      tools.log("AgoraRTCManager: in _initEngine, rtc log path: $rtcLogPath");
      engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(
        appId: agoraAppId,
        audioScenario: options?.audioScenarioType,
        channelProfile: options?.channelProfile,
        areaCode: options?.areaCode,
        logConfig: LogConfig(
          filePath: rtcLogPath,
          fileSizeInKB: defaultLogSizeInKb,
          level: LogLevel.logLevelInfo,
        ),
      ));
      tools.log("AgoraRTCManager: in _initEngine, engine initialized");

      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      tools.log("AgoraRTCManager: in _initEngine, client role set");

      await engine
          .setChannelProfile(ChannelProfileType.channelProfileLiveBroadcasting);
      tools.log("AgoraRTCManager: in _initEngine, channel profile set");

      await engine.setDefaultAudioRouteToSpeakerphone(true);
      tools.log("AgoraRTCManager: in _initEngine, default audio route set to speakerphone");

      engine.unregisterEventHandler(_handler!);
      engine.registerEventHandler(_handler!);
      tools.log("AgoraRTCManager: in _initEngine, event handler registered");

      _engine = engine;
      _engineHasInit = true;
    } on AgoraRtcException catch (e) {
      _engineHasInit = false;
      tools.log(
        "AgoraRTCManager: in _initEngine, failed, code: ${e.code}, message: ${e.message}",
      );
      try {
        await engine?.release();
      } catch (_) {}
      rethrow;
    } catch (e) {
      _engineHasInit = false;
      tools.log("AgoraRTCManager: in initEngine, failed: $e");
      try {
        await engine?.release();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> releaseEngine() async {
    tools.log("AgoraRTCManager: in releaseEngine, engineInitializing: $_engineInitializing");
    tools.log("AgoraRTCManager: in releaseEngine, engineHasInit: $_engineHasInit");
    if (_engineInitializing != null) {
      try {
        await _engineInitializing;
      } catch (_) {
        return;
      }
    }

    tools.log("AgoraRTCManager: in releaseEngine, engineHasInit: $_engineHasInit");

    if (_engineHasInit) {
      tools.log("AgoraRTCManager: in releaseEngine, set engineHasInit to false");
      _engineHasInit = false;
      try {
        tools.log("AgoraRTCManager: in releaseEngine, release engine");
        await _engine.release();
        tools.log("AgoraRTCManager: in releaseEngine, engine released");
        // ignore: empty_catches
      } catch (e) {
        tools.log("AgoraRTCManager: in releaseEngine, release failed: $e");
      }
    }
  }

  void dispose() async {
    await releaseEngine();
  }

  Future<void> joinChannel(
    ChatCallKitCallType type,
    String token,
    String channel,
    int uid,
  ) async {
    tools.log("AgoraRTCManager: joinChannel, called");
    try {
      await _engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(),
      );
    } catch (e) {
      tools.log("AgoraRTCManager: joinChannel failed: $e");
      handler.onError?.call(ErrorCodeType.errFailed,
          "General error with no classified reason. Try calling the method again");
    }
  }

  Future<void> leaveChannel() async {
    tools.log("AgoraRTCManager: in leaveChannel, engineHasInit: $_engineHasInit");
    if (!_engineHasInit) {
      tools.log("AgoraRTCManager: in leaveChannel, engineHasInit is false, return");
      return;
    }
    try {
      tools.log("AgoraRTCManager: in leaveChannel, called");
      await _engine.leaveChannel();
      // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> clearCurrentCallInfo() async {
    try {
      await leaveChannel();
      await stopPreview();
      await disableAudio();
      // ignore: empty_catches
    } catch (e) {}
  }
}

extension EngineActions on AgoraRTCManager {
  Future<void> initRTC() {
    return initEngine();
  }

  Future<void> releaseRTC() {
    return releaseEngine();
  }

  Future<void> enableVideo() async {
    if (!_engineHasInit) return;
    await _engine.enableVideo();
  }

  Future<void> disableVideo() async {
    if (!_engineHasInit) return;
    await _engine.disableVideo();
  }

  Future<void> enableAudio() async {
    if (!_engineHasInit) return;
    await _engine.enableAudio();
  }

  Future<void> disableAudio() async {
    if (!_engineHasInit) return;
    await _engine.disableAudio();
  }

  Future<void> mute() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalAudio(false);
  }

  Future<void> unMute() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalAudio(true);
  }

  Future<void> enableSpeaker() async {
    if (!_engineHasInit) return;
    await _engine.setEnableSpeakerphone(true);
  }

  Future<void> disableSpeaker() async {
    if (!_engineHasInit) return;
    await _engine.setEnableSpeakerphone(false);
  }

  Future<void> startPreview() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalVideo(true);
    await _engine.startPreview();
  }

  Future<void> stopPreview() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalVideo(false);
    await _engine.stopPreview();
  }

  Future<void> switchCamera() async {
    if (!_engineHasInit) return;
    await _engine.switchCamera();
  }

  Future<void> enableLocalView() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalVideo(true);
  }

  Future<void> disableLocalView() async {
    if (!_engineHasInit) return;
    await _engine.enableLocalVideo(false);
  }

  AgoraVideoView? remoteView(int agoraUid, String channel) {
    if (!_engineHasInit) return null;
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: VideoCanvas(uid: agoraUid),
        connection: RtcConnection(channelId: channel),
      ),
    );
  }

  AgoraVideoView? localView() {
    if (!_engineHasInit) return null;

    return AgoraVideoView(
      key: const ValueKey("0"),
      controller: VideoViewController(
        rtcEngine: _engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }
}
