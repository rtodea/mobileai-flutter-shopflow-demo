import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileai_flutter/mobileai_flutter.dart';
import 'ai_screen_map.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: ShopFlowApp()));
}

class ShopFlowApp extends StatelessWidget {
  const ShopFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    const mobileAiBaseUrl = String.fromEnvironment(
      'EXPO_PUBLIC_MOBILEAI_BASE_URL',
      defaultValue: 'https://mobileai.cloud',
    );
    const mobileAiAnalyticsKey = String.fromEnvironment(
      'EXPO_PUBLIC_MOBILEAI_KEY',
      defaultValue: 'mobileai_pub_37aef8662883f2eba40dfc70763f4ef5b1a1a686',
    );

    final normalizedBaseUrl = _normalizeBaseUrl(mobileAiBaseUrl);
    final textProxyUrl = normalizedBaseUrl == null
        ? null
        : '$normalizedBaseUrl/api/v1/hosted-proxy/text';
    final voiceProxyUrl = normalizedBaseUrl == null
        ? null
        : _buildVoiceProxyUrl(normalizedBaseUrl);
    final proxyHeaders = mobileAiAnalyticsKey.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $mobileAiAnalyticsKey'};

    return AIAgent(
      apiKey: textProxyUrl == null && geminiApiKey.isNotEmpty
          ? geminiApiKey
          : null,
      proxyUrl: textProxyUrl,
      proxyHeaders: proxyHeaders,
      voiceProxyUrl: voiceProxyUrl,
      voiceProxyHeaders: proxyHeaders,
      router: router,
      maxSteps: 15,
      language: 'en',
      instructions:
          'You are a helpful assistant for ShopFlow, an e-commerce app.',
      enableVoice: true,
      debug: true,
      screenMap: shopFlowScreenMap,
      conversationPersistenceKey: 'shopflow-example',
      telemetry: mobileAiAnalyticsKey.isEmpty
          ? null
          : TelemetryConfig(
              analyticsKey: mobileAiAnalyticsKey,
              baseUrl: normalizedBaseUrl,
            ),
      onResult: (result) {
        debugPrint('[ShopFlow] Agent result: ${result.message}');
      },
      child: MaterialApp.router(
        title: 'ShopFlow',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}

String? _normalizeBaseUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String _buildVoiceProxyUrl(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri
      .replace(
        scheme: scheme,
        path: _joinPathSegments(uri.path, '/ws/hosted-proxy/voice'),
      )
      .toString();
}

String _joinPathSegments(String left, String right) {
  final normalizedLeft = left.endsWith('/')
      ? left.substring(0, left.length - 1)
      : left;
  final normalizedRight = right.startsWith('/') ? right : '/$right';
  if (normalizedLeft.isEmpty) return normalizedRight;
  return '$normalizedLeft$normalizedRight';
}
