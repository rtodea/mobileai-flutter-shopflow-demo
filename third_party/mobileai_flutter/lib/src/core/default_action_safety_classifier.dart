import 'dart:convert';

import '../providers/provider_factory.dart';
import 'types.dart';

const Map<AiProviderName, String> defaultGuardModels = {
  AiProviderName.gemini: 'gemini-2.5-flash-lite',
  AiProviderName.openai: 'gpt-5.4-nano',
};

String resolveDefaultGuardModel(AgentConfig config) {
  if (config.actionSafety.guardModel != 'auto') {
    return config.actionSafety.guardModel;
  }
  return defaultGuardModels[config.provider]!;
}

class DefaultActionSafetyClassifier implements ActionSafetyClassifier {
  final AgentConfig config;
  AiProvider? _guardProvider;

  DefaultActionSafetyClassifier({required this.config});

  @override
  Future<ScreenSafetyMap> classifyScreen(ScreenSafetyInput input) async {
    final provider = _getGuardProvider();
    if (provider == null || input.screen.elements.isEmpty) {
      return ScreenSafetyMap(screenSignature: input.screenSignature);
    }

    try {
      final result = await provider.generateContent(
        systemPrompt: _screenSystemPrompt,
        userMessage: jsonEncode({
          'userRequest': input.userRequest,
          'screenName': input.screen.screenName,
          'screenContent': input.screenContent,
          'screenSignature': input.screenSignature,
          'mode': input.mode.name,
          'elements': input.screen.elements
              .map(
                (element) => {
                  'index': element.index,
                  'type': element.type.name,
                  'label': element.label,
                  'properties': element.properties,
                },
              )
              .toList(growable: false),
        }),
        tools: [_classifyScreenTool],
        history: const [],
      );
      final decisionsJson =
          result.actionParams?['decisions_json']?.toString() ?? '{}';
      final decoded = jsonDecode(decisionsJson);
      if (decoded is! Map) {
        return ScreenSafetyMap(screenSignature: input.screenSignature);
      }
      final decisions = <int, ActionSafetyDecision>{};
      for (final entry in decoded.entries) {
        final index = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (index == null || value is! Map) continue;
        final decision = _decisionFromJson(value.cast<String, dynamic>());
        if (decision != null &&
            decision.capability != ActionSafetyCapability.unknown) {
          decisions[index] = decision;
        }
      }
      return ScreenSafetyMap(
        screenSignature: input.screenSignature,
        decisions: decisions,
      );
    } catch (_) {
      return ScreenSafetyMap(screenSignature: input.screenSignature);
    }
  }

  @override
  Future<ActionSafetyDecision> classifyAction(ActionSafetyInput input) async {
    final fallback = _fallbackAsk(input);
    final provider = _getGuardProvider();
    if (provider == null) return fallback;

    try {
      final result = await provider.generateContent(
        systemPrompt: _actionSystemPrompt,
        userMessage: jsonEncode({
          'userRequest': input.userRequest,
          'toolName': input.toolName,
          'args': input.args,
          'target': input.targetElement == null
              ? null
              : {
                  'index': input.targetElement!.index,
                  'type': input.targetElement!.type.name,
                  'label': input.targetElement!.label,
                  'properties': input.targetElement!.properties,
                },
          'screenName': input.screen?.screenName,
          'screenContent': input.screenContent ?? input.screen?.elementsText,
          'screenSignature': input.screenSignature,
          'mode': input.mode.name,
          'toolEffect': input.toolEffect.name,
        }),
        tools: [_classifyActionTool],
        history: const [],
      );
      final decision = _decisionFromJson(result.actionParams ?? const {});
      return decision ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  AiProvider? _getGuardProvider() {
    if (_guardProvider != null) return _guardProvider;
    final hasApiKey = config.apiKey != null && config.apiKey!.isNotEmpty;
    final hasProxy = config.proxyUrl != null && config.proxyUrl!.isNotEmpty;
    if (!hasApiKey && !hasProxy) return null;

    _guardProvider = createProvider(
      provider: config.provider,
      apiKey: config.apiKey,
      model: resolveDefaultGuardModel(config),
      proxyUrl: config.proxyUrl,
      proxyHeaders: config.proxyHeaders,
    );
    return _guardProvider;
  }

  ActionSafetyDecision _fallbackAsk(ActionSafetyInput input) {
    return ActionSafetyDecision(
      decision: config.actionSafety.unknownActionDecision,
      confidence: 0,
      reason:
          'Default guard could not classify this action with a valid model decision.',
      userMessage:
          'I am not fully sure what this action will do. Do you want me to continue?',
      capability: ActionSafetyCapability.unknown,
      scope: ActionSafetyScope.unknownTask,
      risk: ActionSafetyRisk.medium,
    );
  }
}

ActionSafetyDecision? _decisionFromJson(Map<String, dynamic> raw) {
  final decision = _enumByName(
    ActionSafetyDecisionKind.values,
    raw['decision'],
  );
  final scope = _enumByName(ActionSafetyScope.values, raw['scope']);
  final capability = _enumByName(
    ActionSafetyCapability.values,
    raw['capability'],
  );
  final risk = _enumByName(ActionSafetyRisk.values, raw['risk']);
  final reason = raw['reason']?.toString();

  if (decision == null ||
      scope == null ||
      capability == null ||
      risk == null ||
      reason == null ||
      reason.isEmpty) {
    return null;
  }

  return ActionSafetyDecision(
    decision: decision,
    confidence: raw['confidence'] is num
        ? (raw['confidence'] as num).toDouble()
        : null,
    reason: reason,
    userMessage: raw['userMessage']?.toString(),
    capability: capability,
    scope: scope,
    risk: risk,
    requiresFreshApproval: raw['requiresFreshApproval'] == true,
  );
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty) return null;
  for (final item in values) {
    if (item.name == value) return item;
  }
  return null;
}

final ToolDefinition _classifyActionTool = ToolDefinition(
  name: 'classify_action',
  description:
      'Classify a proposed mobile app action into a scope, capability, risk, and runtime decision.',
  effect: ToolEffect.read,
  parameters: {
    'decision': ToolParam(
      type: 'string',
      description: 'One of allow, ask, block.',
    ),
    'scope': ToolParam(
      type: 'string',
      description:
          'One of readOrLookup, supportInvestigation, formAssistance, shoppingPreparation, accountManagement, communicationPreparation, unknownTask.',
    ),
    'capability': ToolParam(
      type: 'string',
      description:
          'One of screenRead, uiNavigate, uiScroll, uiFill, uiSelect, stateModify, contentSend, externalOpen, supportEscalate, paymentCommit, orderCommit, accountSecurity, privacySensitive, destructive, unknown.',
    ),
    'risk': ToolParam(
      type: 'string',
      description: 'One of low, medium, high, critical.',
    ),
    'confidence': ToolParam(
      type: 'number',
      description: 'Confidence from 0 to 1.',
    ),
    'reason': ToolParam(type: 'string', description: 'Short audit reason.'),
    'userMessage': ToolParam(
      type: 'string',
      description: 'User-facing message for ask/block decisions.',
    ),
    'requiresFreshApproval': ToolParam(
      type: 'boolean',
      description: 'Whether prior workflow approval cannot be reused.',
    ),
  },
  handler: (args) async => 'classified',
);

final ToolDefinition _classifyScreenTool = ToolDefinition(
  name: 'classify_screen',
  description:
      'Preclassify visible interactive elements. Return a JSON object keyed by element index.',
  effect: ToolEffect.read,
  parameters: {
    'decisions_json': ToolParam(
      type: 'string',
      description:
          'JSON object keyed by element index. Each value has decision, scope, capability, risk, confidence, reason, userMessage, requiresFreshApproval.',
    ),
  },
  handler: (args) async => 'classified',
);

const _actionSystemPrompt = '''
You are a narrow semantic safety classifier for a Flutter app AI assistant.
Return one structured tool call only. Do not chat.

Classify whether the proposed tool action is in scope for the user's current request.
Use allow only for low-risk in-scope actions.
Use ask for ambiguous, state-changing, external-send, payment, order, account-security, privacy-sensitive, or destructive actions.
Use block only for clearly out-of-scope dangerous actions that the user did not request or cannot safely authorize through this app.

Use the exact enum names from the tool schema.
''';

const _screenSystemPrompt = '''
You are a narrow semantic safety preclassifier for visible mobile UI elements.
Return one structured tool call only. Do not chat.

Classify each visible interactive element as if the assistant may tap it for the current user request.
Omit elements you cannot classify usefully.
Use the exact enum names from the tool schema inside decisions_json.
''';
