## 0.2.7

- Wire CSATSurvey into AgentChatBar after successful agent resolution in support mode.
- Add afterMessagesContent prop to AgentChatBar for inline post-conversation widgets.
- Fix proxy session deviceId race condition.
- Add proxy error code handling (rate limits, budget exhaustion, session token limits).

## 0.2.6

- Fixed Gemini "too much branching for serving" schema error by replacing flattened tool parameters with a single `action_input` JSON string field.
- Applied narrow schema to both direct SDK and proxy code paths (`_buildAgentStepDeclaration` and `_buildAgentStepDeclarationJson`).
- Removed `nullable` annotations and enum constraints that contributed to schema branching.

## 0.2.5

- Added SDK-owned semantic action guardrails for Flutter copilot actions.
- Added `ActionSafetyConfig`, `ActionSafetyClassifier`, action safety decision types, approval reuse, developer decision overrides, and `ToolEffect` metadata for tools and `AIAction`.
- Added a built-in default guard classifier using `gemini-2.5-flash-lite` for Gemini and `gpt-5.4-nano` for OpenAI.
- Added runtime enforcement for `allow`, `ask`, and `block` before tool execution, including timeout/low-confidence fallback to approval.
- Added focused action-safety tests and updated guardrail, API, production, and README docs.

## 0.2.4

- Added `AppInteractionMode.companion` for screen-aware guidance without UI control.
- Companion mode now filters UI-effect tools from the model tool list and blocks them again at runtime before execution.
- Added focused docs for guardrails, API reference, rich UI, and production setup.
- Reorganized the README around install, quick start, core concepts, guardrails, and common recipes.

## 0.2.3

- Fixed voice playback/listening sequencing so the microphone pauses while model audio plays and resumes afterward.
- Reset voice workflow approval for each new spoken command while preserving multi-tool commands within one spoken turn.
- Refreshed voice tool element context before executing tap/type tools, including layered UI surfaces such as bottom sheets.
- Added iOS voice E2E coverage for repeated approvals, post-playback mic resume, and multi-step voice tool flows.

## 0.2.2

- Default hosted MobileAI services and example proxy config to `https://mobileai.cloud`.
- Treat generated screen maps as route hints while keeping the live router/adapter as the navigation source of truth.
- Simplify `go_router` setup by allowing `AIAgent` to build the default adapter from the router.

## 0.2.1

- Updated the README to match the shipped `0.2.x` Flutter API and tool surface.
- Replaced stale setup examples with current documentation for `AIAgent`, `AIAction`, `AIData`, `AIZone`, consent, telemetry, support mode, voice mode, and theming.

## 0.2.0

- Added production-safe selector-grade widget-tree parsing with richer selector/state metadata.
- Improved screen dehydration, route isolation, and canonical scroll-host modeling for agent reasoning.
- Upgraded static screen-map generation to prefer durable dynamic-list summaries over transient loading and empty states.
- Expanded rich reply handling, critical-action verification, and chat-history/runtime parity with the React Native library.

## 0.1.3

- Fixed repository, homepage, and issue tracker links in `pubspec.yaml`.
- Added GitHub repository reference badge to `README.md`.
- Ignored `.env` config in `.gitignore` to prevent sensitive credentials exposure.

## 0.1.2

- Resolved all analyzer warnings and lint issues to maximize pub.dev score.
- Implemented `super` parameters and cleaned up unused imports and dead code.
- Migrated deprecated `withOpacity` calls to `withValues`.
- Ensured full compatibility with the latest Flutter SDK (3.41+).
## 0.1.0

- **Overlay UI**: Floating `AgentChatBar` (draggable FAB + expandable panel) and `AgentOverlay` thinking indicator
- **Security guardrails**: `interactiveBlacklist`, `interactiveWhitelist`, `transformScreenContent`, `enableUiControl`
- **Production apiKey warning**: logs a security notice in release builds when `proxyUrl` is not set
- **Flattened API**: `AiAgent` now exposes flat top-level props (`apiKey`, `maxSteps`, `instructions`, `router`, `accentColor`) matching the React Native SDK's API surface
- **Cancellation**: `cancel()` support on `AgentRuntime` and `AiAgentController`
- **RTL / Arabic support**: chat bar placeholder and layout respect `language: 'ar'`
- **History summarization**: compresses long task histories to prevent context overflow
- **Budget guards**: `maxTokenBudget` and `maxCostUsd` stop runaway tasks

## 0.0.1

- Initial release
