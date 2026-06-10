# TODO / Handoff — ShopFlow (mobileai_flutter demo)

A working-state handoff so this can be picked up on another machine. Read top to
bottom once. **Android voice now works end-to-end on a physical phone
(2026-06-09)** — playback is smooth, the assistant no longer talks to itself, and
it stays connected through tool calls. Remaining items are polish + iOS (section 4).

Repo: `git@github.com:rtodea/mobileai-flutter-shopflow-demo.git` (branch `main`).
Recent commits at handoff: `41ea515` (wip: Live model + autopilot), `651d1eb`,
`2c069b2`, `e9ee56f` (the 2026-06-09 voice fixes — section 9).

---

## 1. What this project is

A standalone Flutter app (**ShopFlow**, an e-commerce sample) that demonstrates the
[`mobileai_flutter`](https://pub.dev/packages/mobileai_flutter) SDK — an in-app,
UI-aware AI agent with **text + voice** and screen-aware navigation. It's the
package's official example app, re-pointed at the published package, plus two
**vendored + patched** dependencies (see section 6) to fix desktop/web/mobile bugs.

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
| **Web voice** | ⚠️ connects but `flutter_sound` web audio is **choppy/garbled** |
| **Windows voice** | ❌ not possible — `flutter_sound`'s Windows plugin is a stub |
| **Android build + launch** | ✅ verified (emulator + physical phone) |
| **Android text agent** | ✅ "go to my cart" → taps Cart tab → navigates |
| **Android voice — full loop** | ✅ **verified 2026-06-09 on a physical Redmi 9T (M2007J22G, Android 12)**: mic → transcript → tool actions → spoken reply, smooth playback, no echo loop, stays connected through tool calls |
| **iOS** | ⏳ not yet run |

**Voice was made solid on 2026-06-09** by four fixes (section 6) — the big one is the
**Live model choice**: the native-audio preview models are unstable for tool-heavy
agentic sessions; switching to the **half-cascade `gemini-3.1-flash-live-preview`**
removed the disconnects.

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

## 4. Status & next tasks

> **2026-06-09:** Android voice is **done and verified on a physical phone** (Redmi
> 9T). Connect a phone with **USB debugging** on, `flutter run -d <id>
> --dart-define-from-file=.env`, tap the agent FAB → Voice, and speak. The agent
> transcribes, navigates / acts via tools, and speaks back with smooth audio.

### Definition of done for Android voice — ✅ complete
- [x] App launches on an Android device/emulator. *(emulator + physical phone)*
- [x] Text request (e.g. "go to my cart") navigates.
- [x] Voice: spoken command → transcribed → app navigates → **reply audio is clear**
  (no choppiness) and the assistant **does not loop / talk to itself**. *(2026-06-09)*

### Remaining / next
- [ ] **iOS / macOS** voice (macOS mic entitlements already added).
- [ ] **On-device confirm the autopilot config** (no Allow prompts) — the code is in
  (`main.dart`, section 6/8) but the final on-device check was blocked when the test
  machine dropped off SSH; re-verify next session.
- [ ] **Occasional start-of-turn audio underrun** (one brief glitch at the start of
  some replies) — optional pre-roll/jitter-buffer fix (section 8).

### Setup recap (physical phone — best for voice)
1. Phone → Settings → Developer options → enable **USB debugging**.
2. Plug in via USB, accept the "Allow USB debugging" prompt.
3. `adb devices` (adb in `<sdk>\platform-tools`) — should list it as `device`.
4. `flutter run -d <device-id> --dart-define-from-file=.env`.

(Emulator path via Android Studio Device Manager also works, but emulator **audio
output** is choppy and host-mic passthrough is flaky — use a real phone for voice.)

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
- **Both** MobileAI lines must be **blank** or `main.dart` routes to the hosted
  proxy and ignores your Gemini key. Blanking them forces direct Gemini.
  *(non-blank lines → `[WARN] [FeatureFlag] Fetch failed: 401` and the agent won't run.)*
- The Gemini key is used for **text and voice**. Voice (Gemini Live) needs a
  **Live-capable** model — see the model note in section 6. List the Live models your
  key can use with:
  `https://generativelanguage.googleapis.com/v1beta/models?key=<KEY>` → keep the ones
  whose `supportedGenerationMethods` contains `bidiGenerateContent`.
- See `.env.example` for the template. Never commit a real key (the repo is public).

---

## 6. Vendored + patched dependencies + app config (important context)

Both deps live under `third_party/` and are wired via `dependency_overrides` in
`pubspec.yaml`. If you `flutter pub get` and these paths are missing, the build
breaks — keep them.

### `third_party/flutter_sound` (patched 9.30.0) — fixes the **Windows build**
Upstream's Windows plugin is misnamed (`taudio` vs pubspec
`pluginClass: FlutterSoundPluginCApi`) → `No target "flutter_sound_plugin"`. Patch
(`windows/`): added `include/flutter_sound/flutter_sound_plugin_c_api.h`, a bridging
`FlutterSoundPluginCApiRegisterWithRegistrar` export, and renamed the CMake target.
> Only makes it **build**; the Windows plugin is still a stub, so Windows voice is impossible.

### `third_party/mobileai_flutter` (patched 0.2.7)
1. **`agent_chat_bar.dart`** — wrap the chat field in `DefaultTextEditingShortcuts`
   + `enableInteractiveSelection: true` (Backspace/arrows did nothing on desktop).
2. **`voice_service.dart`** — use cross-platform `WebSocketChannel.connect` on web
   (`kIsWeb`); `IOWebSocketChannel` threw `Platform._version` in browsers.
3. **`agent_chat_bar.dart` (FAB position)** — seed `_position` with a large sentinel
   and only anchor once `size > 0`, so the launcher FAB no longer sticks top-left/
   unclickable on the zero-size first frame.
4. **`agent_chat_bar.dart` (FAB clamps, 2026-06-09)** — some devices (MIUI) report a
   `0×0` surface on the first frame; `_position.dx.clamp(0, width-70)` then became
   `clamp(0, -70)` → `ArgumentError` every frame. Guarded every size-derived clamp
   upper bound so it can't fall below the lower (build, `_buildFab`, drag handler).
5. **`audio_output_service.dart` (playback, 2026-06-09)** — playback was choppy because
   each ~40 ms PCM chunk was paced behind a `Future.delayed` with a **120 ms floor**,
   starving the AudioTrack (constant `underrun`). Now feeds chunks back-to-back (lets
   flutter_sound's own flow control pace them), detects end-of-playback with a debounce
   timer, and bumps the stream buffer `4096 → 16384` for jitter headroom.
6. **`ai_agent.dart` (echo loop, 2026-06-09)** — the mic was resumed on
   `onTurnComplete` (model *done generating*) while buffered audio was still playing,
   so the open mic fed the assistant's own voice back through the server-side VAD →
   it talked to itself. Now resumes the mic on `AudioOutputService.onPlaybackEnd`
   (after audio actually drains).
7. **`ai_agent.dart` + `voice_service.dart` (reconnect recovery, 2026-06-09)** — Live
   sessions can close unexpectedly (`1007/1008/1011`); the app used to reconnect every
   2 s forever, replaying a stale `sessionResumption` handle the server keeps
   rejecting (infinite storm). Now: clear the handle on unexpected close (reconnect
   fresh), and cap reconnects at 5 with exponential backoff (reset on a successful
   connect). Verified against a live `1007`: recovers in one reconnect.
8. **`voice_service.dart` (Live model, 2026-06-09)** — `_defaultLiveModel` changed from
   `gemini-2.5-flash-native-audio-preview-12-2025` → **`gemini-3.1-flash-live-preview`**.
   See the model note below.

### `lib/main.dart` app config (2026-06-09, demo)
- **Autopilot + safety off** for a frictionless demo:
  `interactionMode: AppInteractionMode.autopilot` + `actionSafety: const
  ActionSafetyConfig(enabled: false)`. This removes **all** approval prompts (see the
  approval note below). ⚠️ It also removes the safety net for destructive/payment
  actions — fine for a demo, reconsider before shipping as a default.

> ⭐ **Live model note (the key voice fix).** The Gemini **native-audio** preview
> models (`gemini-2.5-flash-native-audio-*`) sound the most natural but are **unstable
> for tool-heavy agentic sessions** — the server closes the socket mid-turn with
> `1007 (invalid argument)`, `1008 (operation not supported)`, or `1011 (internal
> error)` around function calls. The **half-cascade `gemini-3.1-flash-live-preview`**
> has robust function-calling support and stays connected through the tool loop. Only
> models advertising `bidiGenerateContent` work for Live (query ListModels, section 5).

> 🔐 **Approval / "Allow" prompts.** Two independent gates: (a) the **action-safety
> classifier** (`ActionSafetyConfig`, on by default) classifies each UI action
> allow/ask/block by capability+risk; (b) the **workflow-approval scope**
> (`copilot` mode) gates UI-altering tools until approved. It's **per risk-class, not
> per widget**, and approvals reset on **each new voice command**, so prompts feel
> frequent. To act with no prompts: `interactionMode: autopilot` (bypasses the
> workflow gate and survives the per-command reset) **and** `actionSafety(enabled:
> false)` (turns off the classifier). The element **highlight** during tool use is
> built into the SDK (`highlight_overlay.dart` / `_showActionHighlight`) — no app code.

> If you bump either dependency version, re-apply these patches or drop the override.

---

## 7. Run / build commands

```bash
flutter run -d <device> --dart-define-from-file=.env   # android id / windows / chrome
flutter run -d chrome  --dart-define-from-file=.env    # web (voice choppy, text CORS-blocked)
flutter run -d windows --dart-define-from-file=.env    # desktop (text only; no voice)
flutter analyze                                        # clean except upstream info-lints
flutter build apk  --dart-define-from-file=.env        # android
```

In-app: tap the agent **FAB** → type, or switch to **Voice** and speak. (With the
demo autopilot config there are no Allow prompts.)

---

## 8. Backlog / open issues

- [x] **Android — build, launch, text-nav** *(2026-06-05)*.
- [x] **Android voice** — clean transcription + nav + smooth audio + no echo/loop *(2026-06-09)*.
- [ ] **iOS / macOS** voice.
- [ ] **Squash the `wip` commit** (`41ea515`) into a proper message — it carries the
      Live-model swap + the autopilot/safety demo config.
- [ ] **Decide whether autopilot + `actionSafety(enabled:false)` should be the repo
      default** or demo-only (it removes the approval safety net). If shipping,
      consider exposing `initialApprovalScope` on the `AIAgent` widget instead.
- [ ] **Occasional start-of-turn underrun** — one brief glitch when a reply starts
      (the AudioTrack starts before enough audio is buffered). Optional fix: a small
      pre-roll/jitter buffer in `audio_output_service.dart` (accumulate ~250 ms before
      starting playback). Most replies are clean; deferred as "good enough".
- [ ] **Web text** CORS-blocked on direct Gemini → server/hosted proxy if needed.
- [ ] **Web voice fidelity**: `flutter_sound` web audio choppy/garbled; reroute
      capture via `record_web` + a Web Audio player. Large; only if web voice matters.
- [ ] Optional: upstream the vendored patches; clean up upstream `info` lints.

---

## 9. Git history (context)

```
a019efc  Initial commit: ShopFlow demo for mobileai_flutter
42cf2f4  Fix Windows build: vendor patched flutter_sound + document AI gotchas
67b0061  Fix agent chat box editing on desktop (vendor patched mobileai_flutter)
9cb4e65  Make agent voice WebSocket work on web
0409e52  Add TODO.md handoff doc
f1df1e9  Fix agent FAB pinned top-left/unclickable; update Android handoff
e9ee56f  fix(voice): smooth Gemini Live playback and stop echo loop   <-- 2026-06-09
2c069b2  fix(ui): harden AgentChatBar against zero-size first frame
651d1eb  fix(voice): recover from Gemini Live 1007 closes instead of storming
41ea515  wip   (Live model -> gemini-3.1-flash-live-preview; autopilot + safety off)
```

---

## 10. Debugging notes

- Run with `flutter run` (not a prebuilt exe) to see logs; `debug: true` is set in
  `main.dart`, and `onResult` logs `[ShopFlow] Agent result: …`.
- Useful log lines: `VoiceService connecting…` / `Voice connected`,
  `AudioInputService started` + `chunk #N`, `AudioOutputService stream started`,
  `Voice transcript [user/model]`, `Voice input paused/resumed during model playback`,
  `VoiceService closed (code=…)`, and the SDK `[INFO]/[WARN]/[ERROR]` tags.
- **Audio underrun** shows as `W/AudioTrack: releaseBuffer() … disabled due to previous
  underrun, restarting`. A *storm* of these = the old per-chunk pacing bug (fixed); a
  single one at the start of a reply = the residual start-of-turn glitch (section 8).
- **Echo loop** would show as `Ignored user transcript while model playback is active`
  and the assistant replying to itself — fixed by resuming the mic on playback-end.
- **Live disconnect codes:** `1007` invalid argument, `1008` not implemented/supported
  (incl. *"models/… is not found … for bidiGenerateContent"* = wrong/unavailable model
  name), `1011` internal error. With the half-cascade model these stopped; the
  reconnect-recovery (section 6.7) makes any future one survivable.
- **Remote dev gotcha (Tailscale + Windows):** running this over `ssh` to a Windows box
  works, but if the box **sleeps or changes networks**, Windows can reclassify the
  connection as **Public** and the OpenSSH inbound firewall rule (Private/Domain only)
  silently drops port 22 — `tailscale ping` still gets a `pong` (tunnel fine) but `ssh`
  **times out**. Fix on the box: `Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
  -Enabled True -Profile Any` (or flip the network to Private), and ensure `sshd` is
  running. A reboot resets it cleanly.
- See `README.md` → Troubleshooting for "model overloaded" and "microphone unavailable".
