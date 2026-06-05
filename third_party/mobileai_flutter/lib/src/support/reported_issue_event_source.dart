import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'types.dart';

class ReportedIssueEventSource {
  final void Function(ReportedIssueStatusUpdate update)? onStatusUpdate;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  ReportedIssueEventSource({this.onStatusUpdate});

  bool get isConnected => _channel != null;

  void connect(String url) {
    disconnect();
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _subscription = _channel!.stream.listen((event) {
      if (event is! String) return;
      try {
        final data = jsonDecode(event) as Map<String, dynamic>;
        final type = data['type']?.toString();
        if (type != 'reported_issue_status') return;
        onStatusUpdate?.call(
          ReportedIssueStatusUpdate(
            id: data['id']?.toString() ?? '',
            status: data['status']?.toString() ?? 'acknowledged',
            message: data['message']?.toString() ?? '',
            source: data['source']?.toString() ?? 'system',
            timestamp: data['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
          ),
        );
      } catch (_) {
        // Ignore malformed events from custom backends.
      }
    });
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}
