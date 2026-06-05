import '../core/types.dart';
import 'gemini_provider.dart';
import 'openai_provider.dart';

AiProvider createProvider({
  required AiProviderName provider,
  required String? apiKey,
  String? model,
  String? proxyUrl,
  Map<String, String>? proxyHeaders,
}) {
  switch (provider) {
    case AiProviderName.gemini:
      return GeminiProvider(
        apiKey: apiKey,
        modelName: model ?? 'gemini-2.5-flash',
        proxyUrl: proxyUrl,
        proxyHeaders: proxyHeaders,
      );
    case AiProviderName.openai:
      return OpenAIProvider(
        apiKey: apiKey,
        modelName: model ?? 'gpt-4.1-mini',
        proxyUrl: proxyUrl,
        proxyHeaders: proxyHeaders,
      );
  }
}
