# example

A runnable integration example for CallKit: login, RTC token callback, user
mapping, and the call UI.

To run it, fill in `lib/config.dart` with your own values:

```dart
class Config {
  static String agoraAppId = "";
  static String appkey = "";
  static String appServerDomain = "";
  static String appServerRTCTokenURL = "";
  static String appServerUserMapperURL = "";
}
```

- `appkey`: Your Chat App Key.
- `agoraAppId`: Your Agora RTC App ID.
- `appServerRTCTokenURL` / `appServerUserMapperURL`: Your app server endpoints
  that issue RTC tokens and map RTC UIDs to Chat user IDs.

Then run `flutter run` from this directory.
