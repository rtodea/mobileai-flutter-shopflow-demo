import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mobileai_flutter/src/utils/logger.dart';

import 'types.dart';
import 'agent_runtime.dart'; // To be implemented

/// Connects the Flutter app to the local MCP Server bridge.
class McpBridge {
  final String url;
  final AgentRuntime runtime;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isDestroyed = false;

  McpBridge({required this.url, required this.runtime}) {
    _connect();
  }

  void _connect() {
    if (_isDestroyed) return;

    Logger.info('Connecting to MCP bridge at $url...');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // As soon as the stream is listened to, we know it's trying to connect
      _channel!.stream.listen(
        (message) => _handleMessage(message.toString()),
        onDone: () {
          if (!_isDestroyed) {
            Logger.warn('Disconnected from MCP bridge. Reconnecting in 5s...');
            _channel = null;
            _scheduleReconnect();
          }
        },
        onError: (error) {
          Logger.warn('WebSocket error: $error');
          // onDone will be called afterwards
        },
      );
      
      Logger.info('✅ WebSocket stream initialized for MCP bridge.');
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } catch (e) {
      Logger.warn('WebSocket connection failed: $e');
      _scheduleReconnect();
    }
  }

  Future<void> _handleMessage(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final config = runtime.getConfig();
      final serverMode = config.mcpServerMode;
      final serverEnabled = serverMode == McpServerMode.enabled ||
          (serverMode != McpServerMode.disabled && kDebugMode);

      final type = data['type'] as String?;
      final requestId = data['requestId'] as String?;

      if (type == null || requestId == null) return;

      switch (type) {
        case 'request':
          final command = data['command'] as String?;
          if (command == null) return;
          
          Logger.info('Received task from MCP: "\$command"');

          if (runtime.getIsRunning()) {
            _sendResponse(requestId, {
              'success': false,
              'message': 'Agent is already running a task. Please wait.',
              'steps': [],
            });
            return;
          }

          // Execute the task using the SDK's existing runtime loop
          final result = await runtime.execute(command);
          
          _sendResponse(requestId, {
            'success': result.success,
            'message': result.message,
            // Assuming we map steps to json, but for now just send what we have
          });
          break;

        case 'tools/list':
          if (!serverEnabled) {
            _sendResponse(requestId, {'error': 'MCP server mode is disabled.'});
            return;
          }
          
          final tools = runtime.getTools().map((t) {
            final requiredParams = <String>[];
            t.parameters.forEach((key, val) {
              if (val.required) requiredParams.add(key);
            });
            
            return {
              'name': t.name,
              'description': t.description,
              'inputSchema': {
                'type': 'object',
                'properties': t.parameters.map((k, v) => MapEntry(k, {
                  'type': v.type,
                  'description': v.description,
                  if (v.enumValues != null) 'enum': v.enumValues,
                })),
                'required': requiredParams,
              }
            };
          }).toList();
          
          _sendResponse(requestId, {'tools': tools});
          break;

        case 'tools/call':
          if (!serverEnabled) {
            _sendResponse(requestId, {'error': 'MCP server mode is disabled.'});
            return;
          }
          try {
            final name = data['name'] as String;
            final arguments = data['arguments'] as Map<String, dynamic>? ?? {};
            final result = await runtime.executeTool(name, arguments);
            _sendResponse(requestId, {'result': result});
          } catch (err) {
            _sendResponse(requestId, {'error': err.toString()});
          }
          break;

        case 'screen/state':
          if (!serverEnabled) {
            _sendResponse(requestId, {'error': 'MCP server mode is disabled.'});
            return;
          }
          final screen = runtime.getScreenContext();
          _sendResponse(requestId, {
            'screen': {
              'screenName': screen.screenName,
              'availableScreens': screen.availableScreens,
              'elementsText': screen.elementsText,
            }
          });
          break;
      }
    } catch (err) {
      Logger.error('Error handling message: $err');
    }
  }

  void _sendResponse(String requestId, Map<String, dynamic> payload) {
    if (_channel != null && !_isDestroyed) {
      _channel!.sink.add(jsonEncode({
        'type': 'response',
        'requestId': requestId,
        'payload': payload,
      }));
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer == null && !_isDestroyed) {
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        _connect();
      });
    }
  }

  void destroy() {
    _isDestroyed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
