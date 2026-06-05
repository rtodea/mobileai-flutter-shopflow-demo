import 'dart:async';

import '../core/types.dart';
import '../services/outbound_call_service.dart';
import '../utils/logger.dart';
import 'outbound_call_watcher.dart';

/// Dependencies for the outbound call tool.
class OutboundCallToolDeps {
  final String analyticsKey;
  final OutboundCallConfig? config;
  final String Function()? getCurrentScreen;
  final List<Map<String, String>> Function()? getHistory;
  final Map<String, dynamic>? userContext;
  final void Function(String status)? onStatusUpdate;

  const OutboundCallToolDeps({
    required this.analyticsKey,
    this.config,
    this.getCurrentScreen,
    this.getHistory,
    this.userContext,
    this.onStatusUpdate,
  });
}

/// Maps failure codes to user-friendly labels.
String _friendlyFailureLabel(String? failureCode) {
  switch (failureCode) {
    case 'no_answer':
      return 'No one answered the phone.';
    case 'busy':
      return 'The line was busy.';
    case 'canceled':
      return 'The call was canceled.';
    case 'callee_hung_up':
      return 'They answered but hung up immediately.';
    case 'exhausted':
      return "Couldn't reach them after multiple attempts.";
    case 'connection_lost':
      return 'Connection was lost during the call.';
    case 'watcher_timeout':
      return 'The call timed out waiting for a response.';
    default:
      return 'The call could not be completed.';
  }
}

String _summarizeRecentHistory(List<Map<String, String>> history) {
  final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
  final lines = recent.map((e) => '${e['role']}: ${e['content']}').join('\n');
  return lines.length > 3000 ? lines.substring(0, 3000) : lines;
}

/// Create the outbound AI call tool definition.
///
/// Follows the same factory pattern as [createEscalateTool].
ToolDefinition createOutboundCallTool(OutboundCallToolDeps deps) {
  final allowedTargetTypes =
      (deps.config?.allowedTargetTypes?.isNotEmpty ?? false)
          ? deps.config!.allowedTargetTypes!
          : [...defaultOutboundCallTargetTypes];

  return ToolDefinition(
    name: 'start_ai_call',
    description:
        'Start an outbound AI phone call from the company-owned MobileAI phone number '
        'to a trusted contact configured in the dashboard. '
        'Use this only after investigating the issue and deciding a real human/vendor/partner '
        'phone call is needed, such as a stuck order, delivery coordination, appointment '
        'confirmation, booking partner follow-up, billing/fraud escalation, or external vendor '
        'status check. Never provide or infer a phone number; pass only targetType and targetId '
        'so MobileAI can look up the trusted contact. This tool requires explicit user approval '
        'before dialing.',
    parameters: {
      'targetType': ToolParam(
        type: 'string',
        description: 'Trusted contact category configured in MobileAI.',
        required: true,
        enumValues: allowedTargetTypes,
      ),
      'targetId': ToolParam(
        type: 'string',
        description: 'Stable app/business ID for the trusted contact. Do not send a phone number.',
        required: true,
      ),
      'reason': ToolParam(
        type: 'string',
        description: 'Brief reason the call is needed.',
        required: true,
      ),
      'callGoal': ToolParam(
        type: 'string',
        description: 'Specific outcome the AI caller should try to get from the external party.',
        required: true,
      ),
      'contextSummary': ToolParam(
        type: 'string',
        description: 'Important context to give the AI caller before dialing.',
        required: true,
      ),
      'urgency': ToolParam(
        type: 'string',
        description: 'Call urgency.',
        required: false,
        enumValues: ['normal', 'urgent'],
      ),
    },
    effect: ToolEffect.support,
    handler: (args) => _executeOutboundCall(args, deps),
  );
}

Future<String> _executeOutboundCall(
  Map<String, dynamic> args,
  OutboundCallToolDeps deps,
) async {
  final targetId = (args['targetId']?.toString() ?? '').trim();

  // Reject raw phone numbers
  if (RegExp(r'^\+?[1-9]\d{7,14}$').hasMatch(targetId)) {
    return '❌ start_ai_call rejected: targetId must be a semantic trusted-contact ID, not a phone number.';
  }

  final contextFromHistory = _summarizeRecentHistory(deps.getHistory?.call() ?? []);

  final result = await startOutboundAiCall(
    analyticsKey: deps.analyticsKey,
    config: deps.config,
    currentScreen: deps.getCurrentScreen?.call(),
    userContext: deps.userContext,
    request: OutboundCallRequest(
      targetType: (args['targetType']?.toString() ?? '').trim(),
      targetId: targetId,
      reason: (args['reason']?.toString() ?? '').trim(),
      callGoal: (args['callGoal']?.toString() ?? '').trim(),
      contextSummary: (args['contextSummary']?.toString() ?? '').trim().isNotEmpty
          ? (args['contextSummary']?.toString() ?? '').trim()
          : contextFromHistory.isNotEmpty
              ? contextFromHistory
              : 'No additional conversation context was provided.',
      urgency: args['urgency'] == 'urgent' ? 'urgent' : 'normal',
    ),
  );

  if (!result.ok) {
    return '❌ Outbound AI call could not start: ${result.error ?? 'Unknown error'}. Fall back to human escalation or messaging.';
  }

  deps.onStatusUpdate?.call('📞 Dialing...');

  final callId = result.callId;
  if (callId == null || callId.isEmpty) {
    return [
      'AI_CALL_STARTED',
      'Call ID: unknown',
      'Status: ${result.status ?? 'started'}',
      'Warning: backend did not return a call ID; live updates are not available.',
    ].join('\n');
  }

  // Start watching the call via WebSocket
  final watcher = OutboundCallWatcher(
    callId: callId,
    analyticsKey: deps.analyticsKey,
    proxyUrl: deps.config?.proxyUrl,
    timeoutMs: deps.config?.watcherTimeoutMs ?? 30 * 60 * 1000,
    onEvent: (event) {
      deps.config?.onCallEvent?.call(event);
      final type = event['type']?.toString();
      if (type == 'status') {
        final status = event['status']?.toString();
        final label = status == 'in_progress'
            ? '📞 On call...'
            : status == 'ringing'
                ? '📞 Ringing...'
                : '📞 $status';
        deps.onStatusUpdate?.call(label);
      } else if (type == 'retry_scheduled') {
        deps.onStatusUpdate?.call('📞 No answer — retrying shortly...');
      } else if (type == 'completed' && event['status'] == 'failed') {
        deps.onStatusUpdate?.call(
          '📞 ${_friendlyFailureLabel(event['failureCode']?.toString())}',
        );
      }
    },
  );

  OutboundCallTerminal terminal;
  try {
    terminal = await watcher.start();
  } catch (e) {
    watcher.close();
    Logger.error('[OutboundCallTool] Watcher error: $e');
    return [
      'AI_CALL_FAILED',
      'Call ID: $callId',
      'Reason: watcher_error: $e',
      'Fall back to human escalation or messaging.',
    ].join('\n');
  }

  // Format transcript
  final transcriptLines = terminal.transcript
      .where((e) => e.text.trim().isNotEmpty)
      .map((e) => '${e.role}: ${e.text.trim()}')
      .toList();

  if (terminal.status != 'completed') {
    final friendly = _friendlyFailureLabel(terminal.failureCode);
    final lines = <String>[
      'AI_CALL_FAILED',
      'Call ID: $callId',
      'Status: ${terminal.status}',
      'What happened: $friendly',
      if (terminal.failureReason != null) 'Technical reason: ${terminal.failureReason}',
      if (terminal.durationSeconds != null) 'Duration: ${terminal.durationSeconds}s',
      if (transcriptLines.isNotEmpty) 'Transcript:',
      ...transcriptLines,
      terminal.failureCode == 'exhausted'
          ? 'All retry attempts have been exhausted. Inform the user you could not reach the contact and suggest alternatives (try again later, escalate, or use messaging).'
          : 'Fall back to human escalation or messaging if the goal was not achieved.',
    ];
    return lines.join('\n');
  }

  // Successful call
  final outcome = terminal.outcome ?? {};
  final outcomeReason = outcome['reason']?.toString() ?? 'unspecified';
  final outcomeSummary = (outcome['summary']?.toString() ?? '').trim().isNotEmpty
      ? outcome['summary']!.toString().trim()
      : transcriptLines.length > 8
          ? transcriptLines.sublist(transcriptLines.length - 8).join('\n')
          : transcriptLines.isNotEmpty
              ? transcriptLines.join('\n')
              : 'No summary available.';

  return [
    'AI_CALL_COMPLETED',
    'Call ID: $callId',
    'Target: ${result.targetDisplayName ?? targetId}',
    'Duration: ${terminal.durationSeconds ?? 0}s',
    'Outcome reason: $outcomeReason',
    'Outcome summary: $outcomeSummary',
    if (transcriptLines.isNotEmpty) 'Transcript:',
    ...transcriptLines,
    'Use this outcome to continue helping the user.',
  ].join('\n');
}
