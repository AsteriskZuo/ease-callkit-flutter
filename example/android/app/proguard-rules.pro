-keep class com.hyphenate.** { *; }
-dontwarn com.hyphenate.**

# Optional vendor push SDKs referenced by HyphenateChat.
-dontwarn com.heytap.msp.push.HeytapPushManager
-dontwarn com.heytap.msp.push.callback.ICallBackResultService
-dontwarn com.meizu.cloud.pushsdk.PushManager
-dontwarn com.meizu.cloud.pushsdk.util.MzSystemUtils
-dontwarn com.vivo.push.IPushActionListener
-dontwarn com.vivo.push.PushClient
-dontwarn com.vivo.push.PushConfig$Builder
-dontwarn com.vivo.push.PushConfig
-dontwarn com.vivo.push.util.VivoPushException
-dontwarn com.xiaomi.mipush.sdk.MiPushClient
