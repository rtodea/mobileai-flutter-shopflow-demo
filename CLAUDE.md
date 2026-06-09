# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

A Flutter demo app (**ShopFlow**, an e-commerce sample) that exercises the
[`mobileai_flutter`](https://pub.dev/packages/mobileai_flutter) SDK — an in-app,
UI-aware AI agent with text + voice and screen-aware navigation. It is adapted
from that package's official `example/` app. It declares the **published**
package (`mobileai_flutter: ^0.2.7`) but actually builds against a patched
vendored copy at `third_party/mobileai_flutter` via `dependency_overrides`
(see gotchas below).

## Commands

- Install deps: `flutter pub get`
- Static analysis: `flutter analyze` (keep it clean)
- Tests: `flutter test`; e2e: `flutter test integration_test`
- Run: `flutter run -d chrome` (web), `-d windows`, `-d macos`, or a device id
- Build: `flutter build web` / `apk` / `macos` / `windows` / `linux`

Pass configuration as Dart defines (all optional; defaults work):

```bash
flutter run --dart-define-from-file=.env
# or
flutter run --dart-define=EXPO_PUBLIC_MOBILEAI_KEY=... --dart-define=GEMINI_API_KEY=...
```

## Key files

- `lib/main.dart` — app entry; constructs the `AIAgent` widget and resolves the
  hosted text/voice proxy URLs (or the direct-Gemini fallback) from Dart defines.
- `lib/router.dart` — `go_router` config: a `ShellRoute` with a bottom nav
  (home/search/cart/profile) plus deep settings routes.
- `lib/ai_screen_map.dart` — **GENERATED** `ScreenMap` the agent uses to reason
  about routes. Regenerate with the package tool if you change routes:
  `dart run tool/generate_screen_map.dart` (from a checkout of the package),
  then keep `screens`/`navigatesTo`/`chains` in sync with `router.dart`.
- `lib/providers/` — Riverpod providers (`cart`, `data`, `preferences`).
- `lib/data/seed_data.dart` — in-memory catalog used by the screens.

## Conventions & gotchas

- **Dart defines, not `.env` at runtime.** Values are compiled in via
  `String.fromEnvironment`. There is no dotenv loader; `.env` is only consumed by
  `--dart-define-from-file`. `.env` is git-ignored — never commit real secrets.
- The committed default `EXPO_PUBLIC_MOBILEAI_KEY` is a **publishable**
  (`mobileai_pub_…`) key and matches the upstream package example. It is safe to
  be public; do not replace it with a secret key.
- **Voice needs mic permissions** (already configured): Android `RECORD_AUDIO`,
  iOS/macOS `NSMicrophoneUsageDescription`, macOS `audio-input` entitlement. If
  you add platforms or run `flutter create .` to regenerate scaffolding, re-add
  these.
- **Windows build patch (vendored):** `flutter_sound` 9.30.0's Windows plugin is
  broken (native code named `taudio` vs pubspec `pluginClass:
  FlutterSoundPluginCApi`). We vendor a patched copy at `third_party/flutter_sound`
  and point to it via `dependency_overrides` in `pubspec.yaml`. The patch lives in
  `third_party/flutter_sound/windows/` (added `include/flutter_sound/…_c_api.h`, a
  bridging `FlutterSoundPluginCApiRegisterWithRegistrar` export, and renamed the
  CMake target to `flutter_sound_plugin`). Re-apply if `flutter_sound` is bumped.
- **mobileai_flutter patches (vendored):** `third_party/mobileai_flutter` is a
  copy of the published 0.2.7 with local patches, wired via `dependency_overrides`.
  Patched files (diff against the pub-cache copy to see them):
  `agent_chat_bar.dart` (desktop text-editing shortcuts; translucent
  "liquid glass" styling via BackdropFilter; voice mode renders as an animated
  `_VoiceOrb`), `ai_agent.dart`, `voice_service.dart`, `audio_output_service.dart`
  (voice stability fixes). Re-apply these if the SDK is bumped.
- **Gemini "model overloaded" (503)** and **"microphone unavailable"** are usually
  environmental, not bugs: the former is transient Gemini capacity (retry / switch
  model / use the hosted proxy); the latter is usually the wrong default input
  device (e.g. a Bluetooth hands-free), not the SDK.
- `router.dart` and `ai_screen_map.dart` must stay consistent — route paths in
  the screen map are matched against the router's locations.
- Requires Flutter ≥ 3.24.0 / Dart ≥ 3.11.4 (developed on Flutter 3.44.1).

## When changing navigation

1. Edit `lib/router.dart`.
2. Update `lib/ai_screen_map.dart` (titles, `navigatesTo`, `chains`) so the agent
   knows about the new/changed routes.
3. `flutter analyze` and run a manual agent flow to confirm navigation works.
