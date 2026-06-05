import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/types.dart';
import '../services/telemetry/device.dart' show getDeviceId, initDeviceId;
import '../services/telemetry/device_metadata.dart' show getDeviceMetadata;
import '../utils/logger.dart';
import 'escalation_socket.dart';
import 'types.dart';

/// Escalate tool — hands off the conversation to a human agent.
///
/// Providers:
/// - 'mobileai' (default when analyticsKey present):
///   POSTs to MobileAI /api/v1/escalations → gets ticketId + wsUrl
///   Opens WebSocket via EscalationSocket → agent reply pushed in real time
/// - 'custom': fires the consumer's onEscalate callback (backward compatible)

const String _mobileaiHost = 'https://mobileai.cloud';

/// Callback signature for escalation started event.
typedef OnEscalationStarted = void Function(String ticketId);

/// Callback signature for human reply event.
typedef OnHumanReply = void Function(String reply, String? ticketId);

/// Callback signature for typing change event.
typedef OnTypingChange = void Function(bool isTyping);

/// Callback signature for ticket closed event.
typedef OnTicketClosed = void Function(String? ticketId);

ToolDefinition createEscalateTool({
  required EscalationConfig config,
  String? analyticsKey,
  required Map<String, dynamic> Function() getContext,
  List<Map<String, String>> Function()? getHistory,
  List<Map<String, dynamic>> Function()? getToolCalls,
  List<String> Function()? getScreenFlow,
  OnHumanReply? onHumanReply,
  OnEscalationStarted? onEscalationStarted,
  OnTypingChange? onTypingChange,
  OnTicketClosed? onTicketClosed,
  Map<String, dynamic>? userContext,
  String? pushToken,
  String? pushTokenType,
}) {
  // Determine effective provider
  final provider =
      config.provider ?? (analyticsKey != null ? EscalationProvider.mobileai : EscalationProvider.custom);

  // Socket instance — one per tool instance
  EscalationSocket? socket;

  return ToolDefinition(
    name: 'escalate_to_human',
    description: [
      'Hand off the conversation to a human support agent.',
      'Use this when:',
      '(1) the user explicitly asks for a human,',
      '(2) you cannot resolve the issue after multiple attempts, or',
      '(3) the topic requires human judgment (billing disputes, account issues).',
    ].join(' '),
    parameters: {
      'reason': ToolParam(
        type: 'string',
        description: 'Brief summary of why escalation is needed and what has been tried',
        required: true,
      ),
    },
    handler: (args) async {
      final reason = (args['reason'] as String?) ?? 'User requested human support';
      final context = getContext();

      if (provider == EscalationProvider.mobileai && analyticsKey != null) {
        try {
          final history = (getHistory?.call() ?? []).take(20).toList();
          Logger.info('Escalation: ★★★ Creating ticket — reason: $reason');

          // Ensure device ID is initialized
          await initDeviceId();
          final deviceId = getDeviceId() ?? 'unknown';

          final response = await http
              .post(
                Uri.parse('$_mobileaiHost/api/v1/escalations'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'analyticsKey': analyticsKey,
                  'reason': reason,
                  'screen': context['currentScreen'] ?? '/',
                  'history': history,
                  'stepsBeforeEscalation': context['stepsBeforeEscalation'] ?? 0,
                  'userContext': {
                    ...?userContext,
                    'device': getDeviceMetadata().toJson(),
                  },
                  'screenFlow': getScreenFlow?.call() ?? [],
                  'toolCalls': getToolCalls?.call() ?? [],
                  'pushToken': pushToken,
                  'pushTokenType': pushTokenType,
                  'deviceId': deviceId,
                }),
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Escalation request timed out'),
              );

          if (response.statusCode == 200 || response.statusCode == 201) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final ticketId = data['ticketId']?.toString() ?? '';
            final wsUrl = data['wsUrl']?.toString() ?? '';

            Logger.info('Escalation: ★★★ Ticket created: $ticketId | wsUrl: $wsUrl');

            // Connect WebSocket for real-time reply
            socket?.disconnect();
            socket = EscalationSocket(
              onReply: (reply, replyTicketId) {
                Logger.info('Escalation: ★★★ Human reply for $ticketId: ${reply.substring(0, 80)}');
                onHumanReply?.call(reply, replyTicketId ?? ticketId);
              },
              onTypingChange: (isTyping) {
                Logger.info('Escalation: ★★★ Agent typing: $isTyping');
                onTypingChange?.call(isTyping);
              },
              onTicketClosed: (closedTicketId) {
                Logger.info('Escalation: ★★★ Ticket closed: $closedTicketId');
                onTicketClosed?.call(closedTicketId ?? ticketId);
              },
              onError: (error) {
                Logger.error('Escalation: ★★★ WebSocket error: $error');
              },
            );
            socket!.connect(wsUrl);
            Logger.info('Escalation: ★★★ WebSocket connecting...');

            // Pass the socket to UI
            onEscalationStarted?.call(ticketId);
          } else {
            Logger.error('Escalation: Failed to create ticket: ${response.statusCode}');
          }
        } on TimeoutException {
          Logger.error('Escalation: Network timeout creating ticket');
        } catch (e) {
          Logger.error('Escalation: Network error: $e');
        }

        final message = config.escalationMessage ??
            "Your request has been sent to our support team. A human agent will reply here as soon as possible.";
        return 'ESCALATED: $message';
      }

      // 'custom' provider — fire callback
      final escalationContext = EscalationContext(
        conversationSummary: reason,
        currentScreen: context['currentScreen']?.toString() ?? '/',
        originalQuery: context['originalQuery']?.toString() ?? '',
        stepsBeforeEscalation: (context['stepsBeforeEscalation'] as int?) ?? 0,
      );

      await config.onEscalate?.call(escalationContext);

      final message = config.escalationMessage ??
          "Your request has been sent to our support team. A human agent will reply here as soon as possible.";
      return 'ESCALATED: $message';
    },
  );
}
