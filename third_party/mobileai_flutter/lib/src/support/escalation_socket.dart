import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/logger.dart';

/// EscalationSocket — manages a WebSocket connection to the MobileAI platform
/// for receiving real-time replies from human support agents.
///
/// Lifecycle:
/// 1. SDK calls escalate_to_human → POST /api/v1/escalations → gets { ticketId, wsUrl }
/// 2. EscalationSocket.connect(wsUrl) opens a WS connection
/// 3. Platform pushes { type: 'reply', ticketId, reply } when agent responds
/// 4. onReply callback fires → shown in chat UI as "Human Agent: `reply`"
/// 5. disconnect() on chat close / unmount
///
/// Handles:
/// - Server heartbeat pings (type: 'ping') — acknowledged silently
/// - Auto-reconnect on unexpected close (max 3 attempts, exponential backoff)
/// - Message queue — buffers sendText calls while connecting, flushes on open
class EscalationSocket {
  final void Function(String reply, String? ticketId) onReply;
  final void Function(dynamic error)? onError;
  final void Function(bool isTyping)? onTypingChange;
  final void Function(String? ticketId)? onTicketClosed;
  final int maxReconnectAttempts;

  WebSocketChannel? _channel;
  String? _wsUrl;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _intentionalClose = false;
  bool _hasErrored = false;
  bool _isReady = false;

  /// Messages buffered while the socket is connecting / reconnecting.
  final List<String> _messageQueue = [];

  StreamSubscription? _streamSubscription;

  EscalationSocket({
    required this.onReply,
    this.onError,
    this.onTypingChange,
    this.onTicketClosed,
    this.maxReconnectAttempts = 3,
  });

  /// True if the underlying WebSocket is open and ready to send.
  bool get isConnected => _channel != null && _isReady;

  /// True if the socket encountered an error (and may not be reliable to reuse).
  bool get hasErrored => _hasErrored;

  void connect(String wsUrl) {
    _wsUrl = wsUrl;
    _intentionalClose = false;
    _hasErrored = false;
    _openConnection();
  }

  /// Send a text message to the live agent.
  ///
  /// If the socket is currently connecting or reconnecting, the message is
  /// buffered and sent automatically once the connection is established.
  /// Returns `true` in both cases (connected send + queued send).
  /// Returns `false` only if the socket has no URL (was never connected).
  bool sendText(String text) {
    if (_wsUrl == null) {
      Logger.warn('[EscalationSocket] No URL — cannot send message');
      return false;
    }

    if (isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({'type': 'user_message', 'content': text}),
        );
        return true;
      } catch (e) {
        Logger.error('[EscalationSocket] Failed to send message: $e');
        return false;
      }
    }

    // Socket is connecting or reconnecting — queue the message
    Logger.info('[EscalationSocket] ⏳ Socket not open — queuing message');
    _messageQueue.add(
      jsonEncode({'type': 'user_message', 'content': text}),
    );

    // If socket is closed, kick off a reconnect to flush the queue
    if (_channel == null) {
      Logger.info('[EscalationSocket] Socket CLOSED — initiating reconnect');
      _openConnection();
    }

    return true; // optimistic — message is queued
  }

  bool sendTypingStatus(bool isTyping) {
    if (isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({'type': isTyping ? 'typing_start' : 'typing_stop'}),
        );
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  void disconnect() {
    _intentionalClose = true;
    _messageQueue.clear(); // drop queued messages on intentional close
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _isReady = false;
    Logger.info('[EscalationSocket] Disconnected');
  }

  void _flushQueue() {
    if (_messageQueue.isEmpty) return;

    Logger.info('[EscalationSocket] 🚀 Flushing ${_messageQueue.length} queued message(s)');
    final queue = List<String>.from(_messageQueue); // copy
    _messageQueue.clear();

    for (final payload in queue) {
      try {
        _channel!.sink.add(payload);
      } catch (e) {
        Logger.error('[EscalationSocket] Failed to flush queued message: $e');
      }
    }
  }

  void _openConnection() {
    if (_wsUrl == null) return;

    // Cancel existing subscription if any
    _streamSubscription?.cancel();

    try {
      Logger.info('[EscalationSocket] Connecting to $_wsUrl...');
      _isReady = false;
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl!));

      // Listen to the stream
      _streamSubscription = _channel!.stream.listen(
        (event) {
          _handleMessage(event);
        },
        onError: (error) {
          Logger.error('[EscalationSocket] ❌ WebSocket error: $error');
          _hasErrored = true;
          _isReady = false;
          onError?.call(error);
        },
        onDone: () {
          Logger.info('[EscalationSocket] Connection done');
          _isReady = false;
          if (!_intentionalClose) {
            _handleClose();
          }
        },
        cancelOnError: false,
      );

      // Connection is ready once we've set up the stream
      _isReady = true;
      _reconnectAttempts = 0;
      _hasErrored = false;
      Logger.info('[EscalationSocket] ✅ Connected to $_wsUrl');
      _flushQueue();
    } catch (e) {
      Logger.error('[EscalationSocket] Failed to open WebSocket: $e');
      _isReady = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic event) {
    if (event is! String) return;

    try {
      final msg = jsonDecode(event) as Map<String, dynamic>;
      final type = msg['type']?.toString();

      Logger.debug('[EscalationSocket] Message received: $type');

      switch (type) {
        case 'ping':
          Logger.debug('[EscalationSocket] Heartbeat ping received');
          break;

        case 'reply':
          final reply = msg['reply']?.toString() ?? '';
          final ticketId = msg['ticketId']?.toString();
          Logger.info('[EscalationSocket] Human reply received: ${reply.substring(0, 80)}');
          onTypingChange?.call(false);
          onReply.call(reply, ticketId);
          break;

        case 'typing_start':
          onTypingChange?.call(true);
          break;

        case 'typing_stop':
          onTypingChange?.call(false);
          break;

        case 'ticket_closed':
          final ticketId = msg['ticketId']?.toString();
          Logger.info('[EscalationSocket] Ticket closed by agent: $ticketId');
          onTypingChange?.call(false);
          onTicketClosed?.call(ticketId);
          _intentionalClose = true;
          _channel?.sink.close();
          break;
      }
    } catch (e) {
      Logger.warn('[EscalationSocket] Failed to parse message: $e');
    }
  }

  void _handleClose() {
    if (_intentionalClose) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      Logger.warn('[EscalationSocket] Max reconnect attempts reached — giving up');
      _messageQueue.clear(); // drop queued messages
      return;
    }

    final delay = 1000 * (1 << _reconnectAttempts).clamp(1, 16);
    _reconnectAttempts++;
    Logger.info(
      '[EscalationSocket] Reconnecting in ${delay}ms (attempt $_reconnectAttempts/$maxReconnectAttempts)',
    );

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _hasErrored = false;
      _channel = null; // clear old channel before reconnect
      _openConnection();
    });
  }

  void dispose() {
    disconnect();
  }
}
