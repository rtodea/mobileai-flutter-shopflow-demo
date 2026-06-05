# MobileAI Flutter

A Flutter SDK for adding an in-app AI assistant that can read your widget tree, answer questions, guide users, perform approved actions, and hand off to human support.

[![pub package](https://img.shields.io/pub/v/mobileai_flutter.svg)](https://pub.dev/packages/mobileai_flutter)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.24.0-blue.svg)](https://flutter.dev/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](./LICENSE)

## Contents

- [What the SDK does](#what-the-sdk-does)
- [Install](#install)
- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Guardrails](#guardrails)
- [Common recipes](#common-recipes)
- [More docs](#more-docs)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## What The SDK Does

MobileAI adds a screen-aware assistant to your Flutter app. It can:

- Understand the current screen from the widget tree, semantics, and optional screen map.
- Answer app-specific questions using your knowledge base and registered data sources.
- Guide users through flows in companion mode without controlling the UI.
- Perform approved UI actions in copilot mode with workflow approval.
- Call app-defined non-UI actions with `AIAction`.
- Enforce semantic action safety with `allow`, `ask`, or `block` decisions before tools run.
- Query live app-owned data with `AIData`.
- Render rich chat blocks and contextual `AIZone` interventions.
- Escalate unresolved issues to human support when support mode is configured.

The default user-facing mode is **copilot mode**: the assistant can help with routine app steps after approval while the runtime enforces consent, workflow approval, semantic action safety, interactive filtering, masking, and verification.

## Install

```yaml
dependencies:
  mobileai_flutter: ^0.2.5
```

Import:

```dart
import 'package:mobileai_flutter/mobileai_flutter.dart';
```

For local development in this monorepo:

```yaml
dependencies:
  mobileai_flutter:
    path: ../mobileai-flutter
```

## Quick Start

Wrap the top-level app widget that owns navigation.

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileai_flutter/mobileai_flutter.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);

const apiKey = String.fromEnvironment('GEMINI_API_KEY');

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return AIAgent(
      apiKey: apiKey,
      router: router,
      instructions: 'You are a helpful assistant for this app.',
      child: MaterialApp.router(routerConfig: router),
    );
  }
}
```

Run locally:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

For production, prefer `proxyUrl` instead of shipping raw provider keys in the app.

```dart
AIAgent(
  proxyUrl: 'https://api.example.com/mobileai/chat',
  proxyHeaders: {'Authorization': 'Bearer $sessionToken'},
  child: MaterialApp.router(routerConfig: router),
)
```

## Core Concepts

### Interaction Modes

| Mode | What it does |
| --- | --- |
| `AppInteractionMode.companion` | Screen-aware guidance only. The assistant can explain what it sees and guide the user, but runtime blocks UI-effect tools. |
| `AppInteractionMode.copilot` | Default. Performs approved app actions while workflow approval is enforced. |
| `AppInteractionMode.autopilot` | Trusted automation mode. Use only for low-risk workflows. |

Companion mode is useful when trust matters more than automation. The assistant can read the screen, answer questions, explain confusing states, query knowledge or app data, and use non-UI support tools. It cannot tap, type, scroll, navigate, highlight, render blocks, simplify zones, or otherwise operate the app on the user's behalf.

```dart
AIAgent(
  interactionMode: AppInteractionMode.companion,
  child: MaterialApp.router(routerConfig: router),
)
```

### Navigation

`AIAgent` can build a `GoRouterAdapter` from a `GoRouter`.

```dart
AIAgent(
  router: router,
  child: MaterialApp.router(routerConfig: router),
)
```

For Flutter `Navigator`, pass a navigator key and adapter.

```dart
final navigatorKey = GlobalKey<NavigatorState>();

AIAgent(
  navigatorKey: navigatorKey,
  routerAdapter: NavigatorRouterAdapter(
    navigatorKey: navigatorKey,
    availableScreens: const ['/', '/billing', '/settings'],
  ),
  child: MaterialApp(
    navigatorKey: navigatorKey,
    routes: {
      '/': (_) => const HomeScreen(),
      '/billing': (_) => const BillingScreen(),
      '/settings': (_) => const SettingsScreen(),
    },
  ),
)
```

### App Data With `AIData`

Use `AIData` for structured data that is safer to fetch directly than infer from the current screen.

```dart
AIData(
  definition: DataDefinition(
    name: 'orders',
    description: 'Returns customer order status and ETA information.',
    handler: (context) async {
      return {
        'screen': context.screenName,
        'orders': await orderRepository.search(context.query),
      };
    },
  ),
  child: const OrdersScreen(),
)
```

### App Actions With `AIAction`

Use `AIAction` for app-owned operations that should run through code.

```dart
AIAction(
  action: ActionDefinition(
    name: 'apply_coupon',
    description: 'Apply a coupon code to the current cart.',
    effect: ToolEffect.stateModify,
    parameters: {
      'code': ActionParameterDef(
        type: 'string',
        description: 'Coupon code',
        required: true,
      ),
    },
    handler: (args) async {
      return cart.applyCoupon(args['code'] as String);
    },
  ),
  child: const CartScreen(),
)
```

### Knowledge Base

Pass static entries or a retriever.

```dart
AIAgent(
  knowledgeBase: [
    KnowledgeEntry(
      title: 'Return policy',
      content: 'Customers can request returns within 30 days.',
    ),
  ],
  child: MaterialApp.router(routerConfig: router),
)
```

## Guardrails

Guardrails are enforced by runtime code, not by the assistant alone.

- Consent can require explicit user opt-in before AI use.
- Companion mode blocks UI-effect tools.
- Copilot mode asks for workflow approval before UI-altering actions.
- Semantic action safety classifies generic actions into `allow`, `ask`, or `block`.
- Autopilot skips workflow approval and should be reserved for trusted low-risk flows.
- `interactiveBlacklist` and `interactiveWhitelist` restrict what the assistant can target.
- `transformScreenContent` can mask sensitive text before provider calls.
- Outcome verification can check critical actions.

By default, copilot mode uses the SDK guard classifier with the same provider family as the acting model (`gemini-2.5-flash-lite` for Gemini, `gpt-5.4-nano` for OpenAI). The acting AI proposes actions, the guard classifier classifies risk from the user request and screen context, and `AgentRuntime` enforces the final decision before executing the tool. Unknown or low-confidence actions ask instead of silently running.

```dart
AIAgent(
  interactionMode: AppInteractionMode.copilot,
  consent: const AIConsentConfig(required: true, persist: true),
  actionSafety: const ActionSafetyConfig(),
  transformScreenContent: (content) async {
    return content.replaceAll(RegExp(r'\b\d{4} \d{4} \d{4} \d{4}\b'), '[card number]');
  },
  child: MaterialApp.router(routerConfig: router),
)
```

Read the full Flutter safety model in [doc/guardrails.md](doc/guardrails.md).

## Common Recipes

### Companion Mode

```dart
AIAgent(
  interactionMode: AppInteractionMode.companion,
  router: router,
  child: MaterialApp.router(routerConfig: router),
)
```

### Support Assistant

```dart
AIAgent(
  supportMode: const SupportModeConfig(
    enabled: true,
    supportStyle: 'warm-concise',
    greetingMessage: 'Hi there. How can I help?',
  ),
  child: MaterialApp.router(routerConfig: router),
)
```

### Human Escalation

```dart
AIAgent(
  supportMode: SupportModeConfig(
    enabled: true,
    escalation: EscalationConfig(
      provider: EscalationProvider.custom,
      onEscalate: (context) async {
        await helpdesk.createTicket(context);
        return 'A support ticket has been created.';
      },
    ),
  ),
  child: MaterialApp.router(routerConfig: router),
)
```

### Custom Chat UI

Hide the built-in chat bar and use the controller from the tree.

```dart
final agent = context.ai;

ElevatedButton(
  onPressed: () => agent.send('Help me understand this screen'),
  child: const Text('Ask AI'),
)
```

```dart
AIAgent(
  showChatBar: false,
  child: const MyApp(),
)
```

## More Docs

- [Guardrails](doc/guardrails.md): companion mode, workflow approval, semantic action safety, consent, masking, and verification.
- [API reference](doc/api-reference.md): widgets, props, hooks, types, and configuration.
- [Rich UI](doc/rich-ui.md): blocks, `RichContentRenderer`, `AIZone`, themes, and block handlers.
- [Production](doc/production.md): proxy setup, telemetry, support mode, consent, and release checklist.
- [Parity matrix](doc/parity-matrix.md): Flutter parity status against the React Native SDK.

## Requirements

- Flutter `>=3.24.0`
- Dart `^3.11.4`
- iOS, Android, web, macOS, Windows, or Linux Flutter app
- `go_router` optional, only when using `GoRouter`
- Microphone permissions and native audio setup when voice mode is enabled

## Troubleshooting

**The assistant cannot navigate.** Pass `router`, `routerAdapter`, or `navigatorKey`, and keep direct navigation to safe top-level routes.

**The assistant does not see a control.** Add useful visible text, semantics labels, or accessibility metadata, and make sure the widget is mounted.

**A sensitive control is visible.** Use `interactiveBlacklist`, `interactiveWhitelist`, or `transformScreenContent`.

**The assistant asks before acting.** In copilot mode, workflow approval is expected before UI-altering actions.

**You want guidance only.** Use `AppInteractionMode.companion`.

## License

MIT. See [LICENSE](LICENSE).
