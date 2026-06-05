import 'types.dart';

// ── Verification Types ─────────────────────────────────────────────────────

/// Verification status for action outcomes.
enum VerificationStatus { success, error, uncertain }

/// Kind of failure - whether it's recoverable by the agent.
enum VerificationFailureKind { controllable, uncontrollable }

/// Snapshot of screen state for verification.
class VerificationSnapshot {
  final String screenName;
  final String screenContent;
  final List<InteractiveElement> elements;
  final String? screenshot;

  const VerificationSnapshot({
    required this.screenName,
    required this.screenContent,
    required this.elements,
    this.screenshot,
  });

  @override
  String toString() {
    return 'VerificationSnapshot(screen: $screenName, elements: ${elements.length})';
  }
}

/// Action being verified.
class VerificationAction {
  final String toolName;
  final Map<String, dynamic> args;
  final String label;
  final InteractiveElement? targetElement;

  const VerificationAction({
    required this.toolName,
    required this.args,
    required this.label,
    this.targetElement,
  });

  @override
  String toString() {
    return 'VerificationAction(tool: $toolName, label: $label)';
  }
}

/// Context for performing verification.
class VerificationContext {
  final String goal;
  final VerificationAction action;
  final VerificationSnapshot preAction;
  final VerificationSnapshot postAction;

  const VerificationContext({
    required this.goal,
    required this.action,
    required this.preAction,
    required this.postAction,
  });
}

/// Result of verification.
class VerificationResult {
  final VerificationStatus status;
  final VerificationFailureKind failureKind;
  final String evidence;
  final String source; // 'deterministic' or 'llm'
  final List<String>? missingFields;
  final List<String>? validationMessages;

  const VerificationResult({
    required this.status,
    required this.failureKind,
    required this.evidence,
    required this.source,
    this.missingFields,
    this.validationMessages,
  });

  @override
  String toString() {
    return 'VerificationResult(status: $status, source: $source, evidence: $evidence)';
  }
}

/// Pending verification waiting for post-action snapshot.
class PendingVerification {
  final String goal;
  final VerificationAction action;
  final VerificationSnapshot preAction;
  final int followupSteps;

  const PendingVerification({
    required this.goal,
    required this.action,
    required this.preAction,
    required this.followupSteps,
  });
}

/// Outcome Verifier - Detects success/failure of critical UI actions.
///
/// Uses a two-stage approach:
/// 1. Deterministic verification - Pattern matching for success/error signals
/// 2. LLM verification - Falls back to AI analysis when uncertain
class OutcomeVerifier {
  final AiProvider provider;
  final AgentConfig config;

  OutcomeVerifier({
    required this.provider,
    required this.config,
  });

  /// Check if verifier is enabled.
  bool isEnabled() {
    return config.verifier?.enabled ?? true;
  }

  /// Get maximum followup steps for recovery attempts.
  int getMaxFollowupSteps() {
    return config.verifier?.maxFollowupSteps ?? 2;
  }

  /// Check if an action is critical (requires verification).
  bool isCriticalAction(VerificationAction action) {
    if (action.targetElement?.properties['requiresConfirmation'] == true) {
      return true;
    }

    if (!const ['tap', 'long_press', 'adjust_slider', 'select_picker', 'set_date']
        .contains(action.toolName)) {
      return false;
    }

    final label = action.label.toLowerCase();
    return _commitActionPattern.hasMatch(label);
  }

  /// Verify action outcome using deterministic and LLM-based methods.
  Future<VerificationResult> verify(VerificationContext context) async {
    // Stage 1: Deterministic verification
    final stageA = _deterministicVerify(context);
    if (stageA.status != VerificationStatus.uncertain) {
      return stageA;
    }

    // Stage 2: LLM verification fallback
    final stageB = await _llmVerify(context);
    return stageB ?? stageA;
  }

  // ── Deterministic Verification ────────────────────────────────────────

  static final RegExp _commitActionPattern =
      RegExp(
        r'\b(save|submit|confirm|apply|pay|place|update|continue|finish|send|checkout|complete|verify|review|publish|post|delete|cancel|add|remove|buy|purchase|book|order|subscribe|activate|deactivate)\b',
        caseSensitive: false,
      );

  static final List<RegExp> _successSignalPatterns = [
    RegExp(
      r'\b(success|successful|saved|updated|submitted|completed|done|confirmed|applied|verified|added|removed|activated|deactivated)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bthank you\b', caseSensitive: false),
    RegExp(r'\border confirmed\b', caseSensitive: false),
    RegExp(r'\bchanges saved\b', caseSensitive: false),
  ];

  static final List<RegExp> _errorSignalPatterns = [
    RegExp(r'\berror\b', caseSensitive: false),
    RegExp(r'\bfailed\b', caseSensitive: false),
    RegExp(r'\binvalid\b', caseSensitive: false),
    RegExp(r'\brequired\b', caseSensitive: false),
    RegExp(r'\bincorrect\b', caseSensitive: false),
    RegExp(r'\btry again\b', caseSensitive: false),
    RegExp(r'\bcould not\b', caseSensitive: false),
    RegExp(r'\bunable to\b', caseSensitive: false),
    RegExp(r'\bverification\b.{0,30}\b(error|failed|invalid|required)\b', caseSensitive: false),
    RegExp(r'\bcode\b.{0,30}\b(error|failed|invalid|required)\b', caseSensitive: false),
  ];

  static final List<RegExp> _uncontrollableErrorPatterns = [
    RegExp(r'\bnetwork\b', caseSensitive: false),
    RegExp(r'\bserver\b', caseSensitive: false),
    RegExp(r'\bservice unavailable\b', caseSensitive: false),
    RegExp(r'\btemporarily unavailable\b', caseSensitive: false),
    RegExp(r'\btimeout\b', caseSensitive: false),
    RegExp(r'\btry later\b', caseSensitive: false),
    RegExp(r'\bconnection\b', caseSensitive: false),
  ];

  static final Set<ElementType> _inputFieldTypes = {
    ElementType.textInput,
    ElementType.picker,
    ElementType.datePicker,
    ElementType.slider,
  };

  static final List<RegExp> _fieldMessagePatterns = [
    RegExp(r'^(.+?)\s+(?:is|are)\s+(?:required|invalid|missing)\b', caseSensitive: false),
    RegExp(r'^please\s+(?:enter|provide|select)\s+(.+?)\b', caseSensitive: false),
    RegExp(r'^(.+?)\s+cannot\s+be\s+empty\b', caseSensitive: false),
  ];

  static final List<RegExp> _ignoredEmptyFieldPatterns = [
    RegExp(r'\btype your address\b', caseSensitive: false),
    RegExp(r'\bstreet name\b', caseSensitive: false),
    RegExp(r'\blandmark\b', caseSensitive: false),
    RegExp(r'^\+\d+$'),
    RegExp(r'\bcontact information\b', caseSensitive: false),
  ];

  VerificationResult _deterministicVerify(VerificationContext context) {
    final normalizedPost = _normalizeText(context.postAction.screenContent);
    final validationMessages = _extractValidationMessages(context.postAction.screenContent);
    final missingFields = _inferMissingFields(
      context.postAction.screenContent,
      validationMessages,
      _getVisibleFieldCandidates(context.postAction.elements),
      context.postAction.elements,
    );

    // Check for error signals
    if (_errorSignalPatterns.any((pattern) => pattern.hasMatch(normalizedPost))) {
      final failureKind = _uncontrollableErrorPatterns.any((pattern) => pattern.hasMatch(normalizedPost))
          ? VerificationFailureKind.uncontrollable
          : VerificationFailureKind.controllable;
      return VerificationResult(
        status: VerificationStatus.error,
        failureKind: failureKind,
        evidence: 'Visible validation or error feedback appeared after the action.',
        source: 'deterministic',
        missingFields: missingFields,
        validationMessages: validationMessages,
      );
    }

    // Check for navigation (strong success signal)
    if (context.postAction.screenName != context.preAction.screenName) {
      return VerificationResult(
        status: VerificationStatus.success,
        failureKind: VerificationFailureKind.controllable,
        evidence: 'The app navigated from "${context.preAction.screenName}" to "${context.postAction.screenName}".',
        source: 'deterministic',
        missingFields: missingFields,
        validationMessages: validationMessages,
      );
    }

    // Check for success signals
    if (_successSignalPatterns.any((pattern) => pattern.hasMatch(normalizedPost))) {
      return VerificationResult(
        status: VerificationStatus.success,
        failureKind: VerificationFailureKind.controllable,
        evidence: 'The current screen shows explicit success or completion language.',
        source: 'deterministic',
        missingFields: missingFields,
        validationMessages: validationMessages,
      );
    }

    // Check if commit control disappeared
    if (context.action.targetElement != null &&
        _elementStillPresent(context.preAction.elements, context.action.targetElement!) &&
        !_elementStillPresent(context.postAction.elements, context.action.targetElement!)) {
      return VerificationResult(
        status: VerificationStatus.success,
        failureKind: VerificationFailureKind.controllable,
        evidence: 'The commit control is no longer present on the current screen.',
        source: 'deterministic',
        missingFields: missingFields,
        validationMessages: validationMessages,
      );
    }

    // Unable to determine
    return VerificationResult(
      status: VerificationStatus.uncertain,
      failureKind: VerificationFailureKind.controllable,
      evidence: 'The current UI does not yet prove either success or failure.',
      source: 'deterministic',
      missingFields: missingFields,
      validationMessages: validationMessages,
    );
  }

  // ── LLM Verification ──────────────────────────────────────────────────

  Future<VerificationResult?> _llmVerify(VerificationContext context) async {
    final verificationTool = ToolDefinition(
      name: 'report_verification',
      description: 'Report whether the action succeeded, failed, or remains uncertain based only on the UI evidence.',
      parameters: {
        'status': ToolParam(
          type: 'string',
          description: 'success, error, or uncertain',
          required: true,
        ),
        'failureKind': ToolParam(
          type: 'string',
          description: 'controllable or uncontrollable',
          required: true,
        ),
        'evidence': ToolParam(
          type: 'string',
          description: 'Brief explanation grounded in the current UI evidence',
          required: true,
        ),
      },
      handler: (args) async => 'reported',
    );

    final systemPrompt = [
      'You are an outcome verifier for a mobile app agent.',
      'Your job is to decide whether the last critical UI action actually succeeded.',
      'The current UI is the source of truth. Ignore the actor model\'s prior claims when they conflict with the UI.',
      'Return success only when the current UI clearly proves completion.',
      'Return error when the UI shows validation, verification, submission, or other failure feedback.',
      'Return uncertain when the UI does not yet prove either success or error.',
    ].join(' ');

    final userPrompt = [
      '<goal>${context.goal}</goal>',
      '<action tool="${context.action.toolName}" label="${context.action.label}">${_argsToString(context.action.args)}</action>',
      '<pre_action screen="${context.preAction.screenName}">\n${context.preAction.screenContent}\n</pre_action>',
      '<post_action screen="${context.postAction.screenName}">\n${context.postAction.screenContent}\n</post_action>',
    ].join('\n\n');

    try {
      final response = await provider.generateContent(
        systemPrompt: systemPrompt,
        userMessage: userPrompt,
        tools: [verificationTool],
        history: [],
        screenshotBase64: context.postAction.screenshot,
      );

      final actionName = response.actionName;
      final actionParams = response.actionParams;

      if (actionName != 'report_verification' || actionParams == null) {
        return null;
      }

      final statusStr = actionParams['status'] as String?;
      final failureKindStr = actionParams['failureKind'] as String?;
      final evidence = actionParams['evidence'] as String?;

      VerificationStatus? status;
      if (statusStr == 'success') {
        status = VerificationStatus.success;
      } else if (statusStr == 'error') {
        status = VerificationStatus.error;
      } else if (statusStr == 'uncertain') {
        status = VerificationStatus.uncertain;
      }

      VerificationFailureKind? failureKind;
      if (failureKindStr == 'controllable') {
        failureKind = VerificationFailureKind.controllable;
      } else if (failureKindStr == 'uncontrollable') {
        failureKind = VerificationFailureKind.uncontrollable;
      }

      if (status == null || failureKind == null || evidence == null || evidence.isEmpty) {
        return null;
      }

      return VerificationResult(
        status: status,
        failureKind: failureKind,
        evidence: evidence,
        source: 'llm',
      );
    } catch (e) {
      // LLM verification failed, fall back to uncertain
      return null;
    }
  }

  // ── Helper Methods ───────────────────────────────────────────────────

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\[[^\]]+\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeFieldName(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanScreenLine(String line) {
    return line
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(r'/>', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _getVisibleFieldCandidates(List<InteractiveElement> elements) {
    final seen = <String>{};
    final labels = <String>[];

    for (final element in elements) {
      if (!_inputFieldTypes.contains(element.type)) continue;
      final label = element.label.trim();
      if (label.isEmpty) continue;
      final normalized = _normalizeFieldName(label);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      labels.add(label);
    }

    return labels;
  }

  List<String> _extractValidationMessages(String screenContent) {
    final seen = <String>{};
    final messages = <String>[];

    for (final rawLine in screenContent.split('\n')) {
      final line = _cleanScreenLine(rawLine);
      if (line.isEmpty) continue;
      if (!_errorSignalPatterns.any((pattern) => pattern.hasMatch(line))) continue;

      final normalized = _normalizeFieldName(line);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      messages.add(line);
    }

    return messages;
  }

  String? _matchFieldCandidate(String fieldText, List<String> candidates) {
    final normalizedField = _normalizeFieldName(fieldText);
    if (normalizedField.isEmpty) return null;

    String? bestMatch;
    var bestScore = -1;

    for (final candidate in candidates) {
      final normalizedCandidate = _normalizeFieldName(candidate);
      if (normalizedCandidate.isEmpty) continue;

      var score = -1;
      if (normalizedCandidate == normalizedField) {
        score = 4;
      } else if (normalizedCandidate.contains(normalizedField)) {
        score = 3;
      } else if (normalizedField.contains(normalizedCandidate)) {
        score = 2;
      } else {
        final fieldTokens = normalizedField.split(' ').where((t) => t.isNotEmpty).toSet();
        final candidateTokens = normalizedCandidate.split(' ');
        final overlap = candidateTokens.where((token) => fieldTokens.contains(token)).length;
        if (overlap > 0) {
          score = overlap;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = candidate;
      }
    }

    return bestScore > 0 ? bestMatch : null;
  }

  String? _extractFieldPhrase(String message) {
    for (final pattern in _fieldMessagePatterns) {
      final match = pattern.firstMatch(message);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool _elementStillPresent(List<InteractiveElement> elements, InteractiveElement target) {
    return elements.any((element) =>
        element.index == target.index ||
        (element.type == target.type &&
            element.label.trim().isNotEmpty &&
            element.label.trim() == target.label.trim()));
  }

  List<String> _inferMissingFields(
    String screenContent,
    List<String> validationMessages,
    List<String> fieldCandidates,
    List<InteractiveElement> elements,
  ) {
    final missingFields = <String>[];
    final seen = <String>{};
    final lines = screenContent.split('\n');

    void addField(String? field) {
      if (field == null || field.isEmpty) return;
      final normalized = _normalizeFieldName(field);
      if (normalized.isEmpty || seen.contains(normalized)) return;
      seen.add(normalized);
      missingFields.add(field);
    }

    if (validationMessages.isNotEmpty && fieldCandidates.isNotEmpty) {
      for (final message in validationMessages) {
        final directField = _extractFieldPhrase(message);
        addField(_matchFieldCandidate(directField ?? '', fieldCandidates));

        if (directField != null && directField.isNotEmpty) continue;

        final messageIndex = lines.indexWhere((line) => _cleanScreenLine(line) == message);
        if (messageIndex == -1) continue;

        for (var offset = 1; offset <= 8; offset++) {
          if (messageIndex - offset < 0) break;
          final candidateLine = lines[messageIndex - offset];
          addField(_matchFieldCandidate(_cleanScreenLine(candidateLine), fieldCandidates));
          if (missingFields.isNotEmpty) break;
        }
      }
    }

    // Add empty required fields
    for (final element in elements) {
      if (!_inputFieldTypes.contains(element.type)) continue;
      final label = element.label.trim();
      if (label.isEmpty || _shouldIgnoreEmptyField(label)) continue;

      // Check if field has empty value indicator
      final value = element.properties['value'] as String?;
      if (value != null && value.isNotEmpty) continue;

      // Check if field is required (has * in label or properties)
      final isRequired = label.contains('*') ||
          element.properties['required'] == true ||
          element.properties['error'] != null;

      if (isRequired) {
        addField(label.replaceAll('*', '').trim());
      }
    }

    return missingFields;
  }

  bool _shouldIgnoreEmptyField(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty || !RegExp(r'[a-z]', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    return _ignoredEmptyFieldPatterns.any((pattern) => pattern.hasMatch(trimmed));
  }

  String _argsToString(Map<String, dynamic> args) {
    if (args.isEmpty) return '{}';
    // Simplify for display - don't include full object serialization
    final buffer = StringBuffer('{');
    var first = true;
    for (final entry in args.entries) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('${entry.key}: ');
      final value = entry.value;
      if (value is String) {
        buffer.write('"$value"');
      } else if (value is Map || value is List) {
        buffer.write('[...]');
      } else {
        buffer.write(value);
      }
    }
    buffer.write('}');
    return buffer.toString();
  }
}

// ── Factory Functions ─────────────────────────────────────────────────────

/// Create a verification snapshot.
VerificationSnapshot createVerificationSnapshot({
  required String screenName,
  required String screenContent,
  required List<InteractiveElement> elements,
  String? screenshot,
}) {
  return VerificationSnapshot(
    screenName: screenName,
    screenContent: screenContent,
    elements: elements,
    screenshot: screenshot,
  );
}

/// Build a verification action from tool execution.
VerificationAction buildVerificationAction({
  required String toolName,
  required Map<String, dynamic> args,
  required List<InteractiveElement> elements,
  required String fallbackLabel,
}) {
  final targetElement = args['index'] is int
      ? elements.where((e) => e.index == (args['index'] as int)).firstOrNull
      : null;

  return VerificationAction(
    toolName: toolName,
    args: args,
    label: targetElement?.label ?? fallbackLabel,
    targetElement: targetElement,
  );
}

/// Check if a verification action is critical.
bool isCriticalVerificationAction(VerificationAction action) {
  final verifier = OutcomeVerifier(
    provider: _DummyProvider(),
    config: AgentConfig(),
  );
  return verifier.isCriticalAction(action);
}

/// Check if an action needs verification based on tool name and label.
bool needsVerification(String toolName, String? elementLabel, Map<String, dynamic>? elementProperties) {
  if (elementProperties?.containsKey('requiresConfirmation') == true &&
      elementProperties!['requiresConfirmation'] == true) {
    return true;
  }

  if (!const ['tap', 'long_press', 'adjust_slider', 'select_picker', 'set_date'].contains(toolName)) {
    return false;
  }

  final label = (elementLabel ?? '').toLowerCase();
  return OutcomeVerifier._commitActionPattern.hasMatch(label);
}

// Dummy provider for static method access
class _DummyProvider extends AiProvider {
  @override
  Future<ProviderResult> generateContent({
    required String systemPrompt,
    required String userMessage,
    required List<ToolDefinition> tools,
    required List<AgentStep> history,
    String? screenshotBase64,
    List<UserImage>? userImages,
  }) async {
    return ProviderResult();
  }
}
