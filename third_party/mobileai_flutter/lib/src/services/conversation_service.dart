import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../utils/logger.dart';

class ConversationService {
  const ConversationService._();

  static String _storageKey(String key) =>
      '@mobileai_flutter_conversation_$key';
  static const String _deviceIdStorageKey = '@mobileai_flutter_device_id';

  static String _normalizeBaseUrl(String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) return 'https://mobileai.cloud';
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return trimmed.endsWith('/api/v1/analytics')
        ? trimmed.substring(0, trimmed.length - '/api/v1/analytics'.length)
        : trimmed;
  }

  static String _conversationEndpoint(String? baseUrl) =>
      '${_normalizeBaseUrl(baseUrl)}/api/v1/conversations';

  static Future<void> saveMessages({
    required String key,
    required List<AiMessage> messages,
  }) async {
    await saveDraft(
      key: key,
      draft: ConversationDraft(messages: messages),
    );
  }

  static Future<void> saveDraft({
    required String key,
    required ConversationDraft draft,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'activeConversationId': draft.activeConversationId,
      'messages': draft.messages
          .map(
            (message) => {
              'role': message.role,
              'content': _encodeContent(message.content),
              'previewText': message.previewText,
              'timestamp': message.timestamp,
            },
          )
          .toList(growable: false),
    };
    await prefs.setString(_storageKey(key), jsonEncode(payload));
  }

  static Future<List<AiMessage>> loadMessages(String key) async {
    final draft = await loadDraft(key);
    return draft.messages;
  }

  static Future<ConversationDraft> loadDraft(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(key));
    if (raw == null || raw.isEmpty) return const ConversationDraft();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return ConversationDraft(messages: _decodeMessages(decoded));
      }
      if (decoded is! Map) return const ConversationDraft();

      final map = Map<String, dynamic>.from(decoded);
      final rawMessages = map['messages'];
      final messages = rawMessages is List
          ? _decodeMessages(rawMessages)
          : const <AiMessage>[];

      return ConversationDraft(
        activeConversationId: map['activeConversationId']?.toString(),
        messages: messages,
      );
    } catch (_) {
      return const ConversationDraft();
    }
  }

  static List<AiMessage> _decodeMessages(List<dynamic> rawMessages) {
    return rawMessages
        .whereType<Map>()
        .map((entry) {
          final content = _decodeContent(entry['content']);
          return AiMessage(
            role: '${entry['role'] ?? 'assistant'}',
            content: content,
            previewText: entry['previewText']?.toString(),
            timestamp: (entry['timestamp'] as num?)?.toInt(),
          );
        })
        .toList(growable: false);
  }

  static Future<void> clearConversation(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(key));
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdStorageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final next = const Uuid().v4();
    await prefs.setString(_deviceIdStorageKey, next);
    return next;
  }

  static Future<String?> startConversation({
    required String analyticsKey,
    String? userId,
    String? deviceId,
    String? baseUrl,
    Map<String, String>? headers,
    required List<AiMessage> messages,
    String? title,
  }) async {
    if (analyticsKey.isEmpty) return null;

    final payload = _toBackendPayload(messages);
    if (payload.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_conversationEndpoint(baseUrl)),
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode({
          'analyticsKey': analyticsKey,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'messages': payload,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.warn(
          'ConversationService.startConversation failed: HTTP ${response.statusCode}',
        );
        return null;
      }

      final body = jsonDecode(response.body);
      return body is Map ? body['conversationId']?.toString() : null;
    } catch (error) {
      Logger.warn('ConversationService.startConversation error: $error');
      return null;
    }
  }

  static Future<void> appendMessages({
    required String conversationId,
    required String analyticsKey,
    String? baseUrl,
    Map<String, String>? headers,
    required List<AiMessage> messages,
  }) async {
    if (analyticsKey.isEmpty || conversationId.isEmpty) return;

    final payload = _toBackendPayload(messages);
    if (payload.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(_conversationEndpoint(baseUrl)),
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode({
          'analyticsKey': analyticsKey,
          'conversationId': conversationId,
          'messages': payload,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.warn(
          'ConversationService.appendMessages failed: HTTP ${response.statusCode}',
        );
      }
    } catch (error) {
      Logger.warn('ConversationService.appendMessages error: $error');
    }
  }

  static Future<List<ConversationSummary>> fetchConversations({
    required String analyticsKey,
    String? userId,
    String? deviceId,
    String? baseUrl,
    Map<String, String>? headers,
    int limit = 20,
  }) async {
    if (analyticsKey.isEmpty) return const [];
    if ((userId == null || userId.isEmpty) &&
        (deviceId == null || deviceId.isEmpty)) {
      return const [];
    }

    try {
      final uri = Uri.parse(_conversationEndpoint(baseUrl)).replace(
        queryParameters: <String, String>{
          'analyticsKey': analyticsKey,
          'limit': '$limit',
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        },
      );
      final response = await http.get(uri, headers: {...?headers});

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.warn(
          'ConversationService.fetchConversations failed: HTTP ${response.statusCode}',
        );
        return const [];
      }

      final body = jsonDecode(response.body);
      final conversations = body is Map
          ? body['conversations'] as List<dynamic>?
          : null;
      if (conversations == null) return const [];

      return conversations
          .whereType<Map>()
          .map(
            (entry) =>
                ConversationSummary.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);
    } catch (error) {
      Logger.warn('ConversationService.fetchConversations error: $error');
      return const [];
    }
  }

  static Future<List<AiMessage>?> fetchConversation({
    required String conversationId,
    required String analyticsKey,
    String? baseUrl,
    Map<String, String>? headers,
  }) async {
    if (analyticsKey.isEmpty || conversationId.isEmpty) return null;

    try {
      final uri = Uri.parse('${_conversationEndpoint(baseUrl)}/$conversationId')
          .replace(
            queryParameters: <String, String>{'analyticsKey': analyticsKey},
          );
      final response = await http.get(uri, headers: {...?headers});

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.warn(
          'ConversationService.fetchConversation failed: HTTP ${response.statusCode}',
        );
        return null;
      }

      final body = jsonDecode(response.body);
      final rawMessages = body is Map
          ? body['messages'] as List<dynamic>?
          : null;
      if (rawMessages == null) return null;

      return rawMessages
          .whereType<Map>()
          .map(
            (entry) => AiMessage(
              role: '${entry['role'] ?? 'assistant'}',
              content: '${entry['content'] ?? ''}',
              previewText: '${entry['content'] ?? ''}',
              timestamp: (entry['timestamp'] as num?)?.toInt(),
            ),
          )
          .toList(growable: false);
    } catch (error) {
      Logger.warn('ConversationService.fetchConversation error: $error');
      return null;
    }
  }

  static List<Map<String, dynamic>> _toBackendPayload(
    List<AiMessage> messages,
  ) {
    return messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .map(
          (message) => {
            'role': message.role,
            'content': message.previewText.trim().isEmpty
                ? richContentToPlainText(message.content).trim()
                : message.previewText.trim(),
            'timestamp': message.timestamp,
          },
        )
        .where((message) => (message['content'] as String).isNotEmpty)
        .toList(growable: false);
  }

  static Object _encodeContent(Object content) {
    if (content is String) return content;
    if (content is AiTextNode) {
      return {'type': 'text', 'text': content.text};
    }
    if (content is AiBlockNode) {
      return {
        'type': 'block',
        'id': content.id,
        'blockType': content.blockType,
        'props': content.props,
        'placement': content.placement.name,
        'lifecycle': content.lifecycle.name,
      };
    }
    if (content is List<AiRichNode>) {
      return content.map(_encodeContent).toList(growable: false);
    }
    return content.toString();
  }

  static Object _decodeContent(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map(_decodeNode)
          .whereType<AiRichNode>()
          .toList(growable: false);
    }
    if (content is Map) {
      return _decodeNode(content) ?? '';
    }
    return content.toString();
  }

  static AiRichNode? _decodeNode(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type']?.toString();
    if (type == 'text') {
      return AiTextNode('${map['text'] ?? ''}');
    }
    if (type == 'block') {
      return AiBlockNode(
        id: '${map['id'] ?? ''}',
        blockType: '${map['blockType'] ?? ''}',
        props: Map<String, dynamic>.from((map['props'] as Map?) ?? const {}),
        placement: _decodePlacement(map['placement']?.toString()),
        lifecycle: _decodeLifecycle(map['lifecycle']?.toString()),
      );
    }
    return null;
  }

  static BlockPlacement _decodePlacement(String? value) {
    return BlockPlacement.values.firstWhere(
      (placement) => placement.name == value,
      orElse: () => BlockPlacement.chat,
    );
  }

  static BlockLifecycle _decodeLifecycle(String? value) {
    return BlockLifecycle.values.firstWhere(
      (lifecycle) => lifecycle.name == value,
      orElse: () => BlockLifecycle.dismissible,
    );
  }
}

class ConversationDraft {
  final String? activeConversationId;
  final List<AiMessage> messages;

  const ConversationDraft({
    this.activeConversationId,
    this.messages = const <AiMessage>[],
  });
}
