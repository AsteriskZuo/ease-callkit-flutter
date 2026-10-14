## 0.0.5
- 升级依赖 `im_flutter_sdk` 为 `^5.0.0`，同步更新 iOS `HyphenateChat` 至 5.0.0；
- 适配 5.0.0 仅支持 Token 登录的变更：示例工程改为每次手动 Token 登录，并移除自动登录、密码登录及旧注册换 Token 流程；
- 适配 5.0.0 联系人本地数据 API：启用会话和联系人数据同步，使用 `getAllContacts()` 获取联系人；
- 更新 README 中的依赖版本与示例配置。

## 0.0.4
- 升级 依赖 im_flutter_sdk 为 ^4.25.0；
- 撤销 0.0.3 开始追踪根目录 pubspec.lock 的做法：根目录 pubspec.lock 退出 git 追踪（本地文件保留），遵循 Dart 库包不提交 pubspec.lock 的约定；
- 示例工程 example/pubspec.lock 仍保持 git 追踪。

## 0.0.3
- 升级 依赖 im_flutter_sdk 为 ^4.22.0；
- 升级 example 的 Android 构建工具链以适配 Flutter 3.47（Gradle 8.14.3 / AGP 8.13.0 / KGP 2.3.0），仅示例工程构建配置；
- 开始追踪根目录 pubspec.lock，保证长期搁置后依赖可复现、可构建。

## 0.0.2-beta.1
- 更新版本为0.0.2-beta.1
- 调整初始化RTC engine部分逻辑, 增加初始化部分log记录
- 调整RTC log存放目录

## 0.0.2+2
- 更新版本为0.0.2+2

## 0.0.2+1
- 使用im_flutter_sdk及其依赖插件固定版本为4.15.2

## 0.0.2
- 使用im_flutter_sdk及其依赖插件固定版本为4.13.0+1
- 添加日志写入文件功能, 开关日志功能请设置 `chat_callkit_tools.dart` 中的 `enableLog`

## 0.0.1

* 初次发版
