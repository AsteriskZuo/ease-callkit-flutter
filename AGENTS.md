# AGENTS.md

`em_chat_callkit` is a Flutter plugin that coordinates Easemob IM signaling with the Agora RTC engine for one-to-one and multi-party audio/video calls. This document describes the repository's current architecture and development constraints. The code remains the source of truth for implementation details.

## Document Baseline

| Item | Current value |
|---|---|
| Package version | `0.1.0` |
| `im_flutter_sdk` | `^5.0.0` |
| `agora_rtc_engine` | `6.5.1` |
| Dart | `>=3.0.0 <4.0.0` |
| Flutter | `>=3.3.0` |

This file is versioned operating documentation. Whenever the package version or any dependency listed above changes in `pubspec.yaml`, update this table in the same change. Also update architecture or validation guidance when the release changes behavior, platform support, or integration steps. The example application's own version is independent from the package release version.

## Collaboration Conventions

- When the investigation direction is unclear, or the same problem remains unresolved for more than a few minutes, share the symptoms and current hypotheses with the user before continuing.
- Keep changes scoped to the requested behavior. Call signaling and RTC lifecycle changes have cross-device effects, so state the affected incoming, outgoing, one-to-one, and multi-party paths explicitly.
- Do not commit or push unless the user authorizes it.

### Work Log

- After completing a task, making an important decision, or receiving a correction from the user, append an entry to `dailylog/YYYY-MM-DD.md` using the local date. Create the file if it does not exist.
- Append only; do not modify existing content. Format each entry as: `- HH:MM <what was done or decided>, reason: <...>`.
- Logs may record progress and process details.
- Track work logs under `dailylog/` in Git; do not add the directory to `.gitignore`. When making a user-authorized Git commit, include the log changes from the current work. Logging itself does not trigger a commit or push.

## Architecture

| Path | Responsibility |
|---|---|
| `lib/chat_callkit.dart` | Public barrel file; every supported public type must be exported here |
| `lib/chat_callkit_manager.dart` | Static public facade for call control, media actions, handlers, and observers |
| `lib/chat_callkit_define.dart` | Public enums, callback typedefs, and call state definitions |
| `lib/chat_callkit_observer.dart` | Public call event observer contract |
| `lib/chat_callkit_error.dart` | Public error model and error codes |
| `lib/inherited/chat_callkit_manager_impl.dart` | Orchestrates IM signaling, RTC, call state, token lookup, user mapping, and observer delivery |
| `lib/inherited/chat_callkit_chat_manager.dart` | Implements the IM signaling protocol, timers, multi-device arbitration, and call state transitions |
| `lib/inherited/chat_callkit_rtc_manager.dart` | Owns RTC engine initialization, channel membership, media controls, video views, and RTC callbacks |
| `lib/inherited/chat_callkit_call_model.dart` | Holds the current call, received calls, device id, RTC uid, and state |
| `lib/inherited/tools/call_define.dart` | Isolates IM SDK type names behind `ChatCallKit*` typedefs |
| `lib/inherited/widgets/chat_callkit.dart` | Configures the RTC App ID and call timeout from the widget tree |
| `example/` | Runnable integration example for login, token callbacks, user mapping, and call UI |
| `android/`, `ios/` | Flutter plugin shells and platform deployment configuration; call behavior remains in Dart |
| `scripts/` | Domestic-to-overseas CallKit synchronization tool and its Node test suite |

The main runtime flow is:

`ChatCallKitManager` -> `ChatCallKitManagerImpl` -> IM signaling in `AgoraChatManager` + media in `AgoraRTCManager` -> `ChatCallKitObserver` callbacks.

An application initializes the IM client, places `ChatCallKit` above call UI, registers the RTC token and user-mapping handlers, and adds an observer. Signaling messages move the call model through `idle`, `outgoing`, `alerting`, and `answering`; the manager implementation starts or clears RTC resources in response.

## Ownership Boundaries

- Keep the public facade in `ChatCallKitManager` thin. Business logic belongs in the manager implementation or the dedicated IM/RTC manager.
- Keep IM SDK naming isolated in `lib/inherited/tools/call_define.dart`. Add or update aliases there instead of importing `im_flutter_sdk` throughout the package.
- Keep signaling behavior in `chat_callkit_chat_manager.dart` and RTC behavior in `chat_callkit_rtc_manager.dart`. `chat_callkit_manager_impl.dart` coordinates the two domains.
- Treat signaling attribute names and action values such as `msgType`, `callId`, `callerDevId`, `confirmRing`, and `confirmCallee` as a wire protocol. A change must update every sender and parser and remain compatible with the intended peer versions.
- Keep Android and iOS plugin classes free of duplicated call logic unless a platform API truly requires native implementation.

## Lifecycle And State Rules

- Initialize `ChatCallKitClient` and explicitly log in with a token before starting or receiving calls. SDK 5.0 removes password login and automatic login; CallKit 0.1.0 marks this integration break from 0.0.4 and earlier. Configure `ChatCallKit` with a valid RTC App ID before RTC initialization.
- `initRTC()` and `releaseRTC()` are a lifecycle pair. Release the engine after the call flow no longer needs it.
- Register `RtcTokenHandler` and `UserMapperHandler` before a call can join an RTC channel. Preserve the callback contracts: the token handler maps a token to an RTC uid, and the mapper resolves RTC uids to IM user ids for the same channel.
- Add and remove the same `ChatCallKitObserver` instance symmetrically, normally in `initState` and `dispose`.
- Drive call transitions through `ChatCallKitCallModel.state`; its callback is what coordinates signaling cleanup and RTC work.
- Preserve timeout cleanup and multi-device arbitration when changing invitation, alert, answer, cancel, or confirmation handling. Clear timers and per-call state when returning to `idle`.
- Keep RTC initialization idempotent. Concurrent callers share `_engineInitializing`, and failed initialization must leave the engine retryable.

## Public API Changes

- Export new public APIs from `lib/chat_callkit.dart` and document them in English, matching the existing public API documentation.
- Reuse the existing manager, observer, error, enum, and model surfaces before adding another public abstraction.
- When changing callbacks or call behavior, update the example and README snippets together with the implementation.
- Record release-visible changes in `CHANGELOG.md`.
- Use the package version as the release branch/version source. When changing `version:` in `pubspec.yaml`, update the Document Baseline in this file in the same change.

## Cross-Repository Synchronization

This repository is the Easemob source for the overseas CallKit mirror. `scripts/sync_callkit.js` mirrors the source tree and applies package, SDK, plugin-class, path, homepage, and license replacements for the Agora repository.

- Keep Easemob names in this source repository; let the synchronization script produce Agora-specific names in the target repository.
- Keep replacement-sensitive names and `call_define.dart` handling covered by `scripts/sync_callkit.test.js`.
- The synchronization command requires a clean source repository and no tracked changes in the target repository. Run it only as part of an explicit synchronization task because it cleans and replaces the target contents.
- Run `node --test scripts/sync_callkit.test.js` after changing synchronization behavior or replacement-sensitive package structure.

## Code And Repository Conventions

- Follow `flutter_lints` and existing Dart naming: snake_case files, UpperCamelCase types, and lowerCamelCase members.
- Use `tools.log` for CallKit diagnostic output so signaling and RTC events share the same log path.
- Await operations whose ordering affects state, engine setup, channel membership, or cleanup. Do not silently detach asynchronous lifecycle work.
- Keep observer iteration tolerant of multiple listeners and prevent duplicate registration where the current API already does so.
- The root `pubspec.lock` is intentionally untracked for this library package; `example/pubspec.lock` is tracked for reproducible example builds.
- Android currently uses minSdk 24. The IM SDK dependency requires iOS 13.0 or later, as documented in the README. The thin plugin shell's podspec still declares iOS 11.0; this does not lower the SDK requirement. The example targets iOS 15.0.

## Validation

Run validation from this repository, not from the parent workspace.

- For Dart-only changes: run `flutter pub get`, `flutter analyze`, then run `flutter pub get` and `flutter analyze` in `example/`.
- For signaling or lifecycle changes: manually cover outgoing and incoming calls, answer, reject, cancel, timeout, hangup, and a second-device response as applicable.
- For RTC changes: cover audio and video, mute/unmute, speaker routing, camera switching, local/remote video views, join failure, and engine release on Android and iOS as applicable.
- For dependency or platform changes: build or run the example on every affected platform.
- `example/test/widget_test.dart` is still the generated counter test and does not exercise this package; do not cite it as CallKit coverage.
