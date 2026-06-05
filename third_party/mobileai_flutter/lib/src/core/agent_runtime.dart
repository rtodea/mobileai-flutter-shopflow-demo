import 'dart:async';
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';
import 'action_registry.dart';
import 'block_registry.dart';
import 'data_registry.dart';
import 'default_action_safety_classifier.dart';
import 'element_tree_walker.dart';
import 'flutter_platform_adapter.dart';
import 'screen_dehydrator.dart';
import 'system_prompt.dart';
import 'zone_registry.dart';
import 'verifier.dart';
import '../tools/types.dart';
import '../tools/tap_tool.dart';
import '../tools/type_tool.dart';
import '../tools/scroll_tool.dart';
import '../tools/keyboard_tool.dart';
import '../tools/long_press_tool.dart';
import '../tools/slider_tool.dart';
import '../tools/picker_tool.dart';
import '../tools/guide_tool.dart';
import '../tools/date_picker_tool.dart';
import '../tools/knowledge_tool.dart';
import '../services/knowledge_base_service.dart';
import '../utils/logger.dart';
import '../widgets/highlight_overlay.dart';

class AgentRuntime {
  final AiProvider provider;
  final AgentConfig config;
  final GlobalKey rootKey;
  final GlobalKey<NavigatorState>? navKey;
  late final PlatformAdapter _platformAdapter;

  final Map<String, AgentTool> _tools = {};
  final List<AgentStep> _history = [];
  bool _isRunning = false;
  bool _isCancelRequested = false;

  List<InteractiveElement> _lastElements = [];
  String? _lastScreenName;

  /// Knowledge base service for RAG capabilities.
  KnowledgeBaseService? _knowledgeService;

  /// Approval workflow state for copilot mode.
  AppActionApprovalScope _approvalScope = AppActionApprovalScope.none;
  AppActionApprovalSource _approvalSource = AppActionApprovalSource.none;

  /// Semantic action-safety state for the current task.
  final Map<String, ActionSafetyDecision> _actionSafetyCache = {};
  final Map<String, Future<void>> _screenSafetyPreclassifications = {};
  final Set<String> _actionSafetyApprovedBoundaries = {};
  ActionSafetyClassifier? _defaultActionSafetyClassifier;
  ScreenSnapshot? _lastScreenSnapshot;
  String? _currentScreenContent;
  String? _currentScreenSignature;
  String? _currentTaskId;
  int _taskCounter = 0;

  /// Outcome verifier for critical action verification.
  OutcomeVerifier? _verifier;
  PendingVerification? _pendingCriticalVerification;
  String? _pendingScreenshot;
  String? _verificationObservation;
  _VerifiedCriticalAction? _lastVerifiedCriticalAction;

  /// Current goal for verification context.
  String? _lastGoal;

  /// Error handling state for graceful error suppression.
  void Function(FlutterErrorDetails)? _originalErrorHandler;
  Timer? _errorGraceTimer;

  /// Tools that physically alter the app — must be gated by workflow approval.
  static const Set<String> _appActionTools = {
    'tap',
    'type',
    'scroll',
    'navigate',
    'keyboard',
    'long_press',
    'adjust_slider',
    'select_picker',
    'set_date',
  };

  static const Set<String> _nonSafetyGatedTools = {
    'done',
    'wait',
    'ask_user',
    'query_data',
    'query_knowledge',
  };

  /// Tools that create UI effects. Companion mode blocks these before
  /// execution so the assistant can guide the user without controlling the app.
  static const Set<String> _companionBlockedTools = {
    'tap',
    'type',
    'scroll',
    'keyboard',
    'navigate',
    'long_press',
    'adjust_slider',
    'select_picker',
    'set_date',
    'guide_user',
    'simplify_zone',
    'restore_zone',
    'render_block',
    'inject_card',
  };

  /// Must hold the SemanticsHandle so the semantics tree stays enabled.
  /// Without this, RendererBinding.pipelineOwner.semanticsOwner is null.
  SemanticsHandle? _semanticsHandle;

  AgentRuntime({
    required this.provider,
    required this.config,
    required this.rootKey,
    this.navKey,
  }) {
    _registerBuiltInTools();
    _platformAdapter =
        config.platformAdapter ??
        FlutterPlatformAdapter(
          config: config,
          rootKey: rootKey,
          navigatorKey: navKey,
          getCurrentScreenName: _getCurrentScreenName,
          getRouteNames: _getRouteNames,
        );
    // Initialize knowledge base service if configured
    if (config.knowledgeBase != null) {
      _knowledgeService = KnowledgeBaseService(
        config.knowledgeBase,
        config.knowledgeMaxTokens,
      );
      Logger.info('Knowledge base service initialized');
    }

    // Initialize approval scope if configured
    if (config.initialApprovalScope != null) {
      _approvalScope = config.initialApprovalScope!;
      Logger.info('Initial approval scope: $_approvalScope');
    }

    // Initialize verifier if enabled
    if (config.verifier?.enabled ?? true) {
      _verifier = OutcomeVerifier(provider: provider, config: config);
      Logger.info('Outcome verifier initialized');
    }

    // Enable Flutter's semantics tree — required for ElementTreeWalker.
    // Works transparently in production apps with zero developer setup.
    // The handle is released in dispose() to avoid unnecessary overhead
    // when the agent is not active.
    _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  }

  /// Release the semantics handle. Call when the runtime is no longer needed.
  void dispose() {
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
    _stopErrorSuppression();
  }

  /// Start error suppression mode during critical operations.
  void _startErrorSuppression() {
    if (!config.reportErrorsAsExceptions) return;

    _originalErrorHandler = FlutterError.onError;

    FlutterError.onError = (details) {
      // Log the error but don't crash
      Logger.warn('Suppressed Flutter error: ${details.exception}');
      Logger.debug('Stack trace: ${details.stack}');

      // Also notify via onError callback if configured
      config.onError?.call(
        details.exception,
        ExecutionResult(
          success: false,
          message: 'Error suppressed: ${details.exception}',
          steps: List.from(_history),
        ),
      );
    };
  }

  /// Stop error suppression with a grace period.
  void _stopErrorSuppression({Duration? gracePeriod}) {
    gracePeriod ??= config.gracePeriod;

    // Cancel any existing grace timer
    _errorGraceTimer?.cancel();

    // Set up grace period before restoring original error handler
    _errorGraceTimer = Timer(gracePeriod, () {
      if (_originalErrorHandler != null) {
        FlutterError.onError = _originalErrorHandler;
        _originalErrorHandler = null;
        Logger.info('Original error handler restored after grace period');
      }
      _errorGraceTimer = null;
    });
  }

  /// Request cancellation of the current task.
  /// The execution loop will exit cleanly at the next step boundary.
  void cancel() {
    _isCancelRequested = true;
  }

  /// Cancel and wait until the execute loop has actually stopped.
  /// Polls `_isRunning` every 50ms until false or timeout.
  Future<void> cancelAndWait({int timeoutMs = 5000}) async {
    cancel();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (_isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  AgentConfig getConfig() => config;
  bool getIsRunning() => _isRunning;

  // ─── Approval Workflow Methods ─────────────────────────────────

  /// Check if a tool needs approval based on current scope.
  bool _needsApproval(String toolName) {
    if (config.interactionMode == AppInteractionMode.companion) {
      return false;
    }

    if (config.interactionMode == AppInteractionMode.autopilot) {
      return false;
    }

    // Only UI-altering tools need approval
    if (!_appActionTools.contains(toolName)) {
      return false;
    }

    // Check current approval scope
    return _approvalScope == AppActionApprovalScope.none;
  }

  /// Check if workflow approval is currently granted.
  bool _hasWorkflowApproval() {
    return _approvalScope == AppActionApprovalScope.workflow;
  }

  /// Grant workflow approval for the current task.
  void _grantWorkflowApproval(AppActionApprovalSource source) {
    _approvalScope = AppActionApprovalScope.workflow;
    _approvalSource = source;
    Logger.info('Workflow approval granted (source: $source)');
  }

  /// Get current approval scope (for testing/debugging).
  AppActionApprovalScope getApprovalScope() => _approvalScope;

  /// Get current approval source (for testing/debugging).
  AppActionApprovalSource getApprovalSource() => _approvalSource;

  /// Clear workflow approval when a new user task starts.
  void resetAppActionApproval([String reason = 'reset']) {
    _approvalScope = AppActionApprovalScope.none;
    _approvalSource = AppActionApprovalSource.none;
    _actionSafetyApprovedBoundaries.clear();
    Logger.info('Workflow approval cleared ($reason)');
  }

  bool _isActionSafetyEnabled() {
    return config.actionSafety.enabled;
  }

  ActionSafetyClassifier? _getActionSafetyClassifier() {
    if (config.actionSafety.classifierDisabled) return null;
    final custom = config.actionSafety.customClassifier;
    if (custom != null) return custom;
    if (config.actionSafety.classifier ==
        ActionSafetyClassifierSetting.defaultClassifier) {
      return _defaultActionSafetyClassifier ??= DefaultActionSafetyClassifier(
        config: config,
      );
    }
    return null;
  }

  String _getScreenSignature(ScreenSnapshot? screen, String? screenContent) {
    if (screen == null) return 'no-screen';
    final elementSummary = screen.elements
        .map((element) {
          return '${element.index}:${element.type.name}:${element.label}:${jsonEncode(element.properties)}';
        })
        .join('|');
    return _hashString(
      [
        screen.screenName,
        screen.availableScreens.join(','),
        screenContent ?? screen.elementsText,
        elementSummary,
      ].join('\n'),
    );
  }

  String _getElementSignature(InteractiveElement? element) {
    if (element == null) return 'no-target';
    return _hashString(
      [
        element.index,
        element.type.name,
        element.label,
        jsonEncode(element.properties),
      ].join('|'),
    );
  }

  String _getElementSafetyCacheKey(
    String screenSignature,
    InteractiveElement element,
  ) {
    return '${_currentTaskId ?? 'task'}:$screenSignature:element:${element.index}:${_getElementSignature(element)}';
  }

  String _getActionSafetyCacheKey(
    String screenSignature,
    String toolName,
    Map<String, dynamic> args,
    InteractiveElement? targetElement,
  ) {
    if (targetElement != null) {
      return _getElementSafetyCacheKey(screenSignature, targetElement);
    }
    return '${_currentTaskId ?? 'task'}:$screenSignature:tool:$toolName:${_hashString(jsonEncode(args))}';
  }

  String _hashString(String value) {
    return value.hashCode.toUnsigned(32).toRadixString(16);
  }

  InteractiveElement? _getPolicyTargetElement(
    String toolName,
    Map<String, dynamic> args,
  ) {
    if (!_appActionTools.contains(toolName) &&
        !_companionBlockedTools.contains(toolName)) {
      return null;
    }
    final rawIndex = args['index'];
    if (rawIndex is! int) return null;
    return _lastElements
        .where((element) => element.index == rawIndex)
        .firstOrNull;
  }

  ToolDefinition? _getToolDefinition(String name) {
    final customTool = config.customTools[name];
    if (customTool != null) return customTool;

    final customAction = actionRegistry.getAction(name);
    if (customAction != null) {
      final toolParams = <String, ToolParam>{};
      for (final entry in customAction.parameters.entries) {
        final key = entry.key;
        final val = entry.value;
        if (val is String) {
          toolParams[key] = ToolParam(
            type: 'string',
            description: val,
            required: true,
          );
        } else if (val is ActionParameterDef) {
          toolParams[key] = ToolParam(
            type: val.type,
            description: val.description,
            enumValues: val.enumValues,
            required: val.required,
          );
        }
      }
      return ToolDefinition(
        name: customAction.name,
        description: customAction.description,
        parameters: toolParams,
        effect: customAction.effect,
        handler: (args) async => (await customAction.handler(args)).toString(),
      );
    }

    final builtIn = _getBuiltInToolInstance(name);
    if (builtIn != null) return builtIn.definition;

    if (name == 'navigate') {
      return ToolDefinition(
        name: 'navigate',
        description: 'Navigate to a safe top-level screen.',
        effect: ToolEffect.navigate,
        parameters: const {},
        handler: (args) async => 'navigate',
      );
    }
    if (name == 'wait') {
      return ToolDefinition(
        name: 'wait',
        description: 'Wait for loading states or transitions.',
        effect: ToolEffect.read,
        parameters: const {},
        handler: (args) async => 'wait',
      );
    }
    if (name == 'query_data') {
      return ToolDefinition(
        name: 'query_data',
        description: 'Query app-registered data.',
        effect: ToolEffect.read,
        parameters: const {},
        handler: (args) async => 'query_data',
      );
    }
    if (name == 'ask_user') {
      return ToolDefinition(
        name: 'ask_user',
        description: 'Ask the user a question or request approval.',
        effect: ToolEffect.read,
        parameters: const {},
        handler: (args) async => 'ask_user',
      );
    }
    return null;
  }

  ToolEffect _getToolEffect(String toolName, ToolDefinition? tool) {
    if (tool != null && tool.effect != ToolEffect.unknown) {
      return tool.effect;
    }
    switch (toolName) {
      case 'query_data':
      case 'query_knowledge':
      case 'wait':
        return ToolEffect.read;
      case 'navigate':
      case 'scroll':
      case 'guide_user':
        return ToolEffect.navigate;
      case 'type':
        return ToolEffect.fill;
      case 'keyboard':
      case 'adjust_slider':
      case 'select_picker':
      case 'set_date':
        return ToolEffect.select;
      default:
        return ToolEffect.unknown;
    }
  }

  bool _isSafetyGatedTool(String toolName, ToolDefinition? tool) {
    if (_nonSafetyGatedTools.contains(toolName)) return false;
    if (_appActionTools.contains(toolName)) return true;
    if (_companionBlockedTools.contains(toolName)) return true;
    final effect = _getToolEffect(toolName, tool);
    return effect != ToolEffect.read && effect != ToolEffect.support;
  }

  Future<void> _startScreenSafetyPreclassification({
    required ScreenSnapshot snapshot,
    required String screenContent,
    int? stepIndex,
  }) async {
    if (!_isActionSafetyEnabled() || snapshot.elements.isEmpty) return;
    final classifier = _getActionSafetyClassifier();
    if (classifier == null) return;

    final screenSignature = _getScreenSignature(snapshot, screenContent);
    if (_screenSafetyPreclassifications.containsKey(screenSignature)) return;

    final future = () async {
      try {
        final map = await classifier
            .classifyScreen(
              ScreenSafetyInput(
                userRequest: _lastGoal ?? '',
                screen: snapshot,
                screenContent: screenContent,
                screenSignature: screenSignature,
                mode: config.interactionMode,
                history: _buildSummarizedHistory(),
              ),
            )
            .timeout(config.actionSafety.classifierTimeout);

        for (final entry in map.decisions.entries) {
          final element = snapshot.elements
              .where((element) => element.index == entry.key)
              .firstOrNull;
          if (element == null) continue;
          _actionSafetyCache[_getElementSafetyCacheKey(
                screenSignature,
                element,
              )] =
              entry.value;
        }
        Logger.info(
          'action_safety_preclassified screen=$screenSignature count=${map.decisions.length}',
        );
      } on TimeoutException {
        Logger.warn('action_safety_preclassification_timeout');
      } catch (error) {
        Logger.warn('action_safety_preclassification_failed: $error');
      } finally {
        _screenSafetyPreclassifications.remove(screenSignature);
      }
    }();

    _screenSafetyPreclassifications[screenSignature] = future;
  }

  List<ToolDefinition> getTools() {
    final allTools = _tools.values.map((t) => t.definition).toList();

    // Add dynamically registered actions
    for (final action in actionRegistry.getAll()) {
      final toolParams = <String, ToolParam>{};
      for (final entry in action.parameters.entries) {
        final key = entry.key;
        final val = entry.value;
        if (val is String) {
          toolParams[key] = ToolParam(
            type: 'string',
            description: val,
            required: true,
          );
        } else if (val is ActionParameterDef) {
          toolParams[key] = ToolParam(
            type: val.type,
            description: val.description,
            enumValues: val.enumValues,
            required: val.required,
          );
        }
      }
      allTools.add(
        ToolDefinition(
          name: action.name,
          description: action.description,
          parameters: toolParams,
          effect: action.effect,
          handler: (args) async {
            final res = await action.handler(args);
            return res.toString();
          },
        ),
      );
    }

    // Add knowledge base tool if configured
    if (_knowledgeService != null) {
      final knowledgeTool = KnowledgeTool(
        knowledgeService: _knowledgeService!,
        getCurrentScreenName: _getCurrentScreenName,
      );
      allTools.add(knowledgeTool.definition);
      Logger.info('Knowledge base tool registered');
    }

    if (dataRegistry.getAll().isNotEmpty) {
      allTools.add(
        ToolDefinition(
          name: 'query_data',
          description:
              'Query an app-registered data source for structured async data such as products, recommendations, inventory, pricing, or order status. Use when the app exposes a named data source and it is more reliable than inferring from the current screen.',
          effect: ToolEffect.read,
          parameters: {
            'source': ToolParam(
              type: 'string',
              description: 'The registered data source name to query',
              required: true,
            ),
            'query': ToolParam(
              type: 'string',
              description: 'What data you need from that source',
              required: true,
            ),
          },
          handler: (args) async => 'query_data',
        ),
      );
    }

    allTools.add(
      ToolDefinition(
        name: 'navigate',
        description:
            'Navigate to a safe top-level screen. Do not use for screens that require an item ID or prior selection.',
        effect: ToolEffect.navigate,
        parameters: {
          'screen': ToolParam(
            type: 'string',
            description: 'The target top-level screen name',
            required: true,
          ),
        },
        handler: (args) async => 'navigate',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'wait',
        description:
            'Wait briefly for loading states or transitions to finish.',
        effect: ToolEffect.read,
        parameters: {
          'seconds': ToolParam(
            type: 'integer',
            description: 'How many seconds to wait',
            required: false,
          ),
        },
        handler: (args) async => 'wait',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'simplify_zone',
        description: 'Simplify a registered AI zone to reduce visual clutter.',
        effect: ToolEffect.unknown,
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The zone id to simplify',
            required: true,
          ),
        },
        handler: (args) async => 'simplify_zone',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'restore_zone',
        description: 'Restore a previously simplified or injected AI zone.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The zone id to restore',
            required: true,
          ),
        },
        handler: (args) async => 'restore_zone',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'render_block',
        description:
            'Render a registered block into an AI zone as a local intervention.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The target zone id',
            required: true,
          ),
          'blockType': ToolParam(
            type: 'string',
            description: 'The registered block type to render',
            required: true,
          ),
          'props': ToolParam(
            type: 'string',
            description: 'Optional JSON object props',
            required: false,
          ),
        },
        handler: (args) async => 'render_block',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'inject_card',
        description: 'Deprecated compatibility alias for render_block.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The target zone id',
            required: true,
          ),
          'templateName': ToolParam(
            type: 'string',
            description: 'The legacy card/template name',
            required: true,
          ),
          'props': ToolParam(
            type: 'string',
            description: 'Optional JSON object props',
            required: false,
          ),
        },
        handler: (args) async => 'inject_card',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'done',
        description:
            'Complete the task with a user-facing response. Use text for simple replies, or use reply (JSON string) plus previewText for rich chat replies.',
        parameters: {
          'success': ToolParam(
            type: 'boolean',
            description:
                'True if the goal was successfully completed, false otherwise',
            required: true,
          ),
          'text': ToolParam(
            type: 'string',
            description: 'Response message to the user',
            required: false,
          ),
          'reply': ToolParam(
            type: 'string',
            description:
                'Optional JSON string representing an array of rich reply nodes for chat rendering.',
            required: false,
          ),
          'previewText': ToolParam(
            type: 'string',
            description:
                'Plain text preview used for history, notifications, and transcript previews.',
            required: false,
          ),
          'message': ToolParam(
            type: 'string',
            description: 'Alternative to text parameter',
            required: false,
          ),
        },
        handler: (args) async => 'done',
      ),
    );

    allTools.add(
      ToolDefinition(
        name: 'ask_user',
        description:
            'Communicate with the user. Use this to ask questions, request explicit permission for app actions, answer a direct question, or collect missing low-risk workflow data that can authorize routine in-flow steps.',
        parameters: {
          'question': ToolParam(
            type: 'string',
            description: 'The message or question to say to the user',
            required: true,
          ),
          'request_app_action': ToolParam(
            type: 'boolean',
            description:
                'Set to true when requesting permission to take an action in the app (navigate, tap, investigate). Shows explicit approval buttons to the user.',
            required: true,
          ),
          'grants_workflow_approval': ToolParam(
            type: 'boolean',
            description:
                'Optional. Set to true only when asking for missing low-risk input or a low-risk selection that you will directly apply in the current action workflow. If the user answers, their answer authorizes routine in-flow actions like typing/selecting/toggling, but NOT irreversible final commits or support investigations.',
            required: false,
          ),
        },
        handler: (args) async => 'ask_user',
      ),
    );

    for (final entry in config.customTools.entries) {
      allTools.removeWhere((tool) => tool.name == entry.key);
      allTools.add(entry.value);
    }

    return allTools;
  }

  void _registerBuiltInTools() {
    _tools['tap'] = TapTool();
    _tools['type'] = TypeTool();
    _tools['scroll'] = ScrollTool();
    _tools['keyboard'] = KeyboardTool();
    _tools['long_press'] = LongPressTool();
    _tools['adjust_slider'] = SliderTool();
    _tools['select_picker'] = PickerTool();
    _tools['set_date'] = DatePickerTool();
    _tools['guide_user'] = GuideTool();
    _tools['capture_screenshot'] = _CaptureScreenshotTool(
      onCapture: () async {
        final screenshot = await _platformAdapter.captureScreenshot();
        if (screenshot != null) {
          _pendingScreenshot = screenshot;
          return '✅ Screenshot captured (${(screenshot.length / 1024).round()}KB). '
              'It will be attached to your next reasoning turn for visual analysis.';
        }
        return '❌ Screenshot capture failed.';
      },
    );
  }

  /// Returns the effective tool list for the current execution context.
  /// When companion mode is enabled, strips UI-effect tools while preserving
  /// read/data/support tools. When enableUiControl=false, strips UI-control
  /// tools so the LLM acts as a knowledge-only assistant.
  static const _uiControlTools = {
    'tap',
    'type',
    'scroll',
    'keyboard',
    'navigate',
    'long_press',
    'adjust_slider',
    'select_picker',
    'set_date',
    'guide_user',
    'ask_user',
  };
  List<ToolDefinition> _getEffectiveTools() {
    final all = getTools();
    if (config.interactionMode == AppInteractionMode.companion) {
      return all
          .where((t) => !_companionBlockedTools.contains(t.name))
          .toList();
    }
    if (config.enableUiControl) return all;
    return all.where((t) => !_uiControlTools.contains(t.name)).toList();
  }

  ToolContext _buildToolContext() {
    return ToolContext(
      rootContext: rootKey.currentContext!,
      config: config,
      lastElements: _lastElements,
      observedScreenName: _lastScreenName,
      getCurrentElements: _getCurrentFilteredElements,
      getCurrentScreenName: _getCurrentScreenName,
      getRouteNames: _getRouteNames,
      captureScreenshot: _platformAdapter.captureScreenshot,
    );
  }

  Future<List<InteractiveElement>> _getCurrentFilteredElements() async {
    final snapshot = await _platformAdapter.getScreenSnapshot();
    return _applyInteractivePolicy(snapshot.elements);
  }

  Future<ActionSafetyDecision> _evaluateActionSafety(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final tool = _getToolDefinition(toolName);
    final targetElement = _getPolicyTargetElement(toolName, args);
    final screen = _lastScreenSnapshot;
    final screenContent = _currentScreenContent ?? screen?.elementsText;
    final screenSignature =
        _currentScreenSignature ?? _getScreenSignature(screen, screenContent);
    final toolEffect = _getToolEffect(toolName, tool);

    if (!_isActionSafetyEnabled()) {
      return _normalizeActionSafetyDecision(
        const ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.allow,
          reason: 'Action safety is disabled.',
        ),
        ActionSafetyDecisionSource.disabled,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    if (config.interactionMode == AppInteractionMode.companion &&
        _companionBlockedTools.contains(toolName)) {
      return _normalizeActionSafetyDecision(
        const ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.block,
          reason: 'Companion mode cannot execute UI-control tools.',
          userMessage:
              'Companion mode is guidance-only. I can guide you, but I cannot control the app UI.',
        ),
        ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    if (!_isSafetyGatedTool(toolName, tool)) {
      return _normalizeActionSafetyDecision(
        const ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.allow,
          reason: 'Tool is not action-safety gated.',
        ),
        ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    if (toolEffect == ToolEffect.read ||
        toolEffect == ToolEffect.support ||
        toolEffect == ToolEffect.navigate ||
        toolEffect == ToolEffect.fill ||
        toolEffect == ToolEffect.select) {
      return _normalizeActionSafetyDecision(
        ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.allow,
          reason: 'Known low-risk tool effect: ${toolEffect.name}.',
          confidence: 1,
          capability: _capabilityForToolEffect(toolEffect),
          risk: ActionSafetyRisk.low,
          scope: ActionSafetyScope.unknownTask,
        ),
        ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    if (toolEffect == ToolEffect.stateModify) {
      return _normalizeActionSafetyDecision(
        const ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.ask,
          reason: 'Tool effect "stateModify" may update app state.',
          userMessage:
              'This may update something in the app. Do you want me to continue?',
          confidence: 1,
          capability: ActionSafetyCapability.stateModify,
          risk: ActionSafetyRisk.medium,
          scope: ActionSafetyScope.unknownTask,
        ),
        ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    if (toolEffect == ToolEffect.payment ||
        toolEffect == ToolEffect.commit ||
        toolEffect == ToolEffect.destructive) {
      return _normalizeActionSafetyDecision(
        ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.ask,
          reason: 'Tool effect "${toolEffect.name}" requires confirmation.',
          userMessage:
              'This action may make an important change. Do you want me to continue?',
          confidence: 1,
          capability: _capabilityForToolEffect(toolEffect),
          risk: toolEffect == ToolEffect.destructive
              ? ActionSafetyRisk.critical
              : ActionSafetyRisk.high,
          scope: ActionSafetyScope.unknownTask,
          requiresFreshApproval: true,
        ),
        ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    final cacheKey = _getActionSafetyCacheKey(
      screenSignature,
      toolName,
      args,
      targetElement,
    );
    final cached = _actionSafetyCache[cacheKey];
    if (cached != null) {
      return _normalizeActionSafetyDecision(
        cached,
        ActionSafetyDecisionSource.cache,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    final pending = _screenSafetyPreclassifications[screenSignature];
    if (pending != null) {
      try {
        await pending.timeout(config.actionSafety.classifierTimeout);
      } catch (_) {}
      final refreshed = _actionSafetyCache[cacheKey];
      if (refreshed != null) {
        return _normalizeActionSafetyDecision(
          refreshed,
          ActionSafetyDecisionSource.cache,
          toolName,
          args,
          targetElement,
          screenSignature,
        );
      }
    }

    final classifier = _getActionSafetyClassifier();
    if (classifier == null) {
      return _normalizeActionSafetyDecision(
        ActionSafetyDecision(
          decision: config.actionSafety.classifierDisabled
              ? ActionSafetyDecisionKind.allow
              : config.actionSafety.unknownActionDecision,
          reason: config.actionSafety.classifierDisabled
              ? 'Semantic action safety classifier is disabled by configuration.'
              : 'No semantic action safety classifier is available.',
          userMessage:
              'I am not fully sure what this action will do. Do you want me to continue?',
          capability: ActionSafetyCapability.unknown,
          scope: ActionSafetyScope.unknownTask,
          risk: ActionSafetyRisk.medium,
          confidence: config.actionSafety.classifierDisabled ? 1 : 0,
        ),
        config.actionSafety.classifierDisabled
            ? ActionSafetyDecisionSource.disabled
            : ActionSafetyDecisionSource.deterministic,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }

    try {
      final decision = await classifier
          .classifyAction(
            ActionSafetyInput(
              userRequest: _lastGoal ?? '',
              toolName: toolName,
              args: args,
              targetElement: targetElement,
              screen: screen,
              screenContent: screenContent,
              screenSignature: screenSignature,
              mode: config.interactionMode,
              history: _buildSummarizedHistory(),
              toolEffect: toolEffect,
            ),
          )
          .timeout(config.actionSafety.classifierTimeout);
      final normalized = _normalizeActionSafetyDecision(
        decision,
        ActionSafetyDecisionSource.classifier,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
      _actionSafetyCache[cacheKey] = normalized;
      return normalized;
    } on TimeoutException {
      return _normalizeActionSafetyDecision(
        const ActionSafetyDecision(
          decision: ActionSafetyDecisionKind.ask,
          confidence: 0,
          reason: 'Semantic action safety classifier timed out.',
          userMessage:
              'I need your confirmation before I continue with this action.',
          capability: ActionSafetyCapability.unknown,
          scope: ActionSafetyScope.unknownTask,
          risk: ActionSafetyRisk.medium,
        ),
        ActionSafetyDecisionSource.timeout,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    } catch (error) {
      return _normalizeActionSafetyDecision(
        ActionSafetyDecision(
          decision: config.actionSafety.unknownActionDecision,
          confidence: 0,
          reason: 'Semantic action safety classifier failed: $error',
          userMessage:
              'I am not fully sure this action is safe to do automatically. Do you want me to continue?',
          capability: ActionSafetyCapability.unknown,
          scope: ActionSafetyScope.unknownTask,
          risk: ActionSafetyRisk.medium,
        ),
        ActionSafetyDecisionSource.classifier,
        toolName,
        args,
        targetElement,
        screenSignature,
      );
    }
  }

  ActionSafetyDecision _normalizeActionSafetyDecision(
    ActionSafetyDecision decision,
    ActionSafetyDecisionSource source,
    String? toolName,
    Map<String, dynamic>? args,
    InteractiveElement? targetElement,
    String? screenSignature,
  ) {
    var normalized = decision;
    final context = ActionSafetyDecisionContext(
      source: source,
      toolName: toolName,
      args: args,
      targetElement: targetElement,
      screenName: _lastScreenSnapshot?.screenName ?? _lastScreenName,
      screenSignature: screenSignature,
    );

    final override = config.actionSafety.overrideDecision?.call(
      normalized,
      context,
    );
    if (override != null) {
      normalized = override;
    }

    final confidence = normalized.confidence ?? 1;
    if (normalized.decision == ActionSafetyDecisionKind.allow &&
        confidence < config.actionSafety.minConfidenceToAllow) {
      normalized = normalized.copyWith(
        decision: ActionSafetyDecisionKind.ask,
        reason:
            'Safety confidence ${confidence.toStringAsFixed(2)} is below the allow threshold.',
        userMessage:
            'I am not fully sure this action is safe to do automatically. Do you want me to continue?',
      );
    }

    config.actionSafety.onDecision?.call(normalized, context);
    Logger.info(
      'action_safety_decision source=${source.name} tool=$toolName '
      'target="${targetElement?.label ?? ''}" decision=${normalized.decision.name} '
      'capability=${normalized.capability?.name} risk=${normalized.risk?.name} '
      'confidence=${normalized.confidence} reason=${normalized.reason}',
    );
    return normalized;
  }

  ActionSafetyCapability _capabilityForToolEffect(ToolEffect effect) {
    switch (effect) {
      case ToolEffect.read:
        return ActionSafetyCapability.screenRead;
      case ToolEffect.navigate:
        return ActionSafetyCapability.uiNavigate;
      case ToolEffect.fill:
        return ActionSafetyCapability.uiFill;
      case ToolEffect.select:
        return ActionSafetyCapability.uiSelect;
      case ToolEffect.stateModify:
        return ActionSafetyCapability.stateModify;
      case ToolEffect.support:
        return ActionSafetyCapability.supportEscalate;
      case ToolEffect.payment:
        return ActionSafetyCapability.paymentCommit;
      case ToolEffect.commit:
        return ActionSafetyCapability.orderCommit;
      case ToolEffect.destructive:
        return ActionSafetyCapability.destructive;
      case ToolEffect.unknown:
        return ActionSafetyCapability.unknown;
    }
  }

  Future<String?> _enforceActionSafetyDecision(
    ActionSafetyDecision decision,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    if (decision.decision == ActionSafetyDecisionKind.allow) {
      return null;
    }

    if (decision.decision == ActionSafetyDecisionKind.block) {
      final message =
          decision.userMessage ??
          'Action blocked by safety guard: ${decision.reason}';
      Logger.warn(
        'action_safety_blocked tool=$toolName reason=${decision.reason}',
      );
      return 'SAFETY_BLOCKED: $message Do not retry this action. Explain the limitation to the user and offer a safe alternative.';
    }

    if (_canReuseActionSafetyApproval(decision)) {
      Logger.info('action_safety_approval_reused tool=$toolName');
      return null;
    }

    if (!config.actionSafety.allowUserOverrideForAsk) {
      return 'Action needs approval but user override is disabled: ${decision.reason}';
    }

    if (config.onAskUser == null) {
      return 'Action needs confirmation but no approval UI is available: ${decision.reason}';
    }

    final question =
        decision.userMessage ??
        'I need your confirmation before I continue with this action.';
    Logger.info('action_safety_approval_required tool=$toolName');
    final response = await config.onAskUser!(
      ApprovalRequest(
        actionName: toolName,
        actionParams: args,
        elementLabel: _getPolicyTargetElement(toolName, args)?.label,
        reason: question,
      ),
    );

    if (response == '__APPROVAL_GRANTED__' ||
        RegExp(
          r'^(yes|allow|approve|approved|confirm|continue)$',
          caseSensitive: false,
        ).hasMatch(response.trim())) {
      _rememberActionSafetyApproval(decision);
      if (_needsApproval(toolName) && !decision.requiresFreshApproval) {
        _grantWorkflowApproval(AppActionApprovalSource.userInput);
      }
      Logger.info('action_safety_approved tool=$toolName');
      return null;
    }

    Logger.info('action_safety_rejected tool=$toolName');
    return 'Action "$toolName" requires approval. Request denied.';
  }

  String? _getActionSafetyBoundaryKey(ActionSafetyDecision decision) {
    final scope = decision.scope;
    final capability = decision.capability;
    final risk = decision.risk;
    if (scope == null || capability == null || risk == null) return null;
    return '${scope.name}:${capability.name}:${risk.name}';
  }

  bool _canReuseActionSafetyApproval(ActionSafetyDecision decision) {
    if (config.actionSafety.approvalReuse == ActionSafetyApprovalReuse.none) {
      return false;
    }
    if (decision.requiresFreshApproval) {
      return false;
    }
    if (config.actionSafety.approvalReuse ==
            ActionSafetyApprovalReuse.workflow &&
        _hasWorkflowApproval()) {
      return true;
    }
    final boundary = _getActionSafetyBoundaryKey(decision);
    return boundary != null &&
        _actionSafetyApprovedBoundaries.contains(boundary);
  }

  bool _hasActionSafetyApprovalFor(ActionSafetyDecision decision) {
    final boundary = _getActionSafetyBoundaryKey(decision);
    return boundary != null &&
        _actionSafetyApprovedBoundaries.contains(boundary);
  }

  void _rememberActionSafetyApproval(ActionSafetyDecision decision) {
    final boundary = _getActionSafetyBoundaryKey(decision);
    if (boundary != null) {
      _actionSafetyApprovedBoundaries.add(boundary);
    }
  }

  List<InteractiveElement> _applyInteractivePolicy(
    List<InteractiveElement> elements,
  ) {
    var interactives = elements;

    final blacklist = config.interactiveBlacklist;
    final whitelist = config.interactiveWhitelist;
    if (blacklist != null && blacklist.isNotEmpty) {
      final blackIds = blacklist
          .map((k) => k.currentContext?.findRenderObject()?.debugSemantics?.id)
          .whereType<int>()
          .toSet();
      interactives = interactives.where((e) {
        return e.semanticsNodeId == null ||
            !blackIds.contains(e.semanticsNodeId);
      }).toList();
    }
    if (whitelist != null && whitelist.isNotEmpty) {
      final whiteIds = whitelist
          .map((k) => k.currentContext?.findRenderObject()?.debugSemantics?.id)
          .whereType<int>()
          .toSet();
      interactives = interactives.where((e) {
        return e.semanticsNodeId != null &&
            whiteIds.contains(e.semanticsNodeId);
      }).toList();
    }

    return interactives;
  }

  Future<ExecutionResult> execute(
    String instruction, {
    List<Map<String, String>>? chatHistory,
    List<UserImage>? userImages,
  }) async {
    if (_isRunning) {
      return ExecutionResult(
        success: false,
        message: 'Agent is already running.',
        steps: const [],
      );
    }

    _isRunning = true;
    _isCancelRequested = false;
    _history.clear();
    _lastGoal = instruction;
    _currentTaskId = 'task-${++_taskCounter}';
    _actionSafetyCache.clear();
    _screenSafetyPreclassifications.clear();
    _actionSafetyApprovedBoundaries.clear();
    _currentScreenSignature = null;
    _currentScreenContent = null;
    _lastScreenSnapshot = null;
    _pendingCriticalVerification = null;
    _pendingScreenshot = null;
    _verificationObservation = null;
    _lastVerifiedCriticalAction = null;

    Logger.info('Starting agent execution: "$instruction"');

    // Start error suppression for graceful handling
    _startErrorSuppression();

    try {
      final hasKnowledge = _knowledgeService != null;
      final systemPrompt =
          config.interactionMode == AppInteractionMode.companion
          ? buildCompanionPrompt(
              config.language ?? 'en',
              hasKnowledge: hasKnowledge,
              userInstructions: config.instructions,
            )
          : config.enableUiControl
          ? buildSystemPrompt(
              config.language ?? 'en',
              hasKnowledge: hasKnowledge,
              isCopilot: config.interactionMode != AppInteractionMode.autopilot,
              supportStyle: config.supportStyle,
              userInstructions: config.instructions,
            )
          : buildKnowledgeOnlyPrompt(
              config.language ?? 'en',
              hasKnowledge: hasKnowledge,
              userInstructions: config.instructions,
            );

      for (int step = 1; step <= config.maxSteps; step++) {
        if (_isCancelRequested) {
          return ExecutionResult(
            success: false,
            message: 'Cancelled by user.',
            steps: _history,
          );
        }

        config.onStatusUpdate?.call('Thinking (Step $step)...');
        Logger.info('===== Step $step/${config.maxSteps} =====');

        // 1. Read current platform snapshot
        final snapshot = await _platformAdapter.getScreenSnapshot();
        final interactives = _applyInteractivePolicy(snapshot.elements);
        _lastElements = interactives;

        final elementsText = snapshot.elementsText;
        final screenName = snapshot.screenName;
        _lastScreenName = screenName;
        _lastScreenSnapshot = snapshot;
        _currentScreenContent = elementsText;
        _currentScreenSignature = _getScreenSignature(snapshot, elementsText);
        final routeNames = snapshot.availableScreens;

        unawaited(
          _startScreenSafetyPreclassification(
            snapshot: snapshot,
            screenContent: elementsText,
            stepIndex: step,
          ),
        );

        await _processPendingCriticalVerification(snapshot);

        Logger.info(
          '[AgentRuntime] Step $step snapshot: '
          'screen=$screenName, elementCount=${interactives.length}, '
          'sample=${_summarizeInteractiveElements(interactives)}',
        );
        Logger.info('Screen: $screenName');
        Logger.debug('Dehydrated:\n$elementsText');

        // ── Security: enableUiControl=false → knowledge-only mode ──
        // Get tools, filtering UI tools when control is disabled
        final tools = _getEffectiveTools();

        final maxStepsNum = config.maxSteps;
        final stepInfoBlock =
            '<agent_state>\n<step_info>\nStep $step of $maxStepsNum max possible steps\n</step_info>\n</agent_state>';
        final dynamicPreface = _buildScreenStatePreface(
          instruction: instruction,
          snapshot: snapshot,
        );
        final screenStateBlock = buildScreenStateText(
          screenName: screenName,
          availableScreens: routeNames,
          elementsText: elementsText,
          elements: interactives,
          preface: dynamicPreface,
        );
        // Chat history block (for follow-up requests like "try again")
        String chatBlock = '';
        if (chatHistory != null && chatHistory.isNotEmpty) {
          final buf = StringBuffer('<chat_history>\n');
          for (final msg in chatHistory) {
            buf.writeln('[${msg['role']}]: ${msg['content']}');
          }
          buf.write('</chat_history>');
          chatBlock = '\n\n${buf.toString()}';
        }
        final fullUserMessage =
            '$instruction$chatBlock\n\n$stepInfoBlock\n\n$screenStateBlock';
        // Pass user images on step 0 only; skip screenshot to avoid token overflow
        final stepUserImages = step == 1 ? userImages : null;
        final skipScreenshotForImages =
            step == 1 && userImages != null && userImages.isNotEmpty;

        Logger.info(
          'Sending to AI with ${tools.length} tools...'
          '${stepUserImages != null && stepUserImages.isNotEmpty ? ' with ${stepUserImages.length} user image(s)' : ''}',
        );
        // Consume pending screenshot (set by capture_screenshot tool last turn).
        // Cleared immediately so the next turn defaults back to text-only.
        // Skip screenshot when user images are present to avoid token overflow.
        final screenshotToSend =
            skipScreenshotForImages ? null : _pendingScreenshot;
        _pendingScreenshot = skipScreenshotForImages ? null : null;

        final result = await provider.generateContent(
          systemPrompt: systemPrompt,
          userMessage: fullUserMessage,
          tools: tools,
          history: _buildSummarizedHistory(),
          screenshotBase64: screenshotToSend,
          userImages: stepUserImages,
        );

        // 4. Record Step History
        final actionNameSafe = result.actionName ?? 'unknown';
        final actionParamsSafe = result.actionParams ?? {};

        Logger.info('🧠 Plan: ${result.reasoning?.plan ?? "N/A"}');
        Logger.debug('💾 Memory: ${result.reasoning?.memory ?? "N/A"}');
        Logger.info('Tool: $actionNameSafe($actionParamsSafe)');

        _history.add(
          AgentStep(
            actionName: actionNameSafe,
            actionParams: actionParamsSafe,
            reasoning: result.reasoning,
          ),
        );

        // 5. Execute Action
        if (actionNameSafe == 'done') {
          if (actionParamsSafe['success'] != false &&
              _shouldBlockSuccessCompletion()) {
            Logger.warn(
              '[AgentRuntime] Blocking done(success=true) until pending critical action is verified.',
            );
            _history.last.result =
                'Blocked completion until critical action is verified.';
            continue;
          }
          final result = _buildDoneExecutionResult(actionParamsSafe);
          Logger.info('Task completed: ${result.previewText}');
          _history.last.result = result.previewText;
          return ExecutionResult(
            success: result.success,
            message: result.message,
            reply: result.reply,
            previewText: result.previewText,
            steps: _history,
          );
        }

        config.onStatusUpdate?.call(
          result.reasoning?.plan ?? 'Executing $actionNameSafe...',
        );
        final preActionSnapshot = _createVerificationSnapshotFromScreenSnapshot(
          snapshot,
        );
        final executionMessage = await executeTool(
          actionNameSafe,
          actionParamsSafe,
        );
        Logger.info('Result: $executionMessage');
        _history.last.result = executionMessage;

        if (_toolExecutionAppearsSuccessful(executionMessage)) {
          _maybeStartCriticalVerification(
            toolName: actionNameSafe,
            args: actionParamsSafe,
            preActionSnapshot: preActionSnapshot,
          );
        } else if (actionNameSafe != 'done') {
          _pendingCriticalVerification = null;
        }

        // Let UI settle after action (300ms matches RN default)
        await Future.delayed(const Duration(milliseconds: 300));
      }

      return ExecutionResult(
        success: false,
        message: 'Reached maximum steps limit.',
        previewText: 'Reached maximum steps limit.',
        steps: _history,
      );
    } catch (e) {
      Logger.error('Runtime error: $e');
      return ExecutionResult(
        success: false,
        message: 'Error: ${e.toString()}',
        previewText: 'Error: ${e.toString()}',
        steps: _history,
      );
    } finally {
      _isRunning = false;
      // Stop error suppression with grace period
      _stopErrorSuppression();
    }
  }

  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    final safetyDecision = await _evaluateActionSafety(name, args);
    final safetyBlock = await _enforceActionSafetyDecision(
      safetyDecision,
      name,
      args,
    );
    if (safetyBlock != null) {
      return safetyBlock;
    }
    final actionSafetyAlreadyApproved = _hasActionSafetyApprovalFor(
      safetyDecision,
    );

    VerificationAction? verificationAction;
    if (_verifier != null && _verifier!.isEnabled()) {
      verificationAction = buildVerificationAction(
        toolName: name,
        args: args,
        elements: _lastElements,
        fallbackLabel: name,
      );
      if (_shouldBlockRepeatedVerifiedAction(verificationAction)) {
        final currentScreen = _getCurrentScreenName();
        Logger.warn(
          '[AgentRuntime] Blocking repeated verified action: '
          '${verificationAction.label} on $currentScreen',
        );
        return 'Action "${verificationAction.label}" already appears completed on the current screen. Re-check the current UI before repeating the same consequence-bearing action.';
      }
    }

    // ── Approval Workflow Check ─────────────────────────────────────
    // Check if this tool requires approval and if approval is granted
    if (_needsApproval(name) &&
        !_hasWorkflowApproval() &&
        !actionSafetyAlreadyApproved) {
      // Approval required - ask user for permission
      if (config.onAskUser != null) {
        try {
          // Get element label for better context
          final elementIndex = args['index'] as int?;
          String? elementLabel;
          if (elementIndex != null) {
            final element = _lastElements
                .where((e) => e.index == elementIndex)
                .firstOrNull;
            elementLabel = element?.label;
          }

          final request = ApprovalRequest(
            actionName: name,
            actionParams: args,
            elementLabel: elementLabel,
            reason: 'UI action requires workflow approval',
          );

          Logger.info('Requesting approval for $name');
          final response = await config.onAskUser!(request);

          if (response == '__APPROVAL_GRANTED__') {
            _grantWorkflowApproval(AppActionApprovalSource.userInput);
            Logger.info('Workflow approval granted via user input');
          } else {
            Logger.info('Workflow approval denied by user');
            return 'Action "$name" requires approval. Request denied.';
          }
        } catch (e) {
          Logger.error('Error requesting approval: $e');
          return 'Action "$name" requires approval, but approval system failed: $e';
        }
      } else {
        // No approval callback configured - deny the action
        Logger.warn(
          'Action "$name" requires approval but no onAskUser callback provided',
        );
        return 'Action "$name" requires approval. Please configure onAskUser callback.';
      }
    }

    // ── Highlight before execution ──────────────────────────────────
    _showActionHighlight(name, args);

    // ── Tool Execution ─────────────────────────────────────────────
    String result;

    final customTool = config.customTools[name];
    if (customTool != null) {
      try {
        result = await customTool.handler(args);
      } catch (e) {
        result = 'Tool "$name" failed: $e';
      }
    }
    // 1. Check dynamic actions first
    else if (actionRegistry.getAction(name) != null) {
      final customAction = actionRegistry.getAction(name)!;
      try {
        final actionResult = await customAction.handler(args);
        result = actionResult.toString();
      } catch (e) {
        result = 'Action "$name" failed: $e';
      }
    }
    // 2. Check built-in tool mapped instances
    else if (_getBuiltInToolInstance(name) != null) {
      final toolInstance = _getBuiltInToolInstance(name)!;
      try {
        result = await toolInstance.execute(args, _buildToolContext());
      } catch (e) {
        result = 'Tool "$name" failed: $e';
      }
    }
    // 3. Special case simple inline tools
    else if (name == 'wait') {
      result = await _platformAdapter.executeAction(
        ActionIntent(action: 'wait', args: args),
      );
    } else if (name == 'navigate') {
      final screen = args['screen'] as String?;
      if (screen == null) {
        result = 'Missing screen name';
      } else {
        try {
          result = await _platformAdapter.executeAction(
            ActionIntent(action: 'navigate', args: args),
          );
        } catch (e) {
          result = 'Failed to navigate: $e';
        }
      }
    } else if (name == 'query_data') {
      final source = (args['source'] as String?)?.trim();
      final query = (args['query'] as String?)?.trim();
      if (source == null || source.isEmpty) {
        result = '❌ query_data requires a non-empty source name.';
      } else if (query == null || query.isEmpty) {
        result = '❌ query_data requires a non-empty query.';
      } else {
        final definition = dataRegistry.get(source);
        if (definition == null) {
          result =
              '❌ Unknown data source "$source". Available sources: ${dataRegistry.getAll().map((source) => source.name).join(', ')}';
        } else {
          try {
            final value = await definition.handler(
              DataQueryContext(
                query: query,
                screenName: _getCurrentScreenName(),
              ),
            );
            if (value is String) {
              result = value;
            } else {
              result = jsonEncode(value);
            }
          } catch (e) {
            result = '❌ query_data failed for "$source": $e';
          }
        }
      }
    } else if (name == 'ask_user') {
      String cleanQuestion = (args['question'] as String? ?? '').trim();
      if (cleanQuestion.isNotEmpty) {
        cleanQuestion = cleanQuestion
            .replaceAll(RegExp(r'\[\d+\]'), '')
            .replaceAll(RegExp(r'  +'), ' ')
            .trim();
      }
      if (cleanQuestion.isEmpty) {
        result = 'ask_user requires a non-empty question.';
      } else if (config.onAskUser == null) {
        result = '❓ $cleanQuestion';
      } else {
        final requestAppAction = args['request_app_action'] == true;
        final grantsWorkflowApproval = args['grants_workflow_approval'] == true;
        final answer = await config.onAskUser!(
          AskUserRequest(
            question: cleanQuestion,
            kind: requestAppAction
                ? AskUserKind.approval
                : AskUserKind.freeform,
            requestAppAction: requestAppAction,
            grantsWorkflowApproval: grantsWorkflowApproval,
          ),
        );

        if (answer == '__APPROVAL_GRANTED__') {
          _grantWorkflowApproval(AppActionApprovalSource.explicitButton);
          result = 'User answered: __APPROVAL_GRANTED__';
        } else if (answer == '__APPROVAL_REJECTED__') {
          result = 'Action not approved by user.';
        } else {
          if (grantsWorkflowApproval && answer.trim().isNotEmpty) {
            _grantWorkflowApproval(AppActionApprovalSource.userInput);
          }
          result = 'User answered: $answer';
        }
      }
    } else if (name == 'simplify_zone') {
      final zoneId = args['zoneId'] as String?;
      if (zoneId == null) {
        result = 'Missing zoneId';
      } else {
        final zone = globalZoneRegistry.getZone(zoneId);
        final controller = zone?.controller;
        if (controller == null) {
          result = 'Zone "$zoneId" is not mounted.';
        } else {
          controller.simplify();
          result = 'Simplified zone "$zoneId".';
        }
      }
    } else if (name == 'restore_zone') {
      final zoneId = args['zoneId'] as String?;
      if (zoneId == null) {
        result = 'Missing zoneId';
      } else {
        final zone = globalZoneRegistry.getZone(zoneId);
        final controller = zone?.controller;
        if (controller == null) {
          result = 'Zone "$zoneId" is not mounted.';
        } else {
          controller.restore();
          result = 'Restored zone "$zoneId".';
        }
      }
    } else if (name == 'render_block' || name == 'inject_card') {
      final zoneId = args['zoneId'] as String?;
      final blockType = (args['blockType'] ?? args['templateName']) as String?;
      if (zoneId == null || blockType == null) {
        result = 'Missing zoneId or blockType';
      } else {
        final zone = globalZoneRegistry.getZone(zoneId);
        if (zone == null) {
          result = 'Zone "$zoneId" is not registered.';
        } else if (!globalZoneRegistry.isActionAllowed(
          zoneId,
          ZoneAction.card,
        )) {
          result = 'Zone "$zoneId" does not allow block injection.';
        } else {
          final controller = zone.controller;
          if (controller == null) {
            result = 'Zone "$zoneId" is not mounted.';
          } else {
            final definition = globalBlockRegistry.get(blockType);
            if (definition == null) {
              result = 'Unknown block "$blockType".';
            } else {
              final rawProps = args['props'];
              final props = rawProps is Map<String, dynamic>
                  ? rawProps
                  : rawProps is String && rawProps.trim().isNotEmpty
                  ? Map<String, dynamic>.from(
                      (rawProps.startsWith('{')
                              ? (const JsonDecoder().convert(rawProps) as Map)
                              : const <String, dynamic>{})
                          .map((key, value) => MapEntry('$key', value)),
                    )
                  : <String, dynamic>{};
              controller.renderBlock(
                AiBlockNode(
                  id: '$blockType-${DateTime.now().millisecondsSinceEpoch}',
                  blockType: blockType,
                  props: props,
                  placement: BlockPlacement.zone,
                ),
              );
              result = name == 'inject_card'
                  ? 'Injected "$blockType" in zone "$zoneId". inject_card() is deprecated; prefer render_block().'
                  : 'Rendered "$blockType" in zone "$zoneId".';
            }
          }
        }
      }
    } else {
      result = 'Unknown tool: $name';
    }

    return result;
  }

  static const _highlightableTools = <String, HighlightAction>{
    'tap': HighlightAction.tap,
    'type': HighlightAction.type,
    'scroll': HighlightAction.scroll,
    'long_press': HighlightAction.tap,
    'adjust_slider': HighlightAction.fill,
    'select_picker': HighlightAction.fill,
    'set_date': HighlightAction.fill,
    'keyboard': HighlightAction.type,
  };

  void _showActionHighlight(String toolName, Map<String, dynamic> args) {
    final action = _highlightableTools[toolName];
    if (action == null) return;

    final index = args['index'] as int?;
    if (index == null) return;

    final target = _lastElements.where((e) => e.index == index).firstOrNull;
    if (target == null || target.element == null || !target.element!.mounted) {
      return;
    }

    try {
      final renderObject = target.element!.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      // Scroll into view
      try {
        Scrollable.ensureVisible(
          target.element!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      } catch (_) {}

      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.paintBounds.size;

      final verb = switch (action) {
        HighlightAction.tap => 'Tapping',
        HighlightAction.type => 'Typing into',
        HighlightAction.scroll => 'Scrolling',
        HighlightAction.fill => 'Filling',
        _ => 'Acting on',
      };

      HighlightController.show(HighlightEventData(
        pageX: position.dx,
        pageY: position.dy,
        width: size.width,
        height: size.height,
        message: '$verb ${target.label}',
        action: action,
        autoRemoveAfterMs: 3000,
      ));
    } catch (e) {
      Logger.debug('[AgentRuntime] Highlight failed: $e');
    }
  }

  AgentTool? _getBuiltInToolInstance(String name) {
    switch (name) {
      case 'tap':
        return TapTool();
      case 'type':
        return TypeTool();
      case 'scroll':
        return ScrollTool();
      case 'keyboard':
        return KeyboardTool();
      case 'long_press':
        return LongPressTool();
      case 'adjust_slider':
        return SliderTool();
      case 'select_picker':
        return PickerTool();
      case 'set_date':
        return DatePickerTool();
      case 'guide_user':
        return GuideTool();
      default:
        return null;
    }
  }

  /// Mirrors RN's history summarization:
  /// When history > 8 steps, compress middle steps into a `steps_summary`
  /// to prevent context overflow. Keeps first 2 + last 4 in full detail.
  List<AgentStep> _buildSummarizedHistory() {
    const summarizeThreshold = 8;
    const keepHead = 2;
    const keepTail = 4;

    if (_history.length <= summarizeThreshold) {
      return List.unmodifiable(_history);
    }

    // Build a virtual step that represents the summary of middle steps
    final middleSteps = _history.sublist(keepHead, _history.length - keepTail);
    final summaryLines = middleSteps
        .asMap()
        .entries
        .map((e) {
          final i = keepHead + e.key;
          final step = e.value;
          final resultPreview = step.result ?? step.error ?? 'unknown';
          final succeeded =
              resultPreview.contains('Error') || resultPreview.contains('fail')
              ? 'fail'
              : 'success';
          return 'Step ${i + 1}: ${step.actionName} → $succeeded';
        })
        .join('\n');

    final summaryStep = AgentStep(
      actionName: '__summary__',
      actionParams: {},
      result: '<steps_summary>\n$summaryLines\n</steps_summary>',
    );

    return [
      ..._history.take(keepHead),
      summaryStep,
      ..._history.skip(_history.length - keepTail),
    ];
  }

  String _getCurrentScreenName() {
    if (config.routerAdapter != null) {
      final current = config.routerAdapter!.getCurrentScreenName();
      if (current.isNotEmpty) {
        return current;
      }
    }
    // Try GoRouter first
    if (config.router != null) {
      final matchedLocation = _readGoRouterMatchedLocation(config.router);
      if (matchedLocation != null && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
      try {
        final uri = config.router!.routeInformationProvider.value.uri;
        final path = uri.path.trim();
        if (path.isNotEmpty) {
          return path;
        }
      } catch (_) {}
    }
    // Fall back to Navigator
    if (navKey?.currentState != null) {
      try {
        final route = navKey!.currentState!.widget.pages.lastOrNull;
        return route?.name ?? 'Unknown';
      } catch (_) {}
    }
    return 'Unknown';
  }

  String? _readGoRouterMatchedLocation(dynamic router) {
    try {
      final dynamic state = router.state;
      final matchedLocation = state?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    try {
      final dynamic delegateState = router.routerDelegate?.state;
      final matchedLocation = delegateState?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    try {
      final dynamic currentConfiguration =
          router.routerDelegate?.currentConfiguration;
      final dynamic lastMatch = currentConfiguration?.last;
      final matchedLocation = lastMatch?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    return null;
  }

  List<String> _getRouteNames() {
    if (config.routerAdapter != null) {
      final screens = config.routerAdapter!.getAvailableScreens();
      if (screens.isNotEmpty) return screens;
    }
    // Try GoRouter routes
    if (config.router != null) {
      try {
        final List<String> names = [];
        for (final route in config.router!.configuration.routes) {
          _collectRouteNames(route, names, null);
        }
        return names;
      } catch (_) {}
    }
    return [];
  }

  void _collectRouteNames(
    dynamic route,
    List<String> names,
    String? parentPath,
  ) {
    try {
      final path = route.path as String?;
      if (path != null && path.isNotEmpty && path != '/') {
        names.add(_joinRoutePath(parentPath, path));
      }
      final sub = route.routes as List?;
      if (sub != null) {
        for (final r in sub) {
          _collectRouteNames(
            r,
            names,
            path != null && path.isNotEmpty && path != '/'
                ? _joinRoutePath(parentPath, path)
                : parentPath,
          );
        }
      }
    } catch (_) {}
  }

  String _joinRoutePath(String? parent, String child) {
    if (child.startsWith('/')) {
      return _normalizePath(child);
    }

    final normalizedParent = parent == null || parent.isEmpty || parent == '/'
        ? ''
        : _normalizePath(parent);
    return _normalizePath('$normalizedParent/$child');
  }

  String _normalizePath(String path) {
    final normalized = path.trim().replaceAll(RegExp(r'/+'), '/');
    if (normalized.isEmpty) {
      return '/';
    }
    if (!normalized.startsWith('/')) {
      return '/$normalized';
    }
    return normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  VerificationSnapshot _createVerificationSnapshotFromScreenSnapshot(
    ScreenSnapshot snapshot,
  ) {
    return VerificationSnapshot(
      screenName: snapshot.screenName,
      screenContent: snapshot.elementsText,
      elements: List<InteractiveElement>.from(snapshot.elements),
      screenshot: null,
    );
  }

  ScreenContext getScreenContext() {
    final rootContext = rootKey.currentContext;
    if (rootContext == null) {
      Logger.warn(
        '[AgentRuntime] rootKey.currentContext is null while building screen context.',
      );
    } else {
      Logger.info(
        '[AgentRuntime] Building screen context from root=${rootContext.widget.runtimeType}',
      );
    }
    final walker = ElementTreeWalker(config);
    final interactives = walker.walk(rootKey.currentContext!);
    _lastElements = interactives;
    _lastScreenName = _getCurrentScreenName();
    final elementsText = ScreenDehydrator.dehydrate(interactives);
    Logger.info(
      '[AgentRuntime] Screen context extracted ${interactives.length} interactive elements. '
      'sample=${_summarizeInteractiveElements(interactives)}',
    );
    return ScreenContext(
      screenName: _lastScreenName!,
      availableScreens: _getRouteNames(),
      elementsText: elementsText,
      elements: interactives,
    );
  }

  ExecutionResult _buildDoneExecutionResult(Map<String, dynamic> args) {
    final success = args['success'] != false;
    final text = args['text'] as String?;
    final message = args['message'] as String?;
    final replyPayload = args['reply'];
    final previewText = args['previewText'] as String?;

    final fallbackReplySource = replyPayload ?? text ?? message ?? '';
    var reply = normalizeRichContent(
      fallbackReplySource,
      text ?? message ?? '',
    );

    final structuredReplyCandidate = replyPayload is String
        ? replyPayload
        : text is String
        ? text
        : message is String
        ? message
        : '';
    if (structuredReplyCandidate.trim().isNotEmpty) {
      try {
        final parsedReply = jsonDecode(structuredReplyCandidate);
        reply = normalizeRichContent(parsedReply, text ?? message ?? '');
      } catch (_) {
        reply = normalizeRichContent(
          fallbackReplySource,
          text ?? message ?? '',
        );
      }
    }

    final replyPlainText = richContentToPlainText(reply).trim();
    final effectivePreview =
        previewText != null && previewText.trim().isNotEmpty
        ? previewText
        : replyPlainText.isNotEmpty
        ? replyPlainText
        : text ?? message ?? 'Done';

    return ExecutionResult(
      success: success,
      message: effectivePreview,
      reply: reply.isNotEmpty
          ? reply
          : normalizeRichContent(text ?? message ?? effectivePreview),
      previewText: effectivePreview,
      steps: _history,
    );
  }

  String buildScreenStateText({
    required String screenName,
    required List<String> availableScreens,
    required String elementsText,
    List<InteractiveElement> elements = const <InteractiveElement>[],
    bool includeTags = true,
    String? preface,
  }) {
    final buffer = StringBuffer();
    if (preface != null && preface.isNotEmpty) {
      buffer.writeln(preface);
      buffer.writeln();
    }

    if (includeTags) {
      buffer.writeln('<screen_state>');
    }

    buffer.writeln('Current Screen: $screenName');

    buffer.writeln('Available Screens: ${availableScreens.join(', ')}');

    if (config.screenMap != null) {
      final map = config.screenMap!;
      final routeTruth = availableScreens.toSet();
      final hintedRoutes = routeTruth
          .where((route) => map.screens.containsKey(route))
          .toList(growable: false);

      if (hintedRoutes.isEmpty && routeTruth.isEmpty) {
        buffer.writeln();
        buffer.writeln(
          'Screen Map Hints: generated map provided, but no live route catalog is available.',
        );
      } else if (hintedRoutes.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Screen Map Hints:');
        for (final route in hintedRoutes) {
          final entry = map.screens[route]!;
          final title = entry.title != null && entry.title!.trim().isNotEmpty
              ? ' (${entry.title!.trim()})'
              : '';
          buffer.writeln('- $route$title: ${entry.description}');
        }
      }

      if (map.chains.isNotEmpty) {
        final hintedChains = routeTruth.isEmpty
            ? const <List<String>>[]
            : map.chains
                  .where((chain) => chain.every(routeTruth.contains))
                  .toList(growable: false);
        if (hintedChains.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('Navigation Chain Hints:');
          for (final chain in hintedChains) {
            buffer.writeln('  ${chain.join(' -> ')}');
          }
        }
      }
    }

    final activeStateSummary = ScreenDehydrator.summarizeActiveState(elements);
    if (activeStateSummary.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(activeStateSummary);
    }

    final dataSources = dataRegistry.getAll();
    if (dataSources.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Available Data Sources:');
      for (final source in dataSources) {
        final schemaSummary = source.schema == null || source.schema!.isEmpty
            ? ''
            : ' Fields: ${source.schema!.entries.map((entry) => '${entry.key} (${entry.value.type})').join(', ')}.';
        buffer.writeln('- ${source.name}: ${source.description}$schemaSummary');
      }
    }

    final normalizedElements = elementsText.trim();
    if (normalizedElements.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(normalizedElements);
    }

    if (includeTags) {
      buffer.write('</screen_state>');
    }

    return buffer.toString().trimRight();
  }

  String? _buildScreenStatePreface({
    required String instruction,
    required ScreenSnapshot snapshot,
  }) {
    final observation = _verificationObservation;
    _verificationObservation = null;
    return observation;
  }

  Future<void> _processPendingCriticalVerification(
    ScreenSnapshot snapshot,
  ) async {
    var pending = _pendingCriticalVerification;
    final verifier = _verifier;
    if (pending == null || verifier == null || !verifier.isEnabled()) {
      return;
    }

    pending = PendingVerification(
      goal: pending.goal,
      action: pending.action,
      preAction: pending.preAction,
      followupSteps: pending.followupSteps + 1,
    );
    _pendingCriticalVerification = pending;
    final result = await verifier.verify(
      VerificationContext(
        goal: pending.goal,
        action: pending.action,
        preAction: pending.preAction,
        postAction: _createVerificationSnapshotFromScreenSnapshot(snapshot),
      ),
    );

    Logger.info(
      '[AgentRuntime] Pending verification result: '
      '${result.status} - ${result.evidence}',
    );

    if (result.status == VerificationStatus.success) {
      _verificationObservation =
          'Outcome verifier: The previous action "${pending.action.label}" completed successfully based on the current screen. Do not repeat the same consequence-bearing action unless the user explicitly asks you to do it again.';
      _lastVerifiedCriticalAction = _VerifiedCriticalAction(
        signature: _verificationActionSignature(pending.action),
        screenName: snapshot.screenName,
        label: pending.action.label,
      );
      _pendingCriticalVerification = null;
      return;
    }

    if (result.status == VerificationStatus.error) {
      final details = <String>[
        'Outcome verifier: The previous action "${pending.action.label}" did not complete successfully.',
        result.evidence,
      ];
      if (result.validationMessages != null &&
          result.validationMessages!.isNotEmpty) {
        details.add(
          'Visible validation messages: ${result.validationMessages!.join(' | ')}.',
        );
      }
      if (result.missingFields != null && result.missingFields!.isNotEmpty) {
        details.add(
          'Visible missing required fields: ${result.missingFields!.join(', ')}.',
        );
      }
      _verificationObservation = details.join(' ');
      return;
    }

    final maxFollowupSteps = verifier.getMaxFollowupSteps();
    final ageNote = pending.followupSteps >= maxFollowupSteps
        ? ' This critical action is still unverified after ${pending.followupSteps} follow-up checks.'
        : '';
    _verificationObservation =
        'Outcome verifier: The previous action "${pending.action.label}" is still unverified. ${result.evidence}$ageNote Before calling done(success=true), keep checking for success or error evidence on the current screen.';
  }

  void _maybeStartCriticalVerification({
    required String toolName,
    required Map<String, dynamic> args,
    required VerificationSnapshot preActionSnapshot,
  }) {
    final verifier = _verifier;
    if (verifier == null || !verifier.isEnabled()) {
      return;
    }

    final action = buildVerificationAction(
      toolName: toolName,
      args: args,
      elements: preActionSnapshot.elements,
      fallbackLabel: toolName,
    );

    if (!verifier.isCriticalAction(action)) {
      return;
    }

    _pendingCriticalVerification = PendingVerification(
      goal: _lastGoal ?? 'Complete the requested action',
      action: action,
      preAction: preActionSnapshot,
      followupSteps: 0,
    );
  }

  bool _shouldBlockSuccessCompletion() {
    return _pendingCriticalVerification != null;
  }

  bool _toolExecutionAppearsSuccessful(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('tool "') && normalized.contains('failed')) {
      return false;
    }
    if (normalized.startsWith('failed to')) {
      return false;
    }
    if (normalized.startsWith('missing ')) {
      return false;
    }
    if (normalized.startsWith('unknown tool:')) {
      return false;
    }
    if (normalized.startsWith('safety_blocked:')) {
      return false;
    }
    if (normalized.startsWith('action "') &&
        normalized.contains('requires approval')) {
      return false;
    }
    if (normalized.startsWith('action "') &&
        normalized.contains('already appears completed')) {
      return false;
    }
    if (normalized.startsWith('action not approved by user.')) {
      return false;
    }
    if (normalized.startsWith('could not ')) {
      return false;
    }
    if (normalized.startsWith('❌')) {
      return false;
    }
    return true;
  }

  bool _shouldBlockRepeatedVerifiedAction(VerificationAction action) {
    final verified = _lastVerifiedCriticalAction;
    final verifier = _verifier;
    if (verified == null ||
        verifier == null ||
        !verifier.isCriticalAction(action)) {
      return false;
    }

    return verified.screenName == _getCurrentScreenName() &&
        verified.signature == _verificationActionSignature(action);
  }

  String _verificationActionSignature(VerificationAction action) {
    final target = action.targetElement;
    final identity =
        target?.properties['key']?.toString() ??
        target?.properties['id']?.toString() ??
        action.label.toLowerCase();
    final role =
        target?.properties['role']?.toString() ??
        target?.type.name ??
        'unknown';
    return '${action.toolName}|$role|$identity';
  }

  String _summarizeInteractiveElements(
    List<InteractiveElement> elements, {
    int limit = 8,
  }) {
    if (elements.isEmpty) {
      return '(none)';
    }
    return elements
        .take(limit)
        .map(
          (element) =>
              '[${element.index}] ${element.label} (${element.type.name})',
        )
        .join(' | ');
  }
}

class ScreenContext {
  final String screenName;
  final List<String> availableScreens;
  final String elementsText;
  final List<InteractiveElement> elements;

  ScreenContext({
    required this.screenName,
    required this.availableScreens,
    required this.elementsText,
    this.elements = const <InteractiveElement>[],
  });
}

class _VerifiedCriticalAction {
  final String signature;
  final String screenName;
  final String label;

  const _VerifiedCriticalAction({
    required this.signature,
    required this.screenName,
    required this.label,
  });
}

/// Inline tool that captures a screenshot and stashes it for the next LLM turn.
/// No screenshot is sent to the LLM unless this tool is called.
/// Inline tool that captures a screenshot and stashes it for the next LLM turn.
/// No screenshot is sent to the LLM unless this tool is called.
class _CaptureScreenshotTool implements AgentTool {
  final Future<String> Function() onCapture;

  _CaptureScreenshotTool({required this.onCapture});

  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'capture_screenshot',
    description:
        'Capture the current screen as an image and attach it to your next reasoning turn. '
        'Use only when the user asks about visual content (images, videos, colors, layout appearance) '
        'that cannot be determined from the element tree alone. '
        'The screenshot is consumed by the very next turn and then cleared.',
    parameters: {},
    handler: (_) => throw UnimplementedError('Handled by execute()'),
    effect: ToolEffect.read,
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) =>
      onCapture();
}
