import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../core/types.dart';
import '../utils/logger.dart';

const _agentStepFn = 'agent_step';

class GeminiProvider implements AiProvider {
  final String _apiKey;
  final String modelName;
  final String? _proxyUrl;
  final Map<String, String>? _proxyHeaders;
  final http.Client _httpClient;

  GeminiProvider({
    String? apiKey,
    this.modelName = 'gemini-2.5-flash',
    String? proxyUrl,
    Map<String, String>? proxyHeaders,
    http.Client? httpClient,
  })  : _proxyUrl = proxyUrl,
        _proxyHeaders = proxyHeaders,
        _httpClient = httpClient ?? http.Client(),
        _apiKey = proxyUrl != null && proxyUrl.isNotEmpty ? 'proxy-key' : (apiKey ?? '') {
    if ((apiKey == null || apiKey.isEmpty) && (proxyUrl == null || proxyUrl.isEmpty)) {
      throw Exception(
        '[mobileai_flutter] You must provide either an "apiKey" or "proxyUrl" to AIAgent.',
      );
    }
  }

  @override
  Future<ProviderResult> generateContent({
    required String systemPrompt,
    required String userMessage,
    required List<ToolDefinition> tools,
    required List<AgentStep> history,
    String? screenshotBase64,
    List<UserImage>? userImages,
  }) async {
    Logger.info(
      'Sending request to Gemini. Model: $modelName, Tools: ${tools.length}'
      '${screenshotBase64 != null ? " with screenshot" : ""}'
      '${userImages != null && userImages.isNotEmpty ? " with ${userImages.length} user image(s)" : ""}',
    );

    final proxyUrl = _proxyUrl;
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      return _generateViaProxy(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        tools: tools,
        history: history,
        screenshotBase64: screenshotBase64,
        userImages: userImages,
      );
    }

    final contentParts = <Part>[];
    
    // 1. Build chat history — mirrors RN format:
    // <agent_history>
    // <step_N>
    // Previous Goal Eval: ...
    // Memory: ...
    // Plan: ...
    // Action: tool_name
    // Action Result: tool output
    // </step_N>
    // </agent_history>
    if (history.isNotEmpty) {
      final historyBuffer = StringBuffer();
      historyBuffer.writeln('<agent_history>');
      for (var i = 0; i < history.length; i++) {
        final step = history[i];
        // Virtual summary step — emit its content directly
        if (step.actionName == '__summary__' && step.result != null) {
          historyBuffer.writeln(step.result);
          continue;
        }
        historyBuffer.writeln('<step_$i>');
        if (step.reasoning != null) {
          historyBuffer.writeln('Previous Goal Eval: ${step.reasoning!.previousGoalEval}');
          historyBuffer.writeln('Memory: ${step.reasoning!.memory}');
          historyBuffer.writeln('Plan: ${step.reasoning!.plan}');
        }
        historyBuffer.writeln('Action: ${step.actionName}');
        if (step.error != null) {
          historyBuffer.writeln('Action Result: Error — ${step.error}');
        } else if (step.result != null && step.result!.isNotEmpty) {
          historyBuffer.writeln('Action Result: ${step.result}');
        }
        historyBuffer.writeln('</step_$i>');
      }
      historyBuffer.writeln('</agent_history>');
      contentParts.add(TextPart(historyBuffer.toString()));
    }

    // 2. System prompt + user request (clean, no noisy toolDescriptions in userMessage)
    // The system prompt is injected via GenerativeModel's systemInstruction per-call below.
    contentParts.add(TextPart(userMessage));

    // 3. Add Optional Screenshot
    if (screenshotBase64 != null) {
      try {
        final uriData = UriData.parse(screenshotBase64);
        contentParts.add(DataPart(
          uriData.mimeType,
          uriData.contentAsBytes(),
        ));
      } catch (e) {
        // Fallback if it's just raw base64 without prefix
        contentParts.add(DataPart('image/jpeg', base64Decode(screenshotBase64)));
      }
    }

    // 4. Add User Images
    if (userImages != null && userImages.isNotEmpty) {
      for (final img in userImages) {
        contentParts.add(DataPart(img.mimeType, base64Decode(img.base64)));
      }
      contentParts.add(TextPart(
        '\n[The user attached the above image(s) to their message. '
        'Describe what you see if relevant to their request.]',
      ));
    }

    final agentStepDeclaration = _buildAgentStepDeclaration(tools);
    final startTime = DateTime.now();

    // Build a per-request model with system prompt injected
    final requestModel = GenerativeModel(
      model: modelName,
      apiKey: _apiKey,
      httpClient: _proxyUrl == null || _proxyUrl.isEmpty
          ? null
          : _ProxyHttpClient(
              baseUri: Uri.parse(_proxyUrl),
              headers: _proxyHeaders,
            ),
      systemInstruction: Content.system(systemPrompt),
    );

    try {
      final response = await requestModel.generateContent(
        [Content('user', contentParts)],
        generationConfig: GenerationConfig(
          temperature: 0.2,
          maxOutputTokens: 2048,
        ),
        tools: [
          Tool(functionDeclarations: [agentStepDeclaration])
        ],
        toolConfig: ToolConfig(
          functionCallingConfig: FunctionCallingConfig(
            mode: FunctionCallingMode.any,
            allowedFunctionNames: {_agentStepFn},
          ),
        ),
      );

      final elapsed = DateTime.now().difference(startTime);
      Logger.info('Response received in ${elapsed.inMilliseconds}ms');

      return _parseAgentStepResponse(response, tools);
    } catch (e) {
      Logger.error('Gemini Request failed: $e');
      rethrow;
    }
  }

  Future<ProviderResult> _generateViaProxy({
    required String systemPrompt,
    required String userMessage,
    required List<ToolDefinition> tools,
    required List<AgentStep> history,
    String? screenshotBase64,
    List<UserImage>? userImages,
  }) async {
    final proxyUrl = _proxyUrl;
    if (proxyUrl == null || proxyUrl.isEmpty) {
      throw Exception('Gemini proxy URL is missing.');
    }

    final endpoint = Uri.parse(proxyUrl).replace(
      path: _joinProxyPaths(
        Uri.parse(proxyUrl).path,
        '/v1beta/models/$modelName:generateContent',
      ),
    );

    final response = await _httpClient
        .post(
          endpoint,
          headers: <String, String>{
            'Content-Type': 'application/json',
            ...?_proxyHeaders,
          },
          body: jsonEncode(
            _buildGeminiRequestBody(
              systemPrompt: systemPrompt,
              userMessage: userMessage,
              tools: tools,
              history: history,
              screenshotBase64: screenshotBase64,
              userImages: userImages,
            ),
          ),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception(
            'Gemini proxy request timed out after 30 seconds.',
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Parse proxy error codes for user-friendly messages
      try {
        final errData = jsonDecode(response.body) as Map<String, dynamic>;
        final code = errData['code'] as String? ?? '';
        if (code == 'session_token_budget_exhausted') {
          throw Exception('Session token limit reached. Please start a new conversation.');
        }
        if (code == 'budget_exhausted' || code == 'proxy_blocked') {
          throw Exception('This project has run out of AI credits. Add more credits in the MobileAI dashboard to continue.');
        }
        if (code == 'token_rate_limited' || code == 'device_rate_limited') {
          throw Exception('You\'re sending messages too quickly. Please wait a moment and try again.');
        }
        if (code == 'provider_rate_limited') {
          throw Exception('The AI service is busy. Please wait a moment and try again.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Session token limit')) rethrow;
        if (e is Exception && e.toString().contains('run out of AI credits')) rethrow;
        if (e is Exception && e.toString().contains('too quickly')) rethrow;
        if (e is Exception && e.toString().contains('AI service is busy')) rethrow;
      }
      throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = _parseAgentStepJsonResponse(data, tools);
    return ProviderResult(
      actionName: result.actionName,
      actionParams: result.actionParams,
      reasoning: result.reasoning,
      text: result.text,
      tokenUsage: _extractTokenUsage(data),
      rawResponse: data,
    );
  }

  String _joinProxyPaths(String basePath, String relativePath) {
    if (basePath.isEmpty || basePath == '/') {
      return relativePath.startsWith('/') ? relativePath : '/$relativePath';
    }
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final normalizedRelative = relativePath.startsWith('/')
        ? relativePath
        : '/$relativePath';
    return '$normalizedBase$normalizedRelative';
  }

  Map<String, dynamic> _buildGeminiRequestBody({
    required String systemPrompt,
    required String userMessage,
    required List<ToolDefinition> tools,
    required List<AgentStep> history,
    String? screenshotBase64,
    List<UserImage>? userImages,
  }) {
    final contentParts = <Map<String, dynamic>>[];

    if (history.isNotEmpty) {
      final historyBuffer = StringBuffer();
      historyBuffer.writeln('<agent_history>');
      for (var i = 0; i < history.length; i++) {
        final step = history[i];
        if (step.actionName == '__summary__' && step.result != null) {
          historyBuffer.writeln(step.result);
          continue;
        }
        historyBuffer.writeln('<step_$i>');
        if (step.reasoning != null) {
          historyBuffer.writeln(
            'Previous Goal Eval: ${step.reasoning!.previousGoalEval}',
          );
          historyBuffer.writeln('Memory: ${step.reasoning!.memory}');
          historyBuffer.writeln('Plan: ${step.reasoning!.plan}');
        }
        historyBuffer.writeln('Action: ${step.actionName}');
        if (step.error != null) {
          historyBuffer.writeln('Action Result: Error — ${step.error}');
        } else if (step.result != null && step.result!.isNotEmpty) {
          historyBuffer.writeln('Action Result: ${step.result}');
        }
        historyBuffer.writeln('</step_$i>');
      }
      historyBuffer.writeln('</agent_history>');
      contentParts.add(<String, dynamic>{'text': historyBuffer.toString()});
    }

    contentParts.add(<String, dynamic>{'text': userMessage});

    if (screenshotBase64 != null && screenshotBase64.isNotEmpty) {
      String mimeType = 'image/jpeg';
      String data = screenshotBase64;
      if (screenshotBase64.startsWith('data:')) {
        final uri = UriData.parse(screenshotBase64);
        mimeType = uri.mimeType;
        data = base64Encode(uri.contentAsBytes());
      }
      contentParts.add(<String, dynamic>{
        'inlineData': <String, dynamic>{'mimeType': mimeType, 'data': data},
      });
    }

    if (userImages != null && userImages.isNotEmpty) {
      for (final img in userImages) {
        contentParts.add(<String, dynamic>{
          'inlineData': <String, dynamic>{
            'mimeType': img.mimeType,
            'data': img.base64,
          },
        });
      }
      contentParts.add(<String, dynamic>{
        'text':
            '\n[The user attached the above image(s) to their message. '
            'Describe what you see if relevant to their request.]',
      });
    }

    return <String, dynamic>{
      'system_instruction': <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': systemPrompt},
        ],
      },
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'parts': contentParts},
      ],
      'generationConfig': <String, dynamic>{
        'temperature': 0.2,
        'maxOutputTokens': 2048,
      },
      'tools': <Map<String, dynamic>>[
        <String, dynamic>{
          'functionDeclarations': <Map<String, dynamic>>[
            _buildAgentStepDeclarationJson(tools),
          ],
        },
      ],
      'toolConfig': <String, dynamic>{
        'functionCallingConfig': <String, dynamic>{
          'mode': 'ANY',
          'allowedFunctionNames': <String>[_agentStepFn],
        },
      },
    };
  }

  Map<String, dynamic> _buildAgentStepDeclarationJson(
    List<ToolDefinition> tools,
  ) {
    final toolNames = tools.map((t) => t.name).toList(growable: false);

    final toolDescriptions = tools.map((t) {
      final params = t.parameters.keys.toList();
      final inputGuide = params.isEmpty
          ? 'Use {} for action_input.'
          : 'Provide action_input as a JSON object string with keys: ${params.join(', ')}.';
      return '- ${t.name}: ${t.description} $inputGuide';
    }).join('\n');

    return <String, dynamic>{
      'name': _agentStepFn,
      'description':
          'Execute one agent step. Choose an action and provide reasoning.\n\nAvailable actions:\n$toolDescriptions',
      'parameters': <String, dynamic>{
        'type': 'OBJECT',
        'properties': <String, dynamic>{
          'previous_goal_eval': <String, dynamic>{
            'type': 'STRING',
            'description':
                'One-sentence assessment of your last action. State success, failure, or uncertain. Skip on first step.',
          },
          'memory': <String, dynamic>{
            'type': 'STRING',
            'description':
                'Key facts to remember for future steps: progress made, items found, counters, field values already collected.',
          },
          'plan': <String, dynamic>{
            'type': 'STRING',
            'description': 'Your immediate next goal — what action you will take and why.',
          },
          'action_name': <String, dynamic>{
            'type': 'STRING',
            'description': 'Which action to execute. Must be one of: ${toolNames.join(', ')}.',
          },
          'action_input': <String, dynamic>{
            'type': 'STRING',
            'description':
                'JSON object string containing only the arguments for action_name. Use "{}" when the action takes no parameters.',
          },
        },
        'required': <String>['plan', 'action_name'],
      },
    };
  }

  /// Builds a narrow schema with action_input as a JSON string instead of
  /// flattening every tool parameter into top-level properties. Flattening
  /// triggers Gemini's "too much branching for serving" error once the
  /// toolset grows beyond ~10 tools.
  FunctionDeclaration _buildAgentStepDeclaration(List<ToolDefinition> tools) {
    final toolNames = tools.map((t) => t.name).toList();

    final toolDescriptions = tools.map((t) {
      final params = t.parameters.keys.toList();
      final inputGuide = params.isEmpty
          ? 'Use {} for action_input.'
          : 'Provide action_input as a JSON object string with keys: ${params.join(', ')}.';
      return '- ${t.name}: ${t.description} $inputGuide';
    }).join('\n');

    return FunctionDeclaration(
      _agentStepFn,
      'Execute one agent step. Choose an action and provide reasoning.\n\nAvailable actions:\n$toolDescriptions',
      Schema.object(
        properties: {
          'previous_goal_eval': Schema.string(
            description: 'One-sentence assessment of your last action. State success, failure, or uncertain. Skip on first step.',
          ),
          'memory': Schema.string(
            description: 'Key facts to remember for future steps: progress made, items found, counters, field values already collected.',
          ),
          'plan': Schema.string(
            description: 'Your immediate next goal — what action you will take and why.',
          ),
          'action_name': Schema.string(
            description: 'Which action to execute. Must be one of: ${toolNames.join(', ')}.',
          ),
          'action_input': Schema.string(
            description: 'JSON object string containing only the arguments for action_name. Use "{}" when the action takes no parameters.',
          ),
        },
        requiredProperties: ['plan', 'action_name'],
      ),
    );
  }

  ProviderResult _parseAgentStepResponse(GenerateContentResponse response, List<ToolDefinition> tools) {
    final functionCalls = response.functionCalls;
    if (functionCalls.isEmpty) {
      final text = _normalizeProviderText(response.text);
      Logger.warn(
        'Gemini SDK response did not include a function call. '
        'text=${text.isEmpty ? '(empty)' : text}',
      );
      return _buildFallbackProviderResult(
        text: text.isNotEmpty ? text : _friendlyEmptyResponseMessage(),
        rawResponse: response,
      );
    }

    final call = functionCalls.first;
    if (call.name != _agentStepFn) {
      throw Exception('Model called unexpected function: ${call.name}');
    }

    final args = call.args;
    final actionName = args['action_name'] as String?;

    if (actionName == null) {
      throw Exception('Model omitted action_name in agent_step call.');
    }

    final reasoning = AgentReasoning(
      previousGoalEval: args['previous_goal_eval'] as String? ?? '',
      memory: args['memory'] as String? ?? '',
      plan: args['plan'] as String? ?? '',
    );

    final toolParams = _parseActionInput(args['action_input'], actionName, tools);

    return ProviderResult(
      actionName: actionName,
      actionParams: toolParams,
      reasoning: reasoning,
      tokenUsage: TokenUsage(promptTokens: 0, completionTokens: 0, estimatedCostUSD: 0),
    );
  }

  ProviderResult _parseAgentStepJsonResponse(
    Map<String, dynamic> response,
    List<ToolDefinition> tools,
  ) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      Logger.warn('Gemini proxy response did not include candidates.');
      return _buildFallbackProviderResult(
        text: _friendlyEmptyResponseMessage(),
        rawResponse: response,
      );
    }

    Map<String, dynamic>? functionCall;
    String text = '';
    String? finishReason;

    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) {
        continue;
      }

      finishReason ??= candidate['finishReason'] as String?;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'];
      if (parts is! List || parts.isEmpty) {
        continue;
      }

      for (final part in parts) {
        if (part is! Map<String, dynamic>) {
          continue;
        }
        if (functionCall == null && part['functionCall'] is Map<String, dynamic>) {
          functionCall = part['functionCall'] as Map<String, dynamic>;
        }
        if (text.isEmpty) {
          text = _normalizeProviderText(part['text']);
        }
        if (functionCall != null) {
          break;
        }
      }

      if (functionCall != null) {
        break;
      }
    }

    if (functionCall == null) {
      final fallbackText = text.isNotEmpty
          ? text
          : _friendlyEmptyResponseMessage(finishReason: finishReason);
      Logger.warn(
        'Gemini proxy response did not include a function call. '
        'finishReason=${finishReason ?? '(unknown)'}, text=${text.isEmpty ? '(empty)' : text}',
      );
      return _buildFallbackProviderResult(
        text: fallbackText,
        rawResponse: response,
      );
    }

    final callName = functionCall['name'] as String?;
    if (callName != _agentStepFn) {
      throw Exception('Model called unexpected function: $callName');
    }

    final args = (functionCall['args'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final actionName = args['action_name'] as String?;
    if (actionName == null) {
      throw Exception('Model omitted action_name in agent_step call.');
    }

    final reasoning = AgentReasoning(
      previousGoalEval: args['previous_goal_eval'] as String? ?? '',
      memory: args['memory'] as String? ?? '',
      plan: args['plan'] as String? ?? '',
    );

    final toolParams = _parseActionInput(args['action_input'], actionName, tools);

    return ProviderResult(
      actionName: actionName,
      actionParams: toolParams,
      reasoning: reasoning,
      tokenUsage: _extractTokenUsage(response),
      rawResponse: response,
    );
  }

  /// Parse `action_input` — a JSON string of tool arguments.
  /// Falls back to extracting flat keys from args for backward compat.
  Map<String, dynamic> _parseActionInput(
    dynamic actionInput,
    String actionName,
    List<ToolDefinition> tools,
  ) {
    if (actionInput is String && actionInput.isNotEmpty) {
      try {
        final parsed = jsonDecode(actionInput);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {
        Logger.warn('Failed to parse action_input JSON: $actionInput');
      }
    }
    // If action_input is already a Map (Gemini sometimes returns structured)
    if (actionInput is Map) {
      return Map<String, dynamic>.from(actionInput);
    }
    return <String, dynamic>{};
  }

  ProviderResult _buildFallbackProviderResult({
    required String text,
    Object? rawResponse,
  }) {
    final normalizedText = _normalizeProviderText(text);
    final message = normalizedText.isNotEmpty
        ? normalizedText
        : _friendlyEmptyResponseMessage();

    return ProviderResult(
      actionName: 'done',
      actionParams: <String, dynamic>{
        'text': message,
        'success': false,
      },
      reasoning: AgentReasoning(
        previousGoalEval: '',
        memory: '',
        plan: '',
      ),
      text: message,
      rawResponse: rawResponse,
    );
  }

  String _friendlyEmptyResponseMessage({String? finishReason}) {
    switch (finishReason) {
      case 'SAFETY':
        return 'The AI response was blocked for safety. Please try rephrasing the request.';
      case 'MAX_TOKENS':
        return 'The AI response was cut off before it could finish. Please try again.';
      case 'MALFORMED_FUNCTION_CALL':
        return 'The AI response was incomplete. Please try again.';
      default:
        return 'The AI response was empty. Please try again.';
    }
  }

  String _normalizeProviderText(dynamic value) {
    if (value is! String) {
      return '';
    }
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  TokenUsage _extractTokenUsage(Map<String, dynamic> data) {
    final usage = data['usageMetadata'] as Map<String, dynamic>?;
    final promptTokens = (usage?['promptTokenCount'] as num?)?.toInt() ?? 0;
    final completionTokens =
        (usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0;
    final totalTokens =
        (usage?['totalTokenCount'] as num?)?.toInt() ??
        (promptTokens + completionTokens);
    return TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      estimatedCostUSD: 0,
    );
  }
}

class _ProxyHttpClient extends http.BaseClient {
  final Uri baseUri;
  final Map<String, String>? headers;
  final http.Client _inner;

  _ProxyHttpClient({
    required this.baseUri,
    this.headers,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final relativePath = request.url.path.startsWith('/')
        ? request.url.path.substring(1)
        : request.url.path;
    final queryParameters = <String, String>{
      ...baseUri.queryParameters,
      ...request.url.queryParameters,
    };
    final rewrittenUri = baseUri.replace(
      path: _joinPaths(baseUri.path, relativePath),
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );

    final replacement = http.StreamedRequest(request.method, rewrittenUri)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..contentLength = request.contentLength
      ..headers.addAll(request.headers)
      ..headers.addAll(headers ?? const <String, String>{});

    final bodyBytes = await request.finalize().toBytes();
    replacement.sink.add(bodyBytes);
    await replacement.sink.close();

    return _inner.send(replacement);
  }

  String _joinPaths(String basePath, String relativePath) {
    if (basePath.isEmpty || basePath == '/') {
      return '/$relativePath';
    }
    final normalizedBase = basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
    return '$normalizedBase/$relativePath';
  }
}
