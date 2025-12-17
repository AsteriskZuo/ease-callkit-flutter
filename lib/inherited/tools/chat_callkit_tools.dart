import 'dart:math';
import 'dart:developer' as developer;

bool enableLog = true;

log(String log) {
  if (enableLog) {
    developer.log(log, name: 'ChatCallKit');
  }
}

class ChatCallKitTools {
  static String get randomStr {
    return "flutter_${Random().nextInt(99999999).toString()}";
  }
}
