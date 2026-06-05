import 'package:flutter/widgets.dart';

import '../core/agent_runtime.dart';
import '../core/types.dart';

class AIAgentController {
  final AgentRuntime runtime;
  final Future<void> Function(String instruction, [List<UserImage>? images]) send;
  final Future<void> Function(String conversationId)? openConversation;
  final VoidCallback cancel;
  final VoidCallback clearMessages;
  final VoidCallback startNewConversation;
  final bool isRunning;
  final bool isAwaitingUserResponse;
  final bool isLoadingHistory;
  final ExecutionResult? lastResult;
  final String status;
  final List<AiMessage> messages;
  final List<ConversationSummary> conversations;

  AIAgentController({
    required this.runtime,
    required this.send,
    this.openConversation,
    required this.cancel,
    required this.clearMessages,
    required this.startNewConversation,
    required this.isRunning,
    this.isAwaitingUserResponse = false,
    this.isLoadingHistory = false,
    this.lastResult,
    this.status = '',
    this.messages = const [],
    this.conversations = const [],
  });
}

class AIAgentScope extends InheritedWidget {
  final AIAgentController controller;

  const AIAgentScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static AIAgentController of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AIAgentScope>();
    assert(result != null, 'No AIAgentScope found in context');
    return result!.controller;
  }

  @override
  bool updateShouldNotify(AIAgentScope oldWidget) {
    return controller.isRunning != oldWidget.controller.isRunning ||
        controller.isAwaitingUserResponse !=
            oldWidget.controller.isAwaitingUserResponse ||
        controller.isLoadingHistory != oldWidget.controller.isLoadingHistory ||
        controller.status != oldWidget.controller.status ||
        controller.messages.length != oldWidget.controller.messages.length ||
        controller.conversations.length !=
            oldWidget.controller.conversations.length ||
        controller.lastResult != oldWidget.controller.lastResult;
  }
}

extension AIAgentContextX on BuildContext {
  AIAgentController get ai => AIAgentScope.of(this);
}

@Deprecated('Use AIAgentController instead.')
typedef AiAgentController = AIAgentController;

@Deprecated('Use AIAgentScope instead.')
typedef AiAgentScope = AIAgentScope;
