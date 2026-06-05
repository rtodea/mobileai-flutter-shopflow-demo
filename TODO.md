# TODO / Handoff — ShopFlow (mobileai_flutter demo)

A working-state handoff so this can be picked up on another machine. Read top to
bottom once; the **immediate next task is "Run on Android"** (section 4).

Repo: `git@github.com:rtodea/mobileai-flutter-shopflow-demo.git` (branch `main`).
Last commit at handoff: `9cb4e65`.

---

## 1. What this project is

A standalone Flutter app (**ShopFlow**, an e-commerce sample) that demonstrates the
[`mobileai_flutter`](https://pub.dev/packages/mobileai_flutter) SDK — an in-app,
UI-aware AI agent with **text + voice** and screen-aware navigation. It's the
package's official example app, re-pointed at the published package, plus two
**vendored + patched** dependencies (see section 6) to fix desktop/web bugs.

Built with **Flutter 3.44.1 / Dart 3.12.1** (the package needs Flutter ≥3.24 /
Dart ≥3.11.4).

---

## 2. TL;DR current state

| Area | Status |
| --- | --- |
| Repo builds, analyzed, pushed | ✅ |
| **Text agent** (direct Gemini) on **desktop** | ✅ works (occasional Gemini `503 overloaded`) |
| **Windows** desktop build | ✅ works (needed a vendored `flutter_sound` patch) |
| **Backspace/Delete/arrows + selection** in the chat box | ✅ fixed (vendored `mobileai_flutter` patch) |
| **Web** build/run | ✅ runs |
| **Web text agent** | ❌ blocked by **CORS** (Gemini REST isn't callable from a browser) |
| **Web voice** | ⚠️ connects + mic + playback work, but `flutter_sound` web audio is **choppy/garbled** → commands mis-transcribed |
| **Windows voice** | ❌ not possible — `flutter_sound`'s Windows plugin is a stub (no recorder/player) |
| **Android / iOS voice** | ⏳ **not yet run — this is the next task; it's the intended platform for voice** |

**Why mobile next:** on Android/iOS, `flutter_sound` has real audio support and
there's no CORS, so both text and voice should "just work." The Gemini key and the
Gemini **Live** voice connection are already proven working (we saw `Voice
connected` + audio responses); the only blockers were platform audio (Windows) and
browser limits (web).

---

## 3. Quick start on a fresh laptop

```bash
git clone git@github.com:rtodea/mobileai-flutter-shopflow-demo.git
cd mobileai-flutter-shopflow-demo
flutter --version          # need >=3.24 (dev'd on 3.44.1 / Dart 3.12.1)
flutter pub get            # resolves deps incl. the two vendored path overrides
```

If Flutter isn't installed, see `README.md` (macOS/Windows/Linux-ARM install
sections). On Windows this repo was built from the official stable zip extracted to
`C:\src\flutter` with `C:\src\flutter\bin` on PATH.

Then create your `.env` (section 5) and run (section 7).

---

## 4. ⭐ IMMEDIATE NEXT TASK: run on Android

We confirmed everything except an Android **device/emulator**. On the previous
laptop: SDK platform `android-36.1`, build-tools, platform-tools, the emulator
engine, and **licenses** were installed, but there was **no AVD**, **no system
image**, and `cmdline-tools` was empty.

On the new laptop (you have Android Studio), pick the fastest path:

### Option A — physical phone (best for voice; real mic)
1. Phone → Settings → Developer options → enable **USB debugging**.
2. Plug in via USB, accept the "Allow USB debugging" prompt.
3. Verify: `adb devices` (adb is in `<sdk>\platform-tools`) — should list it.
4. Run (section 7): `flutter run -d <device-id> --dart-define-from-file=.env`.

### Option B — emulator via Android Studio (handles the system-image download)
1. Android Studio → **Device Manager** (phone icon) → **Create device**.
2. Pick e.g. Pixel 7 → choose a system image (e.g. API 34/35), click **Download**.
3. Finish, press ▶ to boot it.
4. Verify `flutter devices` shows the emulator, then run (section 7).
5. Emulator mic: enable host audio input in the AVD's Extended controls →
   Microphone (or "Virtual microphone uses host audio input").

### Option C — pure CLI (if no Android Studio / fully scripted)
1. Download Android **command-line tools** (win/mac/linux) from
   <https://developer.android.com/studio#command-line-tools-only>, unzip to
   `<sdk>/cmdline-tools/latest/`.
2. `sdkmanager "platform-tools" "platforms;android-35" "system-images;android-35;google_apis;x86_64"`
   (accept licenses: `sdkmanager --licenses`).
3. `avdmanager create avd -n shopflow -k "system-images;android-35;google_apis;x86_64"`.
4. `flutter emulators --launch shopflow` (or `emulator -avd shopflow`).
5. Run (section 7).

> First Android Gradle build downloads Gradle + Android deps (~minutes). Expect a
> mic-permission prompt at runtime (the `RECORD_AUDIO` permission is already in the
> manifest). Tap the agent FAB → **Allow AI** → speak, e.g. "open my profile".

### Definition of done for this task
- App launches on an Android device/emulator.
- Text request (e.g. "go to my cart") navigates.
- Voice: speak a command → it's transcribed correctly → the app navigates, and you
  hear the reply clearly (no choppiness like web).

---

## 5. Configuration (`.env`) — NOT committed

`.env` is git-ignored; recreate it on each machine. Values are compiled in via
`--dart-define-from-file=.env` (there is no runtime dotenv). Use **direct Gemini**:

```dotenv
GEMINI_API_KEY=<your AI Studio key>
EXPO_PUBLIC_MOBILEAI_BASE_URL=
EXPO_PUBLIC_MOBILEAI_KEY=
```

- Get a key at <https://aistudio.google.com/app/apikey> (free tier OK; ~10 req/min).
  Note: from **2026-06-19** Google drops unrestricted keys — click "Restrict to
  Gemini API" on the key.
- **Both** MobileAI lines must be **blank** or `main.dart` routes to the hosted
  proxy and ignores your Gemini key. Blanking them forces direct Gemini.
- See `.env.example` for the template. Never commit a real key (the repo is public).
- Alternative (esp. to fix **web text** CORS, and for reliable voice): use the
  hosted proxy instead — set `EXPO_PUBLIC_MOBILEAI_BASE_URL=https://mobileai.cloud`
  and a real `EXPO_PUBLIC_MOBILEAI_KEY` (mobileai_pub_…) from mobileai.cloud.

---

## 6. Vendored + patched dependencies (important context)

Both live under `third_party/` and are wired via `dependency_overrides` in
`pubspec.yaml`. If you `flutter pub get` and these paths are missing, the build
breaks — keep them.

### `third_party/flutter_sound` (patched 9.30.0) — fixes the **Windows build**
Upstream's Windows plugin is misnamed: native code is `taudio`, but its pubspec
declares `pluginClass: FlutterSoundPluginCApi`, so Flutter's generated registrant
can't find the target/symbol/header → `No target "flutter_sound_plugin"`. Patch
(`windows/`): added `include/flutter_sound/flutter_sound_plugin_c_api.h`, a bridging
`FlutterSoundPluginCApiRegisterWithRegistrar` export in `taudio_plugin_c_api.cpp`,
and renamed the CMake target to `flutter_sound_plugin`.
> Note: this only makes it **build**. `flutter_sound`'s Windows plugin is still a
> stub (only `getPlatformVersion`), so **recording/playback do not work on
> Windows** — that's why Windows voice is impossible.

### `third_party/mobileai_flutter` (patched 0.2.7) — two fixes
1. **`lib/src/widgets/agent_chat_bar.dart`** — the chat box is rendered above
   `MaterialApp`, so it had no `DefaultTextEditingShortcuts`; Backspace/Delete/
   arrows did nothing on desktop. Patch wraps the field in
   `DefaultTextEditingShortcuts` and sets `enableInteractiveSelection: true`.
2. **`lib/src/services/voice_service.dart`** — used `IOWebSocketChannel` (dart:io),
   which throws `Unsupported operation: Platform._version` in browsers, so voice
   never connected on web. Patch uses cross-platform `WebSocketChannel.connect` on
   web (`kIsWeb`) and keeps `IOWebSocketChannel` (headers + keep-alive) on native.

> If you bump either dependency version, re-apply these patches or drop the
> override. Consider upstreaming all three fixes.

---

## 7. Run / build commands

```bash
flutter run -d <device> --dart-define-from-file=.env   # android id / windows / chrome
flutter run -d chrome  --dart-define-from-file=.env    # web (voice choppy, text CORS-blocked)
flutter run -d windows --dart-define-from-file=.env    # desktop (text only; no voice)
flutter analyze                                        # clean except upstream info-lints
flutter build apk  --dart-define-from-file=.env        # android release
flutter build web                                      # release web
```

In-app: tap the agent **FAB** → **Allow AI** (consent required once) → type or
switch to **Voice**.

---

## 8. Backlog / open issues

- [ ] **Run + validate on Android** (section 4) — primary goal: clean voice + nav.
- [ ] Try **iOS/macOS** too (macOS mic entitlements already added in
      `macos/Runner/*.entitlements` + Info.plist).
- [ ] **Gemini 503 "model overloaded / high demand"** is transient. Consider adding
      a `--dart-define=GEMINI_MODEL=` and reading it in `main.dart` to switch text
      model (e.g. `gemini-2.0-flash` / `gemini-flash-latest`). Note: the SDK uses
      one `model` for text *and* voice, so don't set a non-audio model if using
      voice.
- [ ] **Web text** is CORS-blocked on direct Gemini → route through a server proxy
      (or the hosted MobileAI proxy) if web text is needed.
- [ ] **Web voice fidelity**: `flutter_sound` web audio is choppy (playback) and
      garbled (capture → mis-transcription). To make web voice usable, reroute
      capture via `record`/`record_web` (AudioWorklet) and replace playback with a
      Web Audio player. Large; only if web voice matters.
- [ ] Optional: upstream the 3 patches (flutter_sound Windows naming;
      mobileai_flutter chat-shortcuts; mobileai_flutter web WebSocket) to the
      package authors.
- [ ] Optional: clean up the 44 upstream `info` lints (`dart fix --apply`).

---

## 9. Git history (context)

```
a019efc  Initial commit: ShopFlow demo for mobileai_flutter
42cf2f4  Fix Windows build: vendor patched flutter_sound + document AI gotchas
67b0061  Fix agent chat box editing on desktop (vendor patched mobileai_flutter)
9cb4e65  Make agent voice WebSocket work on web   <-- HEAD at handoff
```

---

## 10. Debugging notes

- Run with `flutter run` (not just a prebuilt exe) to see logs; `debug: true` is set
  in `main.dart`, and `onResult` logs `[ShopFlow] Agent result: …`.
- Useful log lines: `VoiceService connecting…` / `Voice connected`,
  `AudioInputService started` + `chunk #N`, `AudioOutputService initialized`,
  `Voice transcript [user/model]`, and SDK `[INFO]/[WARN]/[ERROR]` tags.
- Evidence from the previous session:
  - Windows voice: `MissingPluginException … flutter_sound_recorder/_player` (stub).
  - Web voice (pre-fix): `VoiceService failed to connect: Unsupported operation:
    Platform._version`; (post-fix) connects, but transcript of a spoken command came
    back as `" I"` → `Ignored unusable voice transcript` → no navigation.
- See `README.md` → Troubleshooting for the "model overloaded" and
  "microphone unavailable" write-ups.
