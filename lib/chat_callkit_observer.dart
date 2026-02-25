import 'package:em_chat_callkit/chat_callkit.dart';
import 'package:em_chat_callkit/inherited/chat_callkit_call.dart';

abstract mixin class ChatCallKitObserver {
  /// Callback when the call fails, See [ChatCallKitError].

  void onError(ChatCallKitError error) {}

  /// Callback when the call ends, See [ChatCallKitCallEndReason].

  void onCallEnd(ChatCallKitCall? call, ChatCallKitCallEndReason reason) {}

  /// Callback when you receive a call invitation.

  void onReceiveCall(
    String userId,
    String callId,
    ChatCallKitCallType callType,
    Map<String, String>? ext,
  ) {}

  void onInviteMessageWillSend(ChatCallKitMessage message) {}

  /// Callback when the current user joins the call.

  void onJoinedChannel(String channel) {}

  /// Callback when an active user leaves.

  void onUserLeaved(int agoraUid, String? userId) {}

  /// Callback when a user joins a call.

  void onUserJoined(int agoraUid, String? userId) {}

  /// Callback when the peer's mute status changes.

  void onUserMuteAudio(int agoraUid, bool muted) {}

  /// Callback when the peer's camera status changes.

  void onUserMuteVideo(int agoraUid, bool muted) {}

  /// Callback when the user rejects the call or the call times out.

  void onUserRemoved(
      String callId, String userId, ChatCallKitCallEndReason reason) {}

  /// Callback when the call is answered.

  void onAnswer(String callId) {}
}
