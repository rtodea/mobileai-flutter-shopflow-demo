import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/types.dart';
import '../utils/logger.dart';

class MobileAIKnowledgeRetrieverOptions {
  final String analyticsKey;
  final String? baseUrl;
  final Map<String, String>? headers;
  final int? limit;

  const MobileAIKnowledgeRetrieverOptions({
    required this.analyticsKey,
    this.baseUrl,
    this.headers,
    this.limit,
  });
}

String _normalizeBaseUrl(String? baseUrl) {
  if (baseUrl == null || baseUrl.isEmpty) return 'https://mobileai.cloud';
  final trimmed = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return trimmed.endsWith('/api/v1/analytics')
      ? trimmed.substring(0, trimmed.length - '/api/v1/analytics'.length)
      : trimmed;
}

KnowledgeRetriever createMobileAIKnowledgeRetriever(
  MobileAIKnowledgeRetrieverOptions options,
) {
  final url = '${_normalizeBaseUrl(options.baseUrl)}/api/v1/knowledge/query';

  return _HostedKnowledgeRetriever(url, options);
}

class _HostedKnowledgeRetriever implements KnowledgeRetriever {
  final String url;
  final MobileAIKnowledgeRetrieverOptions options;

  const _HostedKnowledgeRetriever(this.url, this.options);

  @override
  Future<List<KnowledgeEntry>> retrieve(String query, String screenName) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${options.analyticsKey}',
          ...?options.headers,
        },
        body: jsonEncode({
          'query': query,
          'screenName': screenName,
          'limit': options.limit,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Logger.warn(
          'MobileAI knowledge query failed: HTTP ${response.statusCode}',
        );
        return const [];
      }

      final payload = jsonDecode(response.body);
      final entries = (payload is Map ? payload['entries'] : null) as List?;
      if (entries == null) return const [];

      return entries
          .whereType<Map>()
          .map(
            (entry) => KnowledgeEntry(
              title: '${entry['title'] ?? ''}',
              content: '${entry['content'] ?? ''}',
              tags: (entry['tags'] as List?)?.map((item) => '$item').toList(),
              screens: (entry['screens'] as List?)
                  ?.map((item) => '$item')
                  .toList(),
              priority: (entry['priority'] as num?)?.toInt(),
            ),
          )
          .toList(growable: false);
    } catch (error) {
      Logger.error('MobileAI knowledge query failed: $error');
      return const [];
    }
  }
}
