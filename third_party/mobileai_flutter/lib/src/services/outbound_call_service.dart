import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/logger.dart';
import 'telemetry/device.dart' show getDeviceId, initDeviceId;
import 'telemetry/device_metadata.dart' show getDeviceMetadata;

const String _logTag = 'OutboundCallService';
const String _defaultHost = 'https://mobileai.cloud';

// ─── Types ───────────────────────────────────────────────────────────────────

/// Configuration for outbound AI calls.
class OutboundCallConfig {
  /// Whether outbound calls are enabled. Default: true when analyticsKey present.
  final bool enabled;

  /// Optional MobileAI-compatible backend root. Defaults to https://mobileai.cloud.
  final String? proxyUrl;

  /// Optional extra headers sent to the outbound-call endpoint.
  final Map<String, String>? headers;

  /// Optional client-side target allowlist. Backend remains the source of truth.
  final List<String>? allowedTargetTypes;

  /// Hard cap on watcher wait time. Default 30 min (matches max call duration).
  final int watcherTimeoutMs;

  /// Optional live event callback.
  final void Function(Map<String, dynamic> event)? onCallEvent;

  const OutboundCallConfig({
    this.enabled = true,
    this.proxyUrl,
    this.headers,
    this.allowedTargetTypes,
    this.watcherTimeoutMs = 30 * 60 * 1000,
    this.onCallEvent,
  });
}

/// Request body for starting an outbound call.
class OutboundCallRequest {
  final String targetType;
  final String targetId;
  final String reason;
  final String callGoal;
  final String contextSummary;
  final String urgency;
  final String? linkedEscalationTicketId;
  final String? linkedReportedIssueId;

  const OutboundCallRequest({
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.callGoal,
    required this.contextSummary,
    this.urgency = 'normal',
    this.linkedEscalationTicketId,
    this.linkedReportedIssueId,
  });

  Map<String, dynamic> toJson() => {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        'callGoal': callGoal,
        'contextSummary': contextSummary,
        'urgency': urgency,
        if (linkedEscalationTicketId != null) 'linkedEscalationTicketId': linkedEscalationTicketId,
        if (linkedReportedIssueId != null) 'linkedReportedIssueId': linkedReportedIssueId,
      };
}

/// Result from starting an outbound call.
class StartOutboundCallResult {
  final bool ok;
  final String? callId;
  final String? status;
  final String? targetDisplayName;
  final String? message;
  final String? error;

  const StartOutboundCallResult({
    required this.ok,
    this.callId,
    this.status,
    this.targetDisplayName,
    this.message,
    this.error,
  });
}

/// Terminal state returned by HTTP poll or watcher.
class OutboundCallTerminal {
  final String status; // 'completed' | 'failed'
  final int? durationSeconds;
  final Map<String, dynamic>? outcome;
  final List<TranscriptEntry> transcript;
  final String? failureReason;
  final String? failureCode;
  final double? billedCostUsd;

  const OutboundCallTerminal({
    required this.status,
    this.durationSeconds,
    this.outcome,
    this.transcript = const [],
    this.failureReason,
    this.failureCode,
    this.billedCostUsd,
  });
}

/// Single transcript entry.
class TranscriptEntry {
  final String role;
  final String text;
  final String? at;

  const TranscriptEntry({required this.role, required this.text, this.at});

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    return TranscriptEntry(
      role: (json['role'] as String?) ?? 'unknown',
      text: (json['text'] as String?) ?? '',
      at: json['at']?.toString(),
    );
  }
}

// ─── Default Target Types ────────────────────────────────────────────────────

const List<String> defaultOutboundCallTargetTypes = [
  'merchant',
  'vendor',
  'carrier',
  'driver',
  'technician',
  'billing_team',
  'fraud_team',
  'external_partner',
];

// ─── Service Functions ───────────────────────────────────────────────────────

String _resolveBase(String? proxyUrl) {
  final raw = (proxyUrl ?? _defaultHost).replaceAll(RegExp(r'/$'), '').replaceAll('/api/v1/analytics', '');
  return raw;
}

/// Start an outbound AI call via the MobileAI API.
Future<StartOutboundCallResult> startOutboundAiCall({
  required String analyticsKey,
  required OutboundCallRequest request,
  OutboundCallConfig? config,
  String? currentScreen,
  Map<String, dynamic>? userContext,
}) async {
  if (analyticsKey.isEmpty) {
    return const StartOutboundCallResult(
      ok: false,
      error: 'MobileAI analyticsKey is required for outbound AI calls.',
    );
  }

  final allowedTypes = config?.allowedTargetTypes;
  if (allowedTypes != null && allowedTypes.isNotEmpty && !allowedTypes.contains(request.targetType)) {
    return StartOutboundCallResult(
      ok: false,
      error: 'Target type "${request.targetType}" is not allowed by this SDK configuration.',
    );
  }

  await initDeviceId();
  final root = _resolveBase(config?.proxyUrl);

  try {
    final response = await http
        .post(
          Uri.parse('$root/api/v1/outbound-calls'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $analyticsKey',
            ...(config?.headers ?? {}),
          },
          body: jsonEncode({
            ...request.toJson(),
            'currentScreen': currentScreen,
            'userContext': {
              ...(userContext ?? {}),
              'deviceId': getDeviceId(),
              'device': getDeviceMetadata().toJson(),
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    final payload = _tryParseJson(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorMsg = payload?['error']?.toString() ??
          'Outbound AI call failed with HTTP ${response.statusCode}.';
      return StartOutboundCallResult(ok: false, error: errorMsg);
    }

    final call = payload?['call'] as Map<String, dynamic>?;
    return StartOutboundCallResult(
      ok: true,
      callId: call?['id']?.toString(),
      status: call?['status']?.toString(),
      targetDisplayName: call?['targetDisplayName']?.toString(),
      message: payload?['message']?.toString(),
    );
  } on TimeoutException {
    Logger.error('$_logTag: Network timeout starting outbound call');
    return const StartOutboundCallResult(ok: false, error: 'Network timeout starting outbound AI call.');
  } catch (e) {
    Logger.error('$_logTag: Network error: $e');
    return StartOutboundCallResult(ok: false, error: 'Network error: $e');
  }
}

/// HTTP poll to get terminal call state (used as fallback when WebSocket drops).
Future<OutboundCallTerminal?> getOutboundCallStatus({
  required String callId,
  required String analyticsKey,
  String? proxyUrl,
}) async {
  final root = _resolveBase(proxyUrl);
  try {
    final res = await http.get(
      Uri.parse('$root/api/v1/outbound-calls/${Uri.encodeComponent(callId)}'),
      headers: {'Authorization': 'Bearer $analyticsKey'},
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return null;

    final data = _tryParseJson(res.body);
    final call = data?['call'] as Map<String, dynamic>?;
    if (call == null) return null;

    final status = call['status']?.toString();
    if (status != 'completed' && status != 'failed') return null;

    final rawTranscript = call['transcript'] as List<dynamic>?;
    final transcript = rawTranscript
            ?.map((e) => TranscriptEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return OutboundCallTerminal(
      status: status!,
      durationSeconds: (call['durationSeconds'] as num?)?.toInt(),
      outcome: call['outcome'] as Map<String, dynamic>?,
      transcript: transcript,
      failureReason: call['failureReason']?.toString(),
      failureCode: call['failureCode']?.toString(),
      billedCostUsd: (call['billedCostUsd'] as num?)?.toDouble(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _tryParseJson(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
