## 0.2.0
- iOS: Add Swift Package Manager support: the plugin source moves to the SPM `Sources/` layout with a new `Package.swift`; CocoaPods integration is unchanged.
- iOS: Raise the plugin shell podspec deployment target from 11.0 to 13.0, aligning with the minimum iOS requirement of the Chat SDK and the SPM configuration.

## 0.1.0
- Versioning: Re-release the 0.0.5 Chat SDK 5.0 adaptation as 0.1.0 to mark the integration break from 0.0.4 and earlier, per Dart/pub 0.x conventions; the public CallKit API is unchanged from 0.0.5.
- Dependencies: Continue to depend on the Chat SDK `^5.0.0`; constrain the RTC dependency to `agora_rtc_engine '>=6.5.1 <6.6.0'` to allow 6.5.x patch upgrades and exclude 6.6.x, which has incompatible callback signatures.
- Example: Fix the `Framework 'aosl' not found` error caused by leftover link parameters after iOS AOSL deduplication; keep the higher-versioned AOSL.
- Migration from 0.0.4 and earlier: Password login and `autoLogin` via the public SDK types have been removed; the app must log in explicitly with a token on every start.
- Migration from 0.0.4 and earlier: Applications that display contacts must enable contact data synchronization and read local data with `getAllContacts()`; see `example/`.
- Docs: Correct the minimum iOS version in the README to 13.0, matching the SDK requirement.
- Packaging: Scope the `pubspec.lock` ignore rule to the library root; keep tracking and packaging the example lock file.

## 0.0.5 (Retracted; superseded by 0.1.0)
- Upgrade the Chat SDK dependency to `^5.0.0`; sync iOS `HyphenateChat` to 5.0.0.
- Adapt to token-only login in 5.0.0: the example now logs in manually with a token on each start; automatic login, password login, and the old register-for-token flow are removed.
- Adapt to the 5.0.0 contact local-data APIs: enable conversation and contact data synchronization and use `getAllContacts()`.
- Docs: Update dependency versions and example configuration in the README.

## 0.0.4
- Upgrade the Chat SDK dependency to `^4.25.0`.
- Revert tracking the root `pubspec.lock` (started in 0.0.3): the root lock file leaves git tracking (the local file is kept), following the Dart convention that library packages do not commit `pubspec.lock`.
- The example project `example/pubspec.lock` remains tracked.

## 0.0.3
- Upgrade the Chat SDK dependency to `^4.22.0`.
- Upgrade the example Android build toolchain for Flutter 3.47 (Gradle 8.14.3 / AGP 8.13.0 / KGP 2.3.0); example build configuration only.
- Start tracking the root `pubspec.lock` so dependencies stay reproducible after long idle periods.

## 0.0.2-beta.1
- Bump the version to 0.0.2-beta.1.
- Adjust the RTC engine initialization logic and add initialization logging.
- Adjust the RTC log storage directory.

## 0.0.2+2
- Bump the version to 0.0.2+2.

## 0.0.2+1
- Pin the Chat SDK and its dependent plugins to 4.15.2.

## 0.0.2
- Pin the Chat SDK and its dependent plugins to 4.13.0+1.
- Add file logging; toggle it via `enableLog` in `chat_callkit_tools.dart`.

## 0.0.1

* Initial release.
