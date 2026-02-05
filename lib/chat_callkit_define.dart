import 'inherited/models/chat_callkit_user_mapper.dart';

/// Call type
enum ChatCallKitCallType {
  audio_1v1,
  video_1v1,
  multi,
}

typedef ChatCallKitStateChange = void Function(
  ChatCallKitCallState newState,
  ChatCallKitCallState preState,
);

/// End of call cause
enum ChatCallKitCallEndReason {
  hangup,
  cancel,
  remoteCancel,
  refuse,
  remoteRefuse,
  busy,
  remoteNoResponse,
  handleOnOtherDevice,
  err,
}

/// Call error type
enum ChatCallKitErrorType {
  process,
  rtc,
  im,
}

/// Call error code
class ChatCallKitErrorProcessCode {
  static int general = 1;
  static int invalidParam = 100;
  static int busy = 101;
  static int fetchTokenFail = 102;
}

enum ChatCallKitCallState {
  idle,
  outgoing,
  alerting,
  answering,
}

/// Returns a Map where key is agoraToken and value is agoraUid
typedef RtcTokenHandler = Future<Map<String, int>> Function(
  String channel,
  String agoraAppId,
);

/// Returns a ChatCallKitUserMapper, See [ChatCallKitUserMapper]
typedef UserMapperHandler = Future<ChatCallKitUserMapper?> Function(
  String channel,
  int agoraUid,
);
