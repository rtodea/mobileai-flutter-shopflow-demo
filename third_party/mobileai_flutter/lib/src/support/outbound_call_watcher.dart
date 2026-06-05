import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/outbound_call_service.dart';
import '../utils/logger.dart';

/// WebSocket-based watcher for outbound AI call events.
///
/// Connects to ws://.../ws/outbound-calls/:callId/events?key=...
/// Receives real-time events: status, transcript, completed, retry_scheduled.
/// Falls back to HTTP poll on socket close.
class OutboundCallWatcher {
  final String callId;
  final String analyticsKey;
  final String? proxyUrl;
  final int timeoutMs;
  final void Function(Map<String, dynamic> event)? onEvent;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _timeoutTimer;
  Completer<OutboundCallTerminal>? _completer;
  bool _resolved = false;
  String? _latestStatus;
  final List<TranscriptEntry> _collectedTranscript = [];

  OutboundCallWatcher({
    required this.callId,
    required this.analyticsKey,
    this.proxyUrl,
    this.timeoutMs = 30 * 60 * 1000,
    this.onEvent,
  });

  /// Start watching. Returns a Future that resolves with terminal call state.
  Future<OutboundCallTerminal> start() {
    if (_completer != null) return _completer!.future;
    _completer = Completer<OutboundCallTerminal>();

    final wsUrl = _buildWsUrl();
    Logger.info('[OutboundCallWatcher] Connecting to $wsUrl');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (e) {
      Logger.error('[OutboundCallWatcher] Failed to open socket: $e');
      _failOnce(Exception('Failed to open watcher socket: $e'));
      return _completer!.future;
    }

    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: (error) {
        Logger.warn('[OutboundCallWatcher] Socket error: $error');
      },
      onDone: () {
        if (!_resolved) {
          Logger.info('[OutboundCallWatcher] Socket closed — polling fallback');
          _pollAndResolve();
        }
      },
      cancelOnError: false,
    );

    // Hard timeout
    final effectiveTimeout = timeoutMs.clamp(10000, 30 * 60 * 1000);
    _timeoutTimer = Timer(Duration(milliseconds: effectiveTimeout), () {
      if (_resolved) return;
      _resolveOnce(OutboundCallTerminal(
        status: 'failed',
        transcript: _collectedTranscript,
        failureReason: 'watcher_timeout',
        failureCode: 'watcher_timeout',
      ));
      close();
    });

    return _completer!.future;
  }

  /// Close the watcher, cancel timers and subscription.
  void close() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  String _buildWsUrl() {
    final root = _resolveWsBase(proxyUrl);
    final key = Uri.encodeComponent(analyticsKey);
    final id = Uri.encodeComponent(callId);
    return '$root/ws/outbound-calls/$id/events?key=$key';
  }

  static String _resolveWsBase(String? proxyUrl) {
    var root = (proxyUrl ?? 'https://mobileai.cloud')
        .replaceAll(RegExp(r'/$'), '')
        .replaceAll('/api/v1/analytics', '');
    if (root.startsWith('https://')) {
      root = 'wss://${root.substring('https://'.length)}';
    } else if (root.startsWith('http://')) {
      root = 'ws://${root.substring('http://'.length)}';
    }
    return root;
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;

    Map<String, dynamic> event;
    try {
      event = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // Fire external callback
    try {
      onEvent?.call(event);
    } catch (e) {
      Logger.warn('[OutboundCallWatcher] onEvent threw: $e');
    }

    final type = event['type']?.toString();

    switch (type) {
      case 'transcript':
        _collectedTranscript.add(TranscriptEntry(
          role: event['role']?.toString() ?? 'unknown',
          text: event['text']?.toString() ?? '',
          at: event['at']?.toString(),
        ));
        break;

      case 'status':
        _latestStatus = event['status']?.toString();
        break;

      case 'retry_scheduled':
        // Keep waiting — don't resolve
        break;

      case 'completed':
        _latestStatus = event['status']?.toString();
        final rawTranscript = event['transcript'] as List<dynamic>?;
        final transcript = (rawTranscript != null && rawTranscript.isNotEmpty)
            ? rawTranscript
                .map((e) => TranscriptEntry.fromJson(e as Map<String, dynamic>))
                .toList()
            : _collectedTranscript;

        _resolveOnce(OutboundCallTerminal(
          status: event['status']?.toString() ?? 'failed',
          durationSeconds: (event['durationSeconds'] as num?)?.toInt(),
          outcome: event['outcome'] as Map<String, dynamic>?,
          transcript: transcript,
          failureReason: event['failureReason']?.toString(),
          failureCode: event['failureCode']?.toString(),
          billedCostUsd: (event['billedCostUsd'] as num?)?.toDouble(),
        ));
        close();
        break;
    }
  }

  Future<void> _pollAndResolve() async {
    try {
      final polled = await getOutboundCallStatus(
        callId: callId,
        analyticsKey: analyticsKey,
        proxyUrl: proxyUrl,
      );
      if (polled != null) {
        _resolveOnce(polled);
        return;
      }
    } catch (_) {
      // poll failed — fall through
    }

    _resolveOnce(OutboundCallTerminal(
      status: _latestStatus == 'completed' ? 'completed' : 'failed',
      transcript: _collectedTranscript,
      failureReason: _latestStatus == 'completed' ? null : 'socket_closed_before_terminal',
      failureCode: 'connection_lost',
    ));
  }

  void _resolveOnce(OutboundCallTerminal terminal) {
    if (_resolved) return;
    _resolved = true;
    _completer?.complete(terminal);
  }

  void _failOnce(Exception error) {
    if (_resolved) return;
    _resolved = true;
    _completer?.completeError(error);
  }
}
