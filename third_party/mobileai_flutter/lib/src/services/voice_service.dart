import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../core/types.dart';
import '../utils/logger.dart';

typedef VoiceStatus = String;

const String _defaultLiveModel =
    'gemini-2.5-flash-native-audio-preview-12-2025';
const int _defaultInputSampleRate = 16000;
const String _defaultLiveEndpoint =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

class VoiceServiceConfig {
  final String? apiKey;
  final String? proxyUrl;
  final Map<String, String>? proxyHeaders;
  final String? model;
  final String? systemPrompt;
  final List<ToolDefinition> tools;
  final int inputSampleRate;
  final String? language;

  const VoiceServiceConfig({
    this.apiKey,
    this.proxyUrl,
    this.proxyHeaders,
    this.model,
    this.systemPrompt,
    this.tools = const [],
    this.inputSampleRate = _defaultInputSampleRate,
    this.language,
  });
}

class VoiceToolCall {
  final String name;
  final Map<String, dynamic> args;
  final String id;

  const VoiceToolCall({
    required this.name,
    required this.args,
    required this.id,
  });
}

class VoiceServiceCallbacks {
  final FutureOr<void> Function(String base64Audio)? onAudioResponse;
  final FutureOr<void> Function(VoiceToolCall toolCall)? onToolCall;
  final void Function(List<String> ids)? onToolCallCancellation;
  final void Function(String text, bool isFinal, String role)? onTranscript;
  final void Function(String status)? onStatusChange;
  final void Function(String error)? onError;
  final void Function()? onTurnComplete;
  final void Function()? onSetupComplete;

  const VoiceServiceCallbacks({
    this.onAudioResponse,
    this.onToolCall,
    this.onToolCallCancellation,
    this.onTranscript,
    this.onStatusChange,
    this.onError,
    this.onTurnComplete,
    this.onSetupComplete,
  });
}

class VoiceService {
  final VoiceServiceConfig config;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  VoiceServiceCallbacks _callbacks = const VoiceServiceCallbacks();
  String? _sessionHandle;
  VoiceStatus _status = 'disconnected';
  Future<void> _messageQueue = Future<void>.value();

  bool intentionalDisconnect = false;
  VoiceServiceCallbacks? lastCallbacks;

  VoiceService(this.config);

  bool get isConnected => _channel != null && _status == 'connected';
  VoiceStatus get currentStatus => _status;

  Future<void> connect(VoiceServiceCallbacks callbacks) async {
    if (_channel != null) {
      Logger.info('VoiceService.connect() ignored — already connected.');
      return;
    }

    _callbacks = callbacks;
    lastCallbacks = callbacks;
    intentionalDisconnect = false;
    _setStatus('connecting');

    try {
      final uri = _resolveConnectionUri();
      final headers = _resolveConnectionHeaders();

      Logger.info('VoiceService connecting to $uri');
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers.isEmpty ? null : headers,
        pingInterval: const Duration(seconds: 20),
      );

      _subscription = _channel!.stream.listen(
        (event) {
          _messageQueue = _messageQueue
              .then((_) => _handleMessage(event))
              .catchError((Object error, StackTrace stackTrace) {
                Logger.error('VoiceService message handler error: $error');
                _callbacks.onError?.call(error.toString());
              });
        },
        onError: (Object error, StackTrace stackTrace) {
          Logger.error('VoiceService stream error: $error');
          _setStatus('error');
          _callbacks.onError?.call(error.toString());
        },
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          Logger.info('VoiceService closed (code=$code, reason=$reason)');
          _subscription = null;
          _channel = null;
          _setStatus('disconnected');
          if (!intentionalDisconnect) {
            final detail = [
              if (code != null) 'code $code',
              if (reason != null && reason.isNotEmpty) reason,
            ].join(': ');
            _callbacks.onError?.call(
              detail.isEmpty
                  ? 'Voice connection closed unexpectedly.'
                  : 'Voice connection closed unexpectedly ($detail).',
            );
          }
        },
      );

      _channel!.sink.add(jsonEncode({'setup': _buildSetupPayload()}));
    } catch (error) {
      Logger.error('VoiceService failed to connect: $error');
      _channel = null;
      _subscription = null;
      _setStatus('error');
      _callbacks.onError?.call(error.toString());
    }
  }

  Future<void> disconnect() async {
    intentionalDisconnect = true;
    await _sendRealtimeInput(<String, dynamic>{'audioStreamEnd': true});
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _setStatus('disconnected');
  }

  Future<void> sendAudio(String base64Audio) async {
    await _sendRealtimeInput(<String, dynamic>{
      'audio': <String, dynamic>{
        'data': base64Audio,
        'mimeType': 'audio/pcm;rate=${config.inputSampleRate}',
      },
    });
  }

  Future<void> notifyAudioStreamEnded() {
    return _sendRealtimeInput(const <String, dynamic>{'audioStreamEnd': true});
  }

  Future<void> sendText(String text) {
    return _sendClientContent(text);
  }

  Future<void> sendScreenContext(String text) {
    return _sendClientContent(text);
  }

  Future<void> sendFunctionResponse(
    String name,
    String id,
    Map<String, dynamic> result,
  ) async {
    if (_channel == null) return;
    Logger.info('VoiceService sending tool response for $name (id=$id).');
    final payload = <String, dynamic>{
      'toolResponse': <String, dynamic>{
        'functionResponses': <Map<String, dynamic>>[
          <String, dynamic>{'name': name, 'id': id, 'response': result},
        ],
      },
    };
    _channel!.sink.add(jsonEncode(payload));
  }

  Future<void> _sendClientContent(String text) async {
    if (_channel == null || text.trim().isEmpty) return;
    final payload = <String, dynamic>{
      'clientContent': <String, dynamic>{
        'turns': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    };
    _channel!.sink.add(jsonEncode(payload));
  }

  Future<void> _sendRealtimeInput(Map<String, dynamic> input) async {
    if (_channel == null || !isConnected) return;
    _channel!.sink.add(jsonEncode(<String, dynamic>{'realtimeInput': input}));
  }

  Uri _resolveConnectionUri() {
    if (config.proxyUrl != null && config.proxyUrl!.trim().isNotEmpty) {
      final proxyUri = Uri.parse(config.proxyUrl!.trim());
      final scheme = switch (proxyUri.scheme) {
        'http' => 'ws',
        'https' => 'wss',
        '' => 'wss',
        _ => proxyUri.scheme,
      };
      final liveEndpointPath = Uri.parse(_defaultLiveEndpoint).path;
      final path = proxyUri.path.contains('BidiGenerateContent')
          ? proxyUri.path
          : _joinUriPaths(proxyUri.path, liveEndpointPath);
      return proxyUri.replace(scheme: scheme, path: path);
    }

    final apiKey = config.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        '[mobileai_flutter] Voice mode requires either apiKey or voiceProxyUrl/proxyUrl.',
      );
    }
    return Uri.parse(
      _defaultLiveEndpoint,
    ).replace(queryParameters: <String, String>{'key': apiKey});
  }

  String _joinUriPaths(String left, String right) {
    final normalizedLeft = left.endsWith('/')
        ? left.substring(0, left.length - 1)
        : left;
    final normalizedRight = right.startsWith('/') ? right : '/$right';
    if (normalizedLeft.isEmpty) return normalizedRight;
    return '$normalizedLeft$normalizedRight';
  }

  Map<String, String> _resolveConnectionHeaders() {
    if (config.proxyUrl == null || config.proxyUrl!.trim().isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{
      ...?config.proxyHeaders,
      HttpHeaders.contentTypeHeader: 'application/json',
    };
  }

  Map<String, dynamic> _buildSetupPayload() {
    final modelName = config.model?.trim().isNotEmpty == true
        ? config.model!.trim()
        : _defaultLiveModel;

    final setup = <String, dynamic>{
      'model': modelName.startsWith('models/')
          ? modelName
          : 'models/$modelName',
      'generationConfig': <String, dynamic>{
        'responseModalities': const <String>['AUDIO'],
      },
      'realtimeInputConfig': <String, dynamic>{
        'automaticActivityDetection': <String, dynamic>{},
      },
      'inputAudioTranscription': <String, dynamic>{},
      'outputAudioTranscription': <String, dynamic>{},
    };

    final prompt = config.systemPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      setup['systemInstruction'] = <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': prompt},
        ],
      };
    }

    final declarations = _buildToolDeclarations();
    if (declarations.isNotEmpty) {
      setup['tools'] = <Map<String, dynamic>>[
        <String, dynamic>{'functionDeclarations': declarations},
      ];
    }

    if (_sessionHandle != null && _sessionHandle!.isNotEmpty) {
      setup['sessionResumption'] = <String, dynamic>{'handle': _sessionHandle};
    } else {
      setup['sessionResumption'] = <String, dynamic>{};
    }

    return setup;
  }

  List<Map<String, dynamic>> _buildToolDeclarations() {
    if (config.tools.isEmpty) return const <Map<String, dynamic>>[];

    return config.tools
        .where((tool) => tool.name != 'capture_screenshot')
        .map((tool) {
          final required = <String>[];
          final properties = <String, dynamic>{};

          for (final entry in tool.parameters.entries) {
            final param = entry.value;
            var type = param.type.toUpperCase();
            var description = param.description;

            if (type == 'INTEGER') type = 'NUMBER';
            if (type == 'BOOLEAN') {
              type = 'STRING';
              description = '${param.description} (use "true" or "false")';
            }

            final property = <String, dynamic>{
              'type': type,
              'description': description,
            };
            if (param.enumValues != null && param.enumValues!.isNotEmpty) {
              property['enum'] = param.enumValues;
            }
            properties[entry.key] = property;
            if (param.required) required.add(entry.key);
          }

          final declaration = <String, dynamic>{
            'name': tool.name,
            'description': tool.description,
          };

          if (properties.isNotEmpty) {
            declaration['parameters'] = <String, dynamic>{
              'type': 'OBJECT',
              'properties': properties,
              if (required.isNotEmpty) 'required': required,
            };
          }

          return declaration;
        })
        .toList(growable: false);
  }

  Future<void> _handleMessage(dynamic event) async {
    if (event == null) return;
    final raw = event is List<int> ? utf8.decode(event) : '$event';

    try {
      final message = jsonDecode(raw);
      if (message is! Map<String, dynamic>) return;

      if (message.containsKey('setupComplete')) {
        _setStatus('connected');
        _callbacks.onSetupComplete?.call();
      }

      final sessionUpdate = message['sessionResumptionUpdate'];
      if (sessionUpdate is Map<String, dynamic>) {
        final handle = sessionUpdate['newHandle']?.toString();
        if (handle != null && handle.isNotEmpty) {
          _sessionHandle = handle;
        }
      }

      final serverContent = message['serverContent'];
      if (serverContent is Map<String, dynamic>) {
        if (serverContent['interrupted'] == true) {
          _callbacks.onTurnComplete?.call();
        }

        final inputTranscription = serverContent['inputTranscription'];
        if (inputTranscription is Map<String, dynamic>) {
          final text = inputTranscription['text']?.toString();
          if (text != null && text.isNotEmpty) {
            _callbacks.onTranscript?.call(text, true, 'user');
          }
        }

        final outputTranscription = serverContent['outputTranscription'];
        if (outputTranscription is Map<String, dynamic>) {
          final text = outputTranscription['text']?.toString();
          if (text != null && text.isNotEmpty) {
            _callbacks.onTranscript?.call(text, true, 'model');
          }
        }

        final modelTurn = serverContent['modelTurn'];
        if (modelTurn is Map<String, dynamic>) {
          final parts = modelTurn['parts'];
          if (parts is List) {
            for (final part in parts) {
              if (part is! Map<String, dynamic>) continue;
              final inlineData = part['inlineData'];
              if (inlineData is Map<String, dynamic>) {
                final data = inlineData['data']?.toString();
                if (data != null && data.isNotEmpty) {
                  Logger.info(
                    'VoiceService received audio response (${data.length} chars).',
                  );
                  await _callbacks.onAudioResponse?.call(data);
                }
              }
            }
          }
        }

        if (serverContent['turnComplete'] == true) {
          _callbacks.onTurnComplete?.call();
        }
      }

      final toolCall = message['toolCall'];
      if (toolCall is Map<String, dynamic>) {
        final calls = toolCall['functionCalls'];
        if (calls is List) {
          for (final entry in calls) {
            if (entry is! Map<String, dynamic>) continue;
            await _callbacks.onToolCall?.call(
              VoiceToolCall(
                name: entry['name']?.toString() ?? '',
                id: entry['id']?.toString() ?? '',
                args: Map<String, dynamic>.from(
                  (entry['args'] as Map?)?.map(
                        (key, value) => MapEntry('$key', value),
                      ) ??
                      const <String, dynamic>{},
                ),
              ),
            );
          }
        }
      }

      final toolCallCancellation = message['toolCallCancellation'];
      if (toolCallCancellation is Map<String, dynamic>) {
        final ids =
            (toolCallCancellation['ids'] as List?)
                ?.map((id) => '$id')
                .toList(growable: false) ??
            const <String>[];
        if (ids.isNotEmpty) {
          _callbacks.onToolCallCancellation?.call(ids);
        }
      }

      final error = message['error'];
      if (error is Map<String, dynamic>) {
        _callbacks.onError?.call(
          error['message']?.toString() ?? 'Voice session error.',
        );
      }
    } catch (error) {
      Logger.error('VoiceService failed to parse message: $error');
      _callbacks.onError?.call(error.toString());
    }
  }

  void _setStatus(VoiceStatus status) {
    _status = status;
    _callbacks.onStatusChange?.call(status);
  }
}
