import 'dart:math';
import 'dart:developer' as developer;

import 'chat_callkit_log.dart';

bool enableLog = true;

log(String log) {
  if (enableLog) {
    // developer.log(log, name: 'ChatCallKit');
    ChatCallKitLogger.instance.log(log);
  }
}

class ChatCallKitTools {
  static String get randomStr {
    return "flutter_${Random().nextInt(99999999).toString()}";
  }
}
