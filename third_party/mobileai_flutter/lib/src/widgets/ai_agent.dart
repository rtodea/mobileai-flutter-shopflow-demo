import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/action_bridge.dart';
import '../core/agent_runtime.dart';
import '../core/data_registry.dart';
import '../core/system_prompt.dart';
import '../core/types.dart';
import '../hooks/ai_scope.dart';
import '../navigation/go_router_adapter.dart';
import '../providers/provider_factory.dart';
import '../services/audio_input_service.dart';
import '../services/audio_output_service.dart';
import '../services/conversation_service.dart';
import '../services/outbound_call_service.dart';
import '../services/telemetry/index.dart';
import '../services/proxy_session_service.dart' as proxy_session;
import '../services/voice_service.dart';
import '../support/index.dart';
import '../theme/rich_ui_theme.dart';
import '../utils/logger.dart';
import 'agent_chat_bar.dart';
import 'agent_overlay.dart';
import 'ai_consent_dialog.dart';
import 'highlight_overlay.dart';
import 'rich_blocks.dart';

class AIAgent extends StatefulWidget {
  final String? apiKey;
  final AiProvider? provider;
  final String? proxyUrl;
  final Map<String, String>? proxyHeaders;
  final String? voiceProxyUrl;
  final Map<String, String>? voiceProxyHeaders;
  final String? model;

  final int maxSteps;
  final String? instructions;
  final dynamic router;
  final FlutterRouterAdapter? routerAdapter;
  final GlobalKey<NavigatorState>? navigatorKey;
  final String language;
  final ScreenMap? screenMap;
  final int? maxTokenBudget;
  final double? maxCostUsd;
  final bool debug;
  final AIConsentConfig? consent;
  final String? conversationPersistenceKey;
  final TelemetryConfig? telemetry;
  final SupportModeConfig supportMode;
  final AppInteractionMode interactionMode;
  final ActionSafetyConfig actionSafety;
  final bool enableVoice;

  /// Configuration for outbound AI phone calls.
  /// Requires analyticsKey in telemetry config and Pro+ tier.
  final OutboundCallConfig? outboundCalls;

  final void Function(ExecutionResult result)? onResult;
  final Future<void> Function(int stepCount)? onBeforeStep;
  final Future<void> Function(List<AgentStep> history)? onAfterStep;
  final void Function(String status)? onStatusUpdate;

  final Color? accentColor;
  final AgentChatBarTheme? theme;
  final RichUiTheme? richUiTheme;
  final Map<String, BlockActionHandler> blockActionHandlers;
  final bool showChatBar;

  final List<GlobalKey>? interactiveBlacklist;
  final List<GlobalKey>? interactiveWhitelist;
  final Future<String> Function(String content)? transformScreenContent;
  final bool enableUiControl;

  final Widget child;

  const AIAgent({
    super.key,
    this.apiKey,
    this.provider,
    this.proxyUrl,
    this.proxyHeaders,
    this.voiceProxyUrl,
    this.voiceProxyHeaders,
    this.model,
    this.maxSteps = 15,
    this.instructions,
    this.router,
    this.routerAdapter,
    this.navigatorKey,
    this.language = 'en',
    this.screenMap,
    this.maxTokenBudget,
    this.maxCostUsd,
    this.debug = false,
    this.consent,
    this.conversationPersistenceKey,
    this.telemetry,
    this.supportMode = const SupportModeConfig(),
    this.interactionMode = AppInteractionMode.copilot,
    this.actionSafety = const ActionSafetyConfig(),
    this.enableVoice = false,
    this.outboundCalls,
    this.onResult,
    this.onBeforeStep,
    this.onAfterStep,
    this.onStatusUpdate,
    this.accentColor,
    this.theme,
    this.richUiTheme,
    this.blockActionHandlers = const {},
    this.showChatBar = true,
    this.interactiveBlacklist,
    this.interactiveWhitelist,
    this.transformScreenContent,
    this.enableUiControl = true,
    required this.child,
  });

  @override
  State<AIAgent> createState() => _AIAgentState();
}

class _AIAgentState extends State<AIAgent> {
  late AgentRuntime _runtime;
  late AIAgentController _controller;

  final GlobalKey _rootKey = GlobalKey();
  final OverlayPortalController _shellOverlayController =
      OverlayPortalController();
  final TicketStore _ticketStore = const TicketStore();
  final TextEditingController _supportComposer = TextEditingController();

  bool _isRunning = false;
  String _statusText = '';
  ExecutionResult? _lastResult;
  bool _showCSAT = false;
  final DateTime _conversationStart = DateTime.now();
  List<AiMessage> _messages = const <AiMessage>[];
  List<ConversationSummary> _conversations = const <ConversationSummary>[];
  List<AiMessage> _supportMessages = const <AiMessage>[];
  bool _isLoadingConversationHistory = false;
  String? _activeConversationId;
  int _lastSavedMessageCount = 0;
  String? _conversationDeviceId;

  bool _hasConsented = false;
  bool _isConsentLoading = true;
  bool _showConsentDialog = false;
  String? _pendingInstruction;
  InteractionMode? _pendingModeAfterConsent;

  // Approval workflow state
  bool _showApprovalDialog = false;
  AskUserRequest? _pendingApprovalRequest;
  Completer<String>? _approvalCompleter;
  AskUserRequest? _pendingAskUserRequest;
  Completer<String>? _askUserCompleter;

  InteractionMode _mode = InteractionMode.text;
  SupportTicket? _activeTicket;
  List<SupportTicket> _tickets = const <SupportTicket>[];
  bool _isLiveAgentTyping = false;

  VoiceService? _voiceService;
  AudioInputService? _audioInputService;
  AudioOutputService? _audioOutputService;
  Timer? _screenSyncTimer;
  bool _isVoiceConnected = false;
  String? _proxySessionToken;
  bool _isMicMuted = false;
  bool _isSpeakerMuted = false;
  bool _isAiSpeaking = false;
  String _lastVoiceContext = '';
  bool _voiceUserHasSpoken = false;
  bool _voiceToolLocked = false;
  bool _voiceInputPausedForPlayback = false;

  EscalationSocket? _escalationSocket;

  // Telemetry service for analytics
  TelemetryService? _telemetryService;
  void Function()? _disposeDataRegistryListener;
  bool _pendingRuntimeRefresh = false;

  bool get _isAwaitingFreeformAskUser =>
      _pendingAskUserRequest?.kind == AskUserKind.freeform &&
      _askUserCompleter != null &&
      !_askUserCompleter!.isCompleted;

  String get _providerName {
    if (widget.provider != null) return 'custom provider';
    final effectiveProvider = widget.proxyUrl != null
        ? 'hosted proxy'
        : (widget.model?.toLowerCase().contains('gpt') == true
              ? 'OpenAI'
              : 'Google Gemini');
    return effectiveProvider;
  }

  AIConsentConfig get _consentConfig =>
      widget.consent ?? const AIConsentConfig();
  bool get _consentRequired => _consentConfig.required;
  String? get _analyticsKey {
    final key = widget.telemetry?.analyticsKey?.trim();
    if (key == null || key.isEmpty) return null;
    return key;
  }

  List<InteractionMode> get _availableModes {
    final modes = <InteractionMode>[InteractionMode.text];
    if (widget.enableVoice) modes.add(InteractionMode.voice);
    if (widget.supportMode.enabled) modes.add(InteractionMode.human);
    return modes;
  }

  FlutterRouterAdapter? get _effectiveRouterAdapter {
    if (widget.routerAdapter != null) return widget.routerAdapter;
    if (widget.router != null) return GoRouterAdapter(router: widget.router);
    return null;
  }

  @override
  void initState() {
    super.initState();
    registerBuiltInBlocks();
    _disposeDataRegistryListener = dataRegistry.onChange(
      _handleDataRegistryChange,
    );
    _initTelemetry();
    _initRuntime();
    _initProxySession();
    _validateScreenMapRoutes();
    _updateController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _shellOverlayController.show();
      }
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    // Track session end
    MobileAI.track('session_end');
    _telemetryService?.flush();
    proxy_session.clearSession();

    _screenSyncTimer?.cancel();
    unawaited(_audioInputService?.dispose());
    unawaited(_audioOutputService?.cleanup());
    unawaited(_voiceService?.disconnect());
    _telemetryService?.dispose();
    _escalationSocket?.disconnect();
    _supportComposer.dispose();
    _disposeDataRegistryListener?.call();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadConsentState();
    await _startFreshConversationIfNeeded();
    await _loadConversationHistoryIfNeeded();
    await _restoreSupportIfNeeded();
  }

  static const String _defaultMobileAIBase = 'https://mobileai.cloud';
  static const String _hostedTextProxyPath = '/api/v1/hosted-proxy/text';

  String? get _resolvedProxyUrl {
    if (widget.proxyUrl != null) return widget.proxyUrl;
    if (_analyticsKey != null) return '$_defaultMobileAIBase$_hostedTextProxyPath';
    return null;
  }

  Map<String, String> get _effectiveProxyHeaders {
    final analyticsKey = _analyticsKey;
    if (analyticsKey == null) return widget.proxyHeaders ?? const {};

    final authToken = _proxySessionToken ?? analyticsKey;
    final deviceId = getDeviceId();
    final headers = Map<String, String>.from(widget.proxyHeaders ?? {});

    final hasAuth = headers.keys.any((k) => k.toLowerCase() == 'authorization');
    if (!hasAuth) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    if (deviceId != null) {
      headers['X-MobileAI-Device-Id'] = deviceId;
    }
    return headers;
  }

  void _initProxySession() {
    final analyticsKey = _analyticsKey;
    if (analyticsKey == null) return;

    final baseUrl = widget.telemetry?.baseUrl;
    proxy_session
        .getSessionToken(analyticsKey, baseUrl: baseUrl)
        .then((token) {
      if (!mounted) return;
      setState(() => _proxySessionToken = token);
      _initRuntime();
      _updateController();
    }).catchError((Object err) {
      Logger.warn('Proxy session exchange failed: $err');
    });
  }

  void _initTelemetry() {
    if (widget.telemetry == null ||
        !widget.telemetry!.enabled ||
        widget.telemetry!.analyticsKey == null ||
        widget.telemetry!.analyticsKey!.isEmpty) {
      return;
    }

    _telemetryService = TelemetryService(
      config: widget.telemetry!,
      sessionId: widget.telemetry!.sessionId,
    );

    // Set the service for static MobileAI access
    MobileAI.setService(_telemetryService);

    // Start the service
    unawaited(_telemetryService!.start());

    // Track session start
    _telemetryService!.track('session_start');

    Logger.info('Telemetry service initialized');
  }

  void _initRuntime() {
    final effectiveProvider =
        widget.provider ??
        createProvider(
          provider: widget.model?.toLowerCase().contains('gpt') == true
              ? AiProviderName.openai
              : AiProviderName.gemini,
          apiKey: widget.apiKey,
          model: widget.model,
          proxyUrl: _resolvedProxyUrl,
          proxyHeaders: _effectiveProxyHeaders,
        );

    final customTools = _buildRuntimeCustomTools();
    final supportInstructions = widget.supportMode.enabled
        ? buildSupportPrompt(widget.supportMode)
        : null;
    final registeredDataInstructions = _buildRegisteredDataInstructions();
    final mergedInstructions = [
      widget.instructions?.trim(),
      supportInstructions?.trim(),
      registeredDataInstructions?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join('\n\n');

    final config = AgentConfig(
      provider: widget.model?.toLowerCase().contains('gpt') == true
          ? AiProviderName.openai
          : AiProviderName.gemini,
      apiKey: widget.apiKey,
      maxSteps: widget.maxSteps,
      language: widget.language,
      instructions: mergedInstructions.isEmpty ? null : mergedInstructions,
      router: widget.router,
      routerAdapter: _effectiveRouterAdapter,
      navigatorKey: widget.navigatorKey,
      model: widget.model,
      proxyUrl: _resolvedProxyUrl,
      proxyHeaders: _effectiveProxyHeaders,
      screenMap: widget.screenMap,
      maxTokenBudget: widget.maxTokenBudget,
      maxCostUsd: widget.maxCostUsd,
      onBeforeStep: widget.onBeforeStep,
      onAfterStep: widget.onAfterStep,
      onStatusUpdate: _setStatus,
      interactiveBlacklist: widget.interactiveBlacklist,
      interactiveWhitelist: widget.interactiveWhitelist,
      transformScreenContent: widget.transformScreenContent,
      enableUiControl: widget.enableUiControl,
      customTools: customTools,
      interactionMode: widget.interactionMode,
      actionSafety: widget.actionSafety,
      supportStyle: widget.supportMode.supportStyle,
      onAskUser: _handleAskUserRequest,
    );

    _runtime = AgentRuntime(
      provider: effectiveProvider,
      config: config,
      rootKey: _rootKey,
      navKey: widget.navigatorKey,
    );
  }

  void _handleDataRegistryChange() {
    if (!mounted) return;
    if (_isRunning) {
      _pendingRuntimeRefresh = true;
      return;
    }
    _refreshRuntimeFromRegistries();
  }

  void _refreshRuntimeFromRegistries() {
    if (!mounted) return;
    _initRuntime();
    _updateController();
  }

  String? _buildRegisteredDataInstructions() {
    final sources = dataRegistry.getAll();
    if (sources.isEmpty) return null;

    final lines = sources.map((source) {
      final schema = source.schema == null
          ? ''
          : source.schema!.entries
                .map(
                  (entry) =>
                      '${entry.key}: ${entry.value.type} - ${entry.value.description}',
                )
                .join('; ');

      return schema.isEmpty
          ? '- Data source `${source.name}`: ${source.description}'
          : '- Data source `${source.name}`: ${source.description}. Fields: $schema';
    });

    return [
      '### MobileAI Registered Data Sources',
      'The app exposes live data sources you can query with `query_data(source, query)`.',
      'Use them for recommendations, catalog lookup, live pricing, inventory, order status, or any structured data that is better fetched directly than inferred from the current screen.',
      ...lines,
    ].join('\n');
  }

  Map<String, ToolDefinition> _buildRuntimeCustomTools() {
    final tools = <String, ToolDefinition>{};

    if (widget.supportMode.enabled && widget.supportMode.escalation != null) {
      final currentScreen = _runtime.getScreenContext().screenName;
      tools['escalate_to_human'] = createEscalateTool(
        config: widget.supportMode.escalation!,
        getContext: () => {
          'screen': currentScreen,
          'timestamp': DateTime.now().toIso8601String(),
        },
        onEscalationStarted: (ticketId) {
          _openSupportTicket(
            SupportTicket(
              id: ticketId,
              reason: 'Escalated to human support',
              screen: currentScreen,
              createdAt: DateTime.now().toIso8601String(),
              wsUrl: '',
            ),
          );
        },
      );
    }

    // Outbound AI calls — requires analyticsKey and enabled config
    final callConfig = widget.outboundCalls;
    final analyticsKey = _analyticsKey;
    if (analyticsKey != null &&
        analyticsKey.isNotEmpty &&
        (callConfig == null || callConfig.enabled)) {
      tools['start_ai_call'] = createOutboundCallTool(
        OutboundCallToolDeps(
          analyticsKey: analyticsKey,
          config: callConfig,
          getCurrentScreen: () => _runtime.getScreenContext().screenName,
          getHistory: () {
            return _messages
                .where((m) => m.role == 'user' || m.role == 'assistant')
                .take(20)
                .map((m) => {'role': m.role, 'content': m.previewText})
                .toList();
          },
          onStatusUpdate: (status) {
            if (mounted) {
              setState(() => _statusText = status);
            }
          },
        ),
      );
    }

    return tools;
  }

  Future<void> _loadConsentState() async {
    if (!_consentRequired) {
      if (!mounted) return;
      setState(() {
        _hasConsented = true;
        _isConsentLoading = false;
      });
      return;
    }

    final hasConsent = await AIConsentController.hasConsent();
    if (!mounted) return;
    setState(() {
      _hasConsented = hasConsent;
      _isConsentLoading = false;
    });
  }

  Future<void> _startFreshConversationIfNeeded() async {
    final key = widget.conversationPersistenceKey;
    if (key == null || key.trim().isEmpty) return;
    await ConversationService.saveDraft(
      key: key,
      draft: const ConversationDraft(),
    );
    if (!mounted) return;
    setState(() {
      _messages = const <AiMessage>[];
      _activeConversationId = null;
      _lastSavedMessageCount = 0;
      _lastResult = null;
    });
    _updateController();
  }

  Future<void> _persistConversationIfNeeded() async {
    final key = widget.conversationPersistenceKey;
    if (key == null || key.trim().isEmpty) return;
    await ConversationService.saveDraft(
      key: key,
      draft: ConversationDraft(
        activeConversationId: _activeConversationId,
        messages: _messages,
      ),
    );
  }

  Future<void> _loadConversationHistoryIfNeeded() async {
    final analyticsKey = _analyticsKey;
    if (analyticsKey == null) {
      if (!mounted) return;
      setState(() {
        _conversations = const <ConversationSummary>[];
        _isLoadingConversationHistory = false;
      });
      _updateController();
      return;
    }

    if (mounted) {
      setState(() => _isLoadingConversationHistory = true);
      _updateController();
    }

    try {
      _conversationDeviceId ??= await ConversationService.getOrCreateDeviceId();
      final list = await ConversationService.fetchConversations(
        analyticsKey: analyticsKey,
        userId: widget.telemetry?.userId,
        deviceId: _conversationDeviceId,
        baseUrl: widget.telemetry?.baseUrl,
        headers: widget.telemetry?.headers,
      );

      if (!mounted) return;
      setState(() {
        _conversations = list;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingConversationHistory = false);
        _updateController();
      }
    }
  }

  Future<void> _restoreSupportIfNeeded() async {
    if (!widget.supportMode.enabled) return;

    final savedTickets = await _ticketStore.loadTickets();
    final restoredTicket = await widget.supportMode.onRestoreTicket?.call();
    final effectiveTicket = restoredTicket ?? savedTickets.firstOrNull;

    if (!mounted) return;

    setState(() {
      _tickets = restoredTicket != null
          ? <SupportTicket>[
              restoredTicket,
              ...savedTickets.where((ticket) => ticket.id != restoredTicket.id),
            ]
          : savedTickets;
      _activeTicket = effectiveTicket;
    });

    if (effectiveTicket != null) {
      await _restoreSupportTranscript(effectiveTicket);
      _connectSupportSocket(effectiveTicket);
    }
  }

  Future<void> _restoreSupportTranscript(SupportTicket ticket) async {
    final restored = await widget.supportMode.onRestoreTranscript?.call(ticket);
    if (!mounted || restored == null || restored.isEmpty) return;
    setState(() {
      _supportMessages = restored
          .map(
            (entry) => AiMessage(
              role: entry.startsWith('[agent]') ? 'assistant' : 'user',
              content: entry.replaceFirst(RegExp(r'^\[(agent|user)\]\s*'), ''),
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _persistSupportTickets() async {
    await _ticketStore.saveTickets(_tickets);
  }

  void _setStatus(String status) {
    if (!mounted) return;
    setState(() {
      _statusText = status;
    });
    widget.onStatusUpdate?.call(status);
    _updateController();
  }

  Future<void> _handleInstructionSend(
    String instruction, [
    List<UserImage>? images,
  ]) async {
    if (_isConsentLoading) return;
    final trimmed = instruction.trim();
    final hasImages = images != null && images.isNotEmpty;
    if (trimmed.isEmpty && !hasImages) return;

    final pendingAskUser = _pendingAskUserRequest;
    final askUserCompleter = _askUserCompleter;

    // When ask_user completer is active AND images present:
    // cancel current execution and start fresh (mirrors RN behavior)
    if (pendingAskUser != null &&
        pendingAskUser.kind == AskUserKind.freeform &&
        askUserCompleter != null &&
        !askUserCompleter.isCompleted) {
      if (hasImages) {
        // Complete with cancel sentinel, then start fresh with images
        askUserCompleter.complete('__CANCELLED__');
        setState(() {
          _pendingAskUserRequest = null;
          _statusText = '';
        });
        await _runtime.cancelAndWait();
        setState(() => _isRunning = false);
        await _runInstruction(
          trimmed.isEmpty ? 'Describe these images' : trimmed,
          userImages: images,
        );
        return;
      }
      setState(() {
        _messages = <AiMessage>[
          ..._messages,
          AiMessage(role: 'user', content: trimmed, previewText: trimmed),
        ];
        _pendingAskUserRequest = null;
        _statusText = '';
      });
      _updateController();
      unawaited(_persistConversationIfNeeded());
      askUserCompleter.complete(trimmed);
      return;
    }

    // When running AND images present: cancel and restart (mirrors RN)
    if (_isRunning && hasImages) {
      await _runtime.cancelAndWait();
      setState(() => _isRunning = false);
      await _runInstruction(
        trimmed.isEmpty ? 'Describe these images' : trimmed,
        userImages: images,
      );
      return;
    }

    if (_isRunning) return;

    if (_consentRequired && !_hasConsented) {
      final alreadyQueued =
          _messages.isNotEmpty &&
          _messages.last.role == 'user' &&
          _messages.last.previewText.trim() == trimmed;
      setState(() {
        _pendingInstruction = trimmed;
        _showConsentDialog = true;
        if (!alreadyQueued) {
          _messages = <AiMessage>[
            ..._messages,
            AiMessage(role: 'user', content: trimmed, previewText: trimmed),
          ];
        }
      });
      _updateController();
      unawaited(_persistConversationIfNeeded());
      return;
    }

    await _runInstruction(trimmed, userImages: images);
  }

  Future<void> _runInstruction(
    String instruction, {
    bool appendUserMessage = true,
    List<UserImage>? userImages,
  }) async {
    if (_isRunning) return;
    final chatHistory = _buildRuntimeChatHistory(instruction, _messages);

    // Build user message content with image nodes if images are present
    final Object userContent;
    if (userImages != null && userImages.isNotEmpty) {
      final nodes = <AiRichNode>[
        if (instruction.trim().isNotEmpty) AiTextNode(instruction),
        for (final img in userImages)
          AiImageNode(base64: img.base64, mimeType: img.mimeType),
      ];
      userContent = nodes;
    } else {
      userContent = instruction;
    }

    setState(() {
      _isRunning = true;
      _statusText = 'Starting...';
      _lastResult = null;
      if (appendUserMessage) {
        _messages = <AiMessage>[
          ..._messages,
          AiMessage(
            role: 'user',
            content: userContent,
            previewText: instruction.isNotEmpty
                ? instruction
                : '[${userImages?.length ?? 0} image(s)]',
          ),
        ];
      }
    });
    _updateController();
    unawaited(_persistConversationIfNeeded());
    MobileAI.agentRequest(
      instruction: instruction,
      screen: _runtime.getScreenContext().screenName,
    );

    try {
      final result = await _runtime.execute(
        instruction,
        chatHistory: chatHistory.isEmpty ? null : chatHistory,
        userImages: userImages,
      );
      if (!mounted) return;
      final assistantMessage = AiMessage(
        role: 'assistant',
        content: result.reply ?? result.message,
        previewText: result.previewText,
      );
      setState(() {
        _lastResult = result;
        _messages = <AiMessage>[..._messages, assistantMessage];
      });
      _updateController();
      widget.onResult?.call(result);
      unawaited(
        _syncConversationHistoryIfNeeded(assistantMessage: assistantMessage),
      );
      MobileAI.agentComplete(
        success: result.success,
        steps: result.steps.length,
        message: result.message,
      );

      // Trigger CSAT survey after successful resolution
      if (result.success &&
          widget.supportMode.enabled &&
          (widget.supportMode.csat?.enabled ?? true)) {
        final delay = widget.supportMode.csat?.showAfterIdleSeconds ?? 10;
        Future.delayed(Duration(seconds: delay), () {
          if (mounted) setState(() => _showCSAT = true);
        });
      }

      // Track error if execution failed
      if (!result.success) {
        MobileAI.errorScreen(
          errorMessage: result.message,
          errorCode: 'agent_failed',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _statusText = '';
        });
        _updateController();
        if (_pendingRuntimeRefresh) {
          _pendingRuntimeRefresh = false;
          _refreshRuntimeFromRegistries();
        }
      }
    }
  }

  List<Map<String, String>> _buildRuntimeChatHistory(
    String currentInstruction,
    List<AiMessage> sourceMessages,
  ) {
    final normalizedInstruction = currentInstruction.trim();
    final history = List<AiMessage>.from(sourceMessages);
    if (history.isNotEmpty &&
        history.last.role == 'user' &&
        history.last.previewText.trim() == normalizedInstruction) {
      history.removeLast();
    }

    final recent = history
        .where((message) => message.previewText.trim().isNotEmpty)
        .toList(growable: false);
    if (recent.isEmpty) return const <Map<String, String>>[];

    final start = math.max(0, recent.length - 8);
    return recent
        .sublist(start)
        .map(
          (message) => <String, String>{
            'role': message.role,
            'content': message.previewText.trim(),
          },
        )
        .toList(growable: false);
  }

  Future<void> _acceptConsent() async {
    await AIConsentController.grant(persist: _consentConfig.persist);
    _consentConfig.onConsent?.call();

    final pendingInstruction = _pendingInstruction;
    final pendingMode = _pendingModeAfterConsent;

    if (!mounted) return;

    setState(() {
      _hasConsented = true;
      _showConsentDialog = false;
      _pendingInstruction = null;
      _pendingModeAfterConsent = null;
    });
    MobileAI.track(
      'ai_consent_granted',
      properties: <String, Object?>{'provider': _providerName},
    );

    if (pendingInstruction != null) {
      await _runInstruction(pendingInstruction, appendUserMessage: false);
    }
    if (pendingMode != null) {
      await _changeMode(pendingMode);
    }
  }

  void _declineConsent() {
    _consentConfig.onDecline?.call();
    if (!mounted) return;
    setState(() {
      _showConsentDialog = false;
      _pendingInstruction = null;
      _pendingModeAfterConsent = null;
    });
    MobileAI.track(
      'ai_consent_declined',
      properties: <String, Object?>{'provider': _providerName},
    );
  }

  // ── Approval Workflow ────────────────────────────────────────────────

  Future<String> _handleAskUserRequest(AskUserRequest request) async {
    if (request.kind == AskUserKind.approval) {
      _approvalCompleter = Completer<String>();
      if (!mounted) {
        _approvalCompleter!.complete('Action denied: widget not mounted');
        return _approvalCompleter!.future;
      }

      setState(() {
        _pendingApprovalRequest = request;
        _showApprovalDialog = true;
        _statusText = 'Waiting for your approval...';
      });
      widget.onStatusUpdate?.call('Waiting for your approval...');

      final response = await _approvalCompleter!.future;

      if (mounted) {
        setState(() {
          _showApprovalDialog = false;
          _pendingApprovalRequest = null;
          _statusText = '';
        });
      }
      widget.onStatusUpdate?.call('');
      _approvalCompleter = null;
      return response;
    }

    _askUserCompleter = Completer<String>();
    if (!mounted) {
      _askUserCompleter!.complete('');
      return _askUserCompleter!.future;
    }

    final trimmedQuestion = request.question.trim();
    final alreadyQueued =
        trimmedQuestion.isNotEmpty &&
        _messages.isNotEmpty &&
        _messages.last.role == 'assistant' &&
        _messages.last.previewText.trim() == trimmedQuestion;

    setState(() {
      _pendingAskUserRequest = request;
      _statusText = 'Waiting for your answer...';
      if (!alreadyQueued && trimmedQuestion.isNotEmpty) {
        _messages = <AiMessage>[
          ..._messages,
          AiMessage(
            role: 'assistant',
            content: trimmedQuestion,
            previewText: trimmedQuestion,
          ),
        ];
      }
    });
    _updateController();
    unawaited(_persistConversationIfNeeded());
    widget.onStatusUpdate?.call('Waiting for your answer...');

    final response = await _askUserCompleter!.future;
    if (mounted) {
      setState(() {
        _pendingAskUserRequest = null;
        _statusText = '';
      });
    }
    widget.onStatusUpdate?.call('');
    _askUserCompleter = null;
    return response;
  }

  void _grantApproval() {
    final completer = _approvalCompleter;
    if (completer == null || completer.isCompleted) {
      Logger.warn('Approval grant ignored — no pending approval completer.');
      return;
    }
    if (mounted) {
      setState(() {
        _statusText = 'Working...';
      });
    }
    widget.onStatusUpdate?.call('Working...');
    completer.complete('__APPROVAL_GRANTED__');
    Logger.info(
      'User granted approval for ${_pendingApprovalRequest is ApprovalRequest ? (_pendingApprovalRequest as ApprovalRequest).actionName : 'unknown'}',
    );
    MobileAI.track(
      'action_approved',
      properties: <String, Object?>{
        'action': _pendingApprovalRequest is ApprovalRequest
            ? (_pendingApprovalRequest as ApprovalRequest).actionName
            : 'unknown',
      },
    );
  }

  void _denyApproval() {
    final completer = _approvalCompleter;
    if (completer == null || completer.isCompleted) {
      Logger.warn('Approval denial ignored — no pending approval completer.');
      return;
    }
    completer.complete('__APPROVAL_REJECTED__');
    Logger.info(
      'User denied approval for ${_pendingApprovalRequest is ApprovalRequest ? (_pendingApprovalRequest as ApprovalRequest).actionName : 'unknown'}',
    );
    MobileAI.track(
      'action_denied',
      properties: <String, Object?>{
        'action': _pendingApprovalRequest is ApprovalRequest
            ? (_pendingApprovalRequest as ApprovalRequest).actionName
            : 'unknown',
      },
    );
  }

  void _clearMessages() {
    setState(() {
      _activeConversationId = null;
      _lastSavedMessageCount = 0;
      _messages = const <AiMessage>[];
      _lastResult = null;
    });
    _updateController();
    final key = widget.conversationPersistenceKey;
    if (key != null && key.trim().isNotEmpty) {
      unawaited(ConversationService.clearConversation(key));
    }
  }

  Future<void> _changeMode(InteractionMode newMode) async {
    if (_mode == newMode) return;
    if (_isConsentLoading) return;

    // Track mode change
    MobileAI.track(
      'mode_changed',
      properties: <String, Object?>{'from': _mode.name, 'to': newMode.name},
    );

    if (_consentRequired &&
        !_hasConsented &&
        newMode == InteractionMode.voice) {
      setState(() {
        _pendingModeAfterConsent = newMode;
        _showConsentDialog = true;
      });
      return;
    }

    if (newMode != InteractionMode.voice) {
      await _stopVoiceSession();
    }

    if (!mounted) return;
    setState(() {
      _mode = newMode;
    });

    if (newMode == InteractionMode.voice) {
      await _startVoiceSession();
    }

    if (newMode == InteractionMode.human && _activeTicket == null) {
      await _ensureSupportTicket();
    }
  }

  Future<void> _startVoiceSession() async {
    if (_voiceService?.isConnected == true) return;

    _audioOutputService ??= AudioOutputService(
      config: AudioOutputConfig(
        onError: (error) => Logger.warn('AudioOutputService: $error'),
      ),
    );
    await _audioOutputService!.initialize();

    _audioInputService ??= AudioInputService(
      AudioInputConfig(
        onAudioChunk: (chunk) {
          _voiceService?.sendAudio(chunk);
        },
        onError: (error) => Logger.warn('AudioInputService: $error'),
        onPermissionDenied: () {
          _setStatus('Microphone permission denied');
        },
      ),
    );

    if (_isSpeakerMuted) {
      await _audioOutputService!.mute();
    }
    if (_isMicMuted) {
      await _audioInputService!.mute();
    }

    _voiceService ??= VoiceService(
      VoiceServiceConfig(
        apiKey: widget.apiKey,
        proxyUrl: widget.voiceProxyUrl ?? _resolvedProxyUrl,
        proxyHeaders: widget.voiceProxyHeaders ?? _effectiveProxyHeaders,
        model: widget.model,
        systemPrompt: buildVoiceSystemPrompt(
          widget.language,
          hasKnowledge: false,
          supportStyle: widget.supportMode.supportStyle,
          userInstructions: widget.instructions,
        ),
        tools: _runtime.getTools(),
        language: widget.language,
      ),
    );

    await _voiceService!.connect(
      VoiceServiceCallbacks(
        onAudioResponse: (audio) async {
          await _pauseVoiceInputForPlayback();
          if (mounted) {
            setState(() => _isAiSpeaking = true);
          }
          await _audioOutputService?.enqueue(audio);
        },
        onStatusChange: (status) async {
          if (!mounted) return;
          setState(() {
            _isVoiceConnected = status == 'connected';
          });
          _setStatus(switch (status) {
            'connecting' => 'Connecting voice…',
            'connected' => 'Voice connected',
            'error' => 'Voice unavailable',
            _ => '',
          });

          if (status == 'connected') {
            Logger.info('Voice connected — starting audio input.');
            final started = await _audioInputService?.start() ?? false;
            Logger.info('Voice audio input start result: $started.');
            if (!mounted) return;
            if (!started) {
              _setStatus('Microphone unavailable');
            } else {
              // Track voice session started
              MobileAI.track('voice_session_started');
            }
            _startVoiceScreenSync();
          }

          if (status == 'disconnected' &&
              _mode == InteractionMode.voice &&
              _voiceService != null &&
              !_voiceService!.intentionalDisconnect) {
            await _audioInputService?.stop();
            await _audioOutputService?.stop();
            if (mounted) {
              setState(() => _isAiSpeaking = false);
            }
            Logger.warn(
              'VoiceService disconnected unexpectedly — reconnecting in 2s.',
            );
            Future<void>.delayed(const Duration(seconds: 2), () {
              if (!mounted ||
                  _mode != InteractionMode.voice ||
                  _voiceService == null ||
                  _voiceService!.intentionalDisconnect ||
                  _voiceService!.lastCallbacks == null) {
                return;
              }
              unawaited(_voiceService!.connect(_voiceService!.lastCallbacks!));
            });
          }
        },
        onTranscript: (text, isFinal, role) {
          Logger.info('Voice transcript [$role] (final=$isFinal): "$text"');
          if (role == 'user') {
            if (_isAiSpeaking || _voiceInputPausedForPlayback) {
              Logger.warn(
                'Ignored user transcript while model playback is active: "$text"',
              );
              return;
            }
            if (_isUsableVoiceUserTranscript(text)) {
              _voiceUserHasSpoken = true;
              _runtime.resetAppActionApproval('new voice command');
            } else {
              Logger.warn(
                'Ignored unusable voice transcript for action gating: "$text"',
              );
            }
          }
        },
        onToolCall: (toolCall) async {
          await _handleVoiceToolCall(toolCall);
        },
        onToolCallCancellation: (ids) {
          Logger.info('Voice tool cancellation: ${ids.join(', ')}');
        },
        onTurnComplete: () {
          if (!mounted) return;
          setState(() {
            _isAiSpeaking = false;
          });
          _voiceUserHasSpoken = false;
          unawaited(_resumeVoiceInputAfterPlayback());
        },
        onSetupComplete: () {
          _sendInitialVoiceContext();
        },
        onError: (error) {
          Logger.error('VoiceService: $error');
          _setStatus(error);
        },
      ),
    );
  }

  Future<void> _stopVoiceSession() async {
    _screenSyncTimer?.cancel();
    _screenSyncTimer = null;
    _lastVoiceContext = '';
    _voiceUserHasSpoken = false;
    _voiceToolLocked = false;
    _voiceInputPausedForPlayback = false;
    await _audioInputService?.stop();
    await _audioOutputService?.stop();
    await _voiceService?.disconnect();

    if (!mounted) return;
    setState(() {
      _isVoiceConnected = false;
      _isAiSpeaking = false;
    });
  }

  void _sendInitialVoiceContext() {
    _voiceUserHasSpoken = false;
    final rawContext = _buildVoiceRawScreenContext();
    _lastVoiceContext = rawContext;
    unawaited(
      _voiceService?.sendScreenContext(
        _formatVoiceScreenContext(rawContext, initial: true),
      ),
    );
  }

  String _buildVoiceRawScreenContext() {
    final screen = _runtime.getScreenContext();
    return _runtime.buildScreenStateText(
      screenName: screen.screenName,
      availableScreens: screen.availableScreens,
      elementsText: screen.elementsText,
      elements: screen.elements,
      includeTags: false,
    );
  }

  String _formatVoiceScreenContext(String rawContext, {required bool initial}) {
    final preface = initial
        ? '[SYSTEM CONTEXT — THIS IS NOT A USER REQUEST. DO NOT RESPOND. DO NOT NAVIGATE. DO NOT CALL ANY TOOLS. DO NOT SPEAK. Just silently read and memorize this screen layout. You will use it when the user speaks their first voice command.]'
        : '[SCREEN UPDATE — The UI has changed. Here is the current screen layout. This is not a user request — do not act unless the user asks.]';
    return '$preface\n\n$rawContext';
  }

  bool _isUsableVoiceUserTranscript(String text) {
    final normalized = text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length < 2) return false;

    final language = widget.language.trim().toLowerCase();
    if (language == 'ar') {
      return RegExp(r'[\p{L}]', unicode: true).hasMatch(normalized);
    }

    // English sessions should not unlock app actions from simulator/audio
    // artifacts like punctuation, CJK, Cyrillic, or Arabic fragments.
    return RegExp(r'[A-Za-z]').hasMatch(normalized);
  }

  /// Build a summary of the conversation for escalation.
  String _buildConversationSummary() {
    if (_messages.isEmpty) return 'No prior conversation';
    final recentMessages = _messages
        .take(5)
        .map((m) => '${m.role}: ${m.previewText}')
        .join('\n');
    return 'Conversation summary:\n$recentMessages';
  }

  String _buildConversationTitle(List<AiMessage> messages) {
    for (final message in messages) {
      if (message.role != 'user') continue;
      final preview = message.previewText.trim();
      if (preview.isEmpty) continue;
      return preview.length <= 80 ? preview : '${preview.substring(0, 79)}…';
    }
    return 'New conversation';
  }

  Future<void> _syncConversationHistoryIfNeeded({
    required AiMessage assistantMessage,
  }) async {
    final analyticsKey = _analyticsKey;
    if (analyticsKey == null) {
      await _persistConversationIfNeeded();
      return;
    }

    final currentMessages = List<AiMessage>.from(_messages);
    if (currentMessages.isEmpty) return;

    final newMessages = currentMessages
        .skip(_lastSavedMessageCount)
        .toList(growable: false);
    if (newMessages.isEmpty) {
      await _persistConversationIfNeeded();
      return;
    }

    _conversationDeviceId ??= await ConversationService.getOrCreateDeviceId();

    if (_activeConversationId == null) {
      final conversationId = await ConversationService.startConversation(
        analyticsKey: analyticsKey,
        userId: widget.telemetry?.userId,
        deviceId: _conversationDeviceId,
        baseUrl: widget.telemetry?.baseUrl,
        headers: widget.telemetry?.headers,
        messages: newMessages,
        title: _buildConversationTitle(newMessages),
      );
      if (conversationId == null) {
        await _persistConversationIfNeeded();
        return;
      }

      if (!mounted) return;
      setState(() {
        _activeConversationId = conversationId;
        _lastSavedMessageCount = currentMessages.length;
        _conversations = <ConversationSummary>[
          ConversationSummary(
            id: conversationId,
            title: _buildConversationTitle(currentMessages),
            preview: assistantMessage.previewText,
            previewRole: assistantMessage.role,
            messageCount: currentMessages.length,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          ..._conversations.where(
            (conversation) => conversation.id != conversationId,
          ),
        ];
      });
      _updateController();
      await _persistConversationIfNeeded();
      return;
    }

    await ConversationService.appendMessages(
      conversationId: _activeConversationId!,
      analyticsKey: analyticsKey,
      baseUrl: widget.telemetry?.baseUrl,
      headers: widget.telemetry?.headers,
      messages: newMessages,
    );

    if (!mounted) return;
    final existing = _conversations.firstWhere(
      (conversation) => conversation.id == _activeConversationId,
      orElse: () => ConversationSummary(
        id: _activeConversationId!,
        title: _buildConversationTitle(currentMessages),
        preview: '',
        messageCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    setState(() {
      _lastSavedMessageCount = currentMessages.length;
      _conversations = <ConversationSummary>[
        ConversationSummary(
          id: existing.id,
          title: existing.title,
          preview: assistantMessage.previewText,
          previewRole: assistantMessage.role,
          messageCount: existing.messageCount + newMessages.length,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        ..._conversations.where(
          (conversation) => conversation.id != _activeConversationId,
        ),
      ];
    });
    _updateController();
    await _persistConversationIfNeeded();
  }

  Future<void> _handleConversationSelect(String conversationId) async {
    final analyticsKey = _analyticsKey;
    if (analyticsKey == null || conversationId.isEmpty) return;

    final messages = await ConversationService.fetchConversation(
      conversationId: conversationId,
      analyticsKey: analyticsKey,
      baseUrl: widget.telemetry?.baseUrl,
      headers: widget.telemetry?.headers,
    );
    if (!mounted || messages == null) return;

    setState(() {
      _activeConversationId = conversationId;
      _lastSavedMessageCount = messages.length;
      _messages = messages;
      _lastResult = null;
    });
    _updateController();
    await _persistConversationIfNeeded();
  }

  void _startNewConversation() {
    setState(() {
      _activeConversationId = null;
      _lastSavedMessageCount = 0;
      _messages = const <AiMessage>[];
      _lastResult = null;
    });
    _updateController();
    final key = widget.conversationPersistenceKey;
    if (key != null && key.trim().isNotEmpty) {
      unawaited(
        ConversationService.saveDraft(
          key: key,
          draft: const ConversationDraft(),
        ),
      );
    }
  }

  void _startVoiceScreenSync() {
    _screenSyncTimer?.cancel();
    _screenSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_voiceService?.isConnected != true) return;
      if (_voiceToolLocked) return;
      final nextContext = _buildVoiceRawScreenContext();
      if (nextContext == _lastVoiceContext) return;

      final previousLength = _lastVoiceContext.length;
      final diff = (nextContext.length - previousLength).abs();
      final diffRatio = previousLength > 0 ? diff / previousLength : 1.0;
      if (diffRatio < 0.05) return;

      _lastVoiceContext = nextContext;
      unawaited(
        _voiceService?.sendScreenContext(
          _formatVoiceScreenContext(nextContext, initial: false),
        ),
      );
    });
  }

  Future<void> _handleVoiceToolCall(VoiceToolCall toolCall) async {
    Logger.info(
      'Voice tool call: ${toolCall.name}(${toolCall.args}) [id=${toolCall.id}]',
    );
    if (!_voiceUserHasSpoken) {
      Logger.warn(
        'Rejected voice tool call ${toolCall.name} — user has not spoken yet.',
      );
      await _voiceService?.sendFunctionResponse(toolCall.name, toolCall.id, <
        String,
        dynamic
      >{
        'result':
            'Action rejected: wait for the user to speak before performing any actions.',
      });
      return;
    }

    await _audioInputService?.stop();

    _setStatus('Executing ${toolCall.name.replaceAll('_', ' ')}…');

    while (_voiceToolLocked) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _voiceToolLocked = true;

    try {
      if (mounted) {
        setState(() => _isRunning = true);
      }
      Logger.info('Executing voice tool ${toolCall.name}...');
      final result = await _runtime.executeTool(toolCall.name, toolCall.args);
      Logger.info('Voice tool result for ${toolCall.name}: $result');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final updatedContext = _buildVoiceRawScreenContext();
      _lastVoiceContext = updatedContext;
      await _voiceService?.sendFunctionResponse(
        toolCall.name,
        toolCall.id,
        <String, dynamic>{
          'result':
              '$result\n\n<updated_screen>\n$updatedContext\n</updated_screen>',
        },
      );
      Logger.info('Voice tool response sent for ${toolCall.name}.');
    } catch (error) {
      Logger.error('Voice tool ${toolCall.name} failed: $error');
      await _voiceService?.sendFunctionResponse(
        toolCall.name,
        toolCall.id,
        <String, dynamic>{'result': 'Tool execution failed: $error'},
      );
    } finally {
      _voiceToolLocked = false;
      if (mounted) {
        setState(() => _isRunning = false);
      }
      if (_voiceService?.isConnected == true &&
          _mode == InteractionMode.voice &&
          !_isMicMuted) {
        final started = await _audioInputService?.start() ?? false;
        if (started) {
          Logger.info(
            'Voice input resumed after tool execution: ${toolCall.name}.',
          );
        } else {
          Logger.warn(
            'Voice input failed to resume after tool execution: ${toolCall.name}.',
          );
          _setStatus('Microphone unavailable');
        }
      }
      _setStatus('');
    }
  }

  Future<void> _pauseVoiceInputForPlayback() async {
    if (_voiceInputPausedForPlayback ||
        _audioInputService?.isRecording != true) {
      return;
    }
    _voiceInputPausedForPlayback = true;
    await _audioInputService?.stop();
    Logger.info('Voice input paused during model playback.');
  }

  Future<void> _resumeVoiceInputAfterPlayback() async {
    if (!_voiceInputPausedForPlayback) return;
    _voiceInputPausedForPlayback = false;
    if (!mounted ||
        _mode != InteractionMode.voice ||
        _voiceService?.isConnected != true ||
        _voiceToolLocked ||
        _isMicMuted) {
      return;
    }

    final started = await _audioInputService?.start() ?? false;
    if (started) {
      Logger.info('Voice input resumed after model playback.');
    } else {
      Logger.warn('Voice input failed to resume after model playback.');
      _setStatus('Microphone unavailable');
    }
  }

  Future<void> _toggleMicMute() async {
    if (_voiceService?.isConnected != true || _audioInputService == null) {
      return;
    }

    final nextMuted = !_isMicMuted;
    if (nextMuted) {
      await _audioInputService!.mute();
      await _voiceService?.notifyAudioStreamEnded();
    } else {
      await _audioInputService!.unmute();
    }

    if (!mounted) return;
    setState(() {
      _isMicMuted = nextMuted;
    });
  }

  Future<void> _toggleSpeakerMute() async {
    if (_audioOutputService == null) return;
    final nextMuted = !_isSpeakerMuted;
    if (nextMuted) {
      await _audioOutputService!.mute();
    } else {
      await _audioOutputService!.unmute();
    }
    if (!mounted) return;
    setState(() {
      _isSpeakerMuted = nextMuted;
    });
  }

  Future<void> _ensureSupportTicket() async {
    if (!widget.supportMode.enabled) return;
    if (_activeTicket != null) {
      _connectSupportSocket(_activeTicket!);
      return;
    }

    final onEscalate = widget.supportMode.escalation?.onEscalate;
    SupportTicket? ticket;
    final currentScreen = _runtime.getScreenContext().screenName;
    final lastMessage = _messages.lastOrNull?.previewText ?? '';

    if (onEscalate != null) {
      final ticketId = await onEscalate(
        EscalationContext(
          conversationSummary: _buildConversationSummary(),
          currentScreen: currentScreen,
          originalQuery: lastMessage,
          stepsBeforeEscalation: 0,
        ),
      );
      ticket = SupportTicket(
        id: ticketId,
        reason: lastMessage.isEmpty ? 'Manual support request' : lastMessage,
        screen: currentScreen,
        createdAt: DateTime.now().toIso8601String(),
        wsUrl: '',
      );
    }

    ticket ??= SupportTicket(
      id: 'support-${DateTime.now().millisecondsSinceEpoch}',
      reason: lastMessage.isEmpty ? 'Support conversation' : lastMessage,
      screen: currentScreen,
      createdAt: DateTime.now().toIso8601String(),
      wsUrl: '',
    );

    _openSupportTicket(ticket);
  }

  void _openSupportTicket(SupportTicket ticket) {
    final greeting = widget.supportMode.greetingMessage?.trim();
    final nextTickets = <SupportTicket>[
      ticket,
      ..._tickets.where((existing) => existing.id != ticket.id),
    ];

    setState(() {
      _mode = InteractionMode.human;
      _activeTicket = ticket;
      _tickets = nextTickets;
      if (_supportMessages.isEmpty && greeting != null && greeting.isNotEmpty) {
        _supportMessages = <AiMessage>[
          AiMessage(
            role: 'assistant',
            content: greeting,
            previewText: greeting,
          ),
        ];
      }
    });
    unawaited(_persistSupportTickets());
    _connectSupportSocket(ticket);

    // Track support ticket opened
    MobileAI.escalation(reason: ticket.reason, ticketId: ticket.id);
  }

  void _connectSupportSocket(SupportTicket ticket) {
    final builder = widget.supportMode.socketUrlBuilder;
    final socketUrl = builder?.call(ticket);
    if (socketUrl == null || socketUrl.trim().isEmpty) return;

    _escalationSocket?.disconnect();
    _escalationSocket = EscalationSocket(
      onReply: (reply, ticketId) {
        if (!mounted) return;
        setState(() {
          _supportMessages = <AiMessage>[
            ..._supportMessages,
            AiMessage(role: 'assistant', content: reply, previewText: reply),
          ];
          _isLiveAgentTyping = false;
        });
      },
      onTypingChange: (typing) {
        if (!mounted) return;
        setState(() => _isLiveAgentTyping = typing);
      },
      onTicketClosed: (ticketId) {
        if (!mounted) return;
        setState(() {
          if (_activeTicket?.id == ticketId) {
            _activeTicket = _activeTicket!.copyWith(status: 'closed');
          }
        });
      },
    );
    _escalationSocket!.connect(socketUrl);
  }

  Future<void> _sendSupportMessage(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final ticket = _activeTicket;
    if (ticket == null) return;

    setState(() {
      _supportMessages = <AiMessage>[
        ..._supportMessages,
        AiMessage(role: 'user', content: trimmed, previewText: trimmed),
      ];
      _isLiveAgentTyping = true;
    });

    if (_escalationSocket?.isConnected == true) {
      _escalationSocket?.sendText(trimmed);
    }

    await widget.supportMode.onSendHumanMessage?.call(ticket, trimmed);
    if (!mounted) return;
    setState(() => _isLiveAgentTyping = false);

    // Track support message sent
    MobileAI.track(
      'support_message_sent',
      properties: <String, Object?>{
        'ticket_id': ticket.id,
        'message_length': trimmed.length,
      },
    );
  }

  void _updateController() {
    _controller = AIAgentController(
      runtime: _runtime,
      isRunning: _isRunning,
      isAwaitingUserResponse: _isAwaitingFreeformAskUser,
      isLoadingHistory: _isLoadingConversationHistory,
      lastResult: _lastResult,
      status: _statusText,
      messages: _messages,
      conversations: _conversations,
      send: _handleInstructionSend,
      openConversation: _handleConversationSelect,
      cancel: () async {
        _runtime.cancel();
        await _stopVoiceSession();
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _statusText = '';
        });
        _updateController();
      },
      clearMessages: _clearMessages,
      startNewConversation: _startNewConversation,
    );
  }

  @override
  void didUpdateWidget(covariant AIAgent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final runtimeChanged =
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.provider != widget.provider ||
        oldWidget.maxSteps != widget.maxSteps ||
        oldWidget.instructions != widget.instructions ||
        oldWidget.router != widget.router ||
        oldWidget.routerAdapter != widget.routerAdapter ||
        oldWidget.navigatorKey != widget.navigatorKey ||
        oldWidget.screenMap != widget.screenMap ||
        oldWidget.interactionMode != widget.interactionMode ||
        oldWidget.actionSafety != widget.actionSafety ||
        oldWidget.supportMode != widget.supportMode;
    if (runtimeChanged) {
      _runtime.dispose();
      _initRuntime();
      _validateScreenMapRoutes();
      _updateController();
    }

    final historyConfigChanged =
        oldWidget.telemetry?.analyticsKey != widget.telemetry?.analyticsKey ||
        oldWidget.telemetry?.userId != widget.telemetry?.userId ||
        oldWidget.telemetry?.baseUrl != widget.telemetry?.baseUrl;
    if (historyConfigChanged) {
      unawaited(_loadConversationHistoryIfNeeded());
    }
  }

  void _validateScreenMapRoutes() {
    final screenMap = widget.screenMap;
    final routerAdapter = _effectiveRouterAdapter;
    if (screenMap == null ||
        routerAdapter == null ||
        routerAdapter is! RouteCatalogProvider) {
      return;
    }

    final knownRoutes = (routerAdapter as RouteCatalogProvider)
        .getKnownRoutes()
        .toSet();
    final mappedRoutes = screenMap.screens.keys.toSet();
    final missingRoutes = knownRoutes.difference(mappedRoutes);
    final extraRoutes = mappedRoutes.difference(knownRoutes);

    if (missingRoutes.isNotEmpty || extraRoutes.isNotEmpty) {
      Logger.warn(
        'ScreenMap mismatch detected. Missing routes: ${missingRoutes.join(', ')}. '
        'Extra routes: ${extraRoutes.join(', ')}.',
      );
    }
  }

  AgentChatBarTheme _resolveTheme() {
    if (widget.theme != null) return widget.theme!;
    if (widget.accentColor != null) {
      return AgentChatBarTheme(primaryColor: widget.accentColor);
    }
    return const AgentChatBarTheme();
  }

  @override
  Widget build(BuildContext context) {
    return AIAgentScope(
      controller: _controller,
      child: ActionBridge(
        controller: ActionBridgeController(widget.blockActionHandlers),
        child: RichUiThemeScope(
          theme: widget.richUiTheme ?? RichUiTheme.defaults(),
          child: Localizations(
            locale: const Locale('en'),
            delegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Material(
                type: MaterialType.transparency,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) {
                        return OverlayPortal(
                          controller: _shellOverlayController,
                          overlayChildBuilder: (context) {
                            return ExcludeSemantics(
                              child: Stack(
                                children: [
                                  if (widget.showChatBar &&
                                      _mode != InteractionMode.human)
                                    AgentChatBar(
                                      onSend: _controller.send,
                                      isThinking: _isRunning,
                                      awaitingUserResponse:
                                          _isAwaitingFreeformAskUser,
                                      lastResult: _lastResult,
                                      messages: _messages,
                                      humanMessages: _supportMessages,
                                      language: widget.language,
                                      onDismiss: () =>
                                          setState(() => _lastResult = null),
                                      onCancel: _controller.cancel,
                                      theme: _resolveTheme(),
                                      conversations: _conversations,
                                      isLoadingHistory:
                                          _isLoadingConversationHistory,
                                      onConversationSelect:
                                          _analyticsKey == null
                                          ? null
                                          : (conversationId) {
                                              unawaited(
                                                _handleConversationSelect(
                                                  conversationId,
                                                ),
                                              );
                                            },
                                      onNewConversation: _analyticsKey == null
                                          ? null
                                          : _startNewConversation,
                                      mode: _mode,
                                      availableModes: _availableModes,
                                      onModeChanged: (mode) =>
                                          unawaited(_changeMode(mode)),
                                      isVoiceConnected: _isVoiceConnected,
                                      isMicMuted: _isMicMuted,
                                      isSpeakerMuted: _isSpeakerMuted,
                                      isAISpeaking: _isAiSpeaking,
                                      onToggleVoiceConnection: () {
                                        if (_isVoiceConnected) {
                                          unawaited(
                                            _changeMode(InteractionMode.text),
                                          );
                                        } else {
                                          unawaited(
                                            _changeMode(InteractionMode.voice),
                                          );
                                        }
                                      },
                                      onToggleMic: _toggleMicMute,
                                      onToggleSpeaker: _toggleSpeakerMute,
                                      activeSupportLabel:
                                          widget.supportMode.agentName,
                                      consentVisible: _showConsentDialog,
                                      consentProviderName: _providerName,
                                      consentConfig: _consentConfig,
                                      onConsentAccept: _acceptConsent,
                                      onConsentDecline: _declineConsent,
                                      approvalVisible: _showApprovalDialog,
                                      approvalRequest: _pendingApprovalRequest,
                                      onApprovalAccept: _grantApproval,
                                      onApprovalDecline: _denyApproval,
                                      afterMessagesContent: _showCSAT && widget.supportMode.csat != null
                                          ? CSATSurvey(config: widget.supportMode.csat!)
                                          : null,
                                    ),
                                  if (_mode == InteractionMode.human)
                                    _buildSupportOverlay(context),
                                  const ActionHighlightOverlay(),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring:
                                          !_isRunning && _statusText.isEmpty,
                                      child: AgentOverlay(
                                        visible:
                                            _isRunning ||
                                            _statusText.isNotEmpty,
                                        statusText: _statusText,
                                        onCancel: _controller.cancel,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: RepaintBoundary(
                            key: _rootKey,
                            child: widget.child,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportOverlay(BuildContext context) {
    final theme = _resolveTheme();

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.backgroundColor ?? const Color(0xF21A1A2E),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.supportMode.agentName ??
                                      'Human support',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _activeTicket == null
                                      ? 'Live support'
                                      : 'Ticket ${_activeTicket!.id}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _mode = InteractionMode.text),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        children: [
                          if (_supportMessages.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                widget.supportMode.greetingMessage ??
                                    'A human support conversation will appear here.',
                                style: const TextStyle(
                                  color: Colors.white,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ..._supportMessages.map((message) {
                            final isUser = message.role == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? (theme.primaryColor ??
                                                const Color(0xFF7B68EE))
                                            .withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  richContentToPlainText(
                                    message.content,
                                  ).trim(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            );
                          }),
                          if (_isLiveAgentTyping)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Text(
                                  'Support agent is typing…',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.supportMode.quickReplies.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          children: widget.supportMode.quickReplies
                              .map((reply) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ActionChip(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    onPressed: () {
                                      final text = reply.message ?? reply.label;
                                      unawaited(_sendSupportMessage(text));
                                    },
                                    label: Text(
                                      reply.icon == null
                                          ? reply.label
                                          : '${reply.icon} ${reply.label}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: CupertinoTextField(
                                controller: _supportComposer,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (value) {
                                  final next = value.trim();
                                  if (next.isEmpty) return;
                                  _supportComposer.clear();
                                  unawaited(_sendSupportMessage(next));
                                },
                                style: const TextStyle(color: Colors.white),
                                placeholder: 'Message support…',
                                placeholderStyle: const TextStyle(
                                  color: Colors.white54,
                                ),
                                decoration: null,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final next = _supportComposer.text.trim();
                              if (next.isEmpty) return;
                              _supportComposer.clear();
                              unawaited(_sendSupportMessage(next));
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                    theme.primaryColor ??
                                    const Color(0xFF7B68EE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@Deprecated('Use AIAgent instead.')
typedef AiAgent = AIAgent;
