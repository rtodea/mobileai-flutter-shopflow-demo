import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/types.dart';
import '../utils/logger.dart';

const _agentStepFn = 'agent_step';
const _openAiApiUrl = 'https://api.openai.com/v1/chat/completions';

class OpenAIProvider implements AiProvider {
  final String modelName;
  final Uri _endpoint;
  final Map<String, String> _headers;
  final http.Client _httpClient;

  OpenAIProvider({
    String? apiKey,
    this.modelName = 'gpt-4.1-mini',
    String? proxyUrl,
    Map<String, String>? proxyHeaders,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _endpoint = _resolveEndpoint(proxyUrl),
        _headers = _resolveHeaders(apiKey: apiKey, proxyUrl: proxyUrl, proxyHeaders: proxyHeaders);

  static Uri _resolveEndpoint(String? proxyUrl) {
    if (proxyUrl == null || proxyUrl.isEmpty) {
      return Uri.parse(_openAiApiUrl);
    }
    return Uri.parse(proxyUrl.endsWith('/') ? '${proxyUrl}v1/chat/completions' : proxyUrl);
  }

  static Map<String, String> _resolveHeaders({
    required String? apiKey,
    required String? proxyUrl,
    required Map<String, String>? proxyHeaders,
  }) {
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      return <String, String>{
        'Content-Type': 'application/json',
        ...?proxyHeaders,
      };
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      return <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };
    }
    throw Exception(
      '[mobileai_flutter] You must provide either "apiKey" or "proxyUrl" to use the OpenAI provider.',
    );
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
      'Sending request to OpenAI. Model: $modelName, Tools: ${tools.length}'
      '${screenshotBase64 != null ? " with screenshot" : ""}'
      '${userImages != null && userImages.isNotEmpty ? " with ${userImages.length} user image(s)" : ""}',
    );

    final response = await _httpClient.post(
      _endpoint,
      headers: _headers,
      body: jsonEncode(
        <String, dynamic>{
          'model': modelName,
          'messages': _buildMessages(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            screenshotBase64: screenshotBase64,
            history: history,
            userImages: userImages,
          ),
          'tools': <Object>[_buildAgentStepTool(tools)],
          'tool_choice': 'required',
          'temperature': 0.2,
          'max_tokens': 2048,
        },
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OpenAI API error ${response.statusCode}: ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = _parseAgentStepResponse(data, tools);
    return ProviderResult(
      actionName: result.actionName,
      actionParams: result.actionParams,
      reasoning: result.reasoning,
      text: result.text,
      tokenUsage: _extractTokenUsage(data),
      rawResponse: data,
    );
  }

  Map<String, dynamic> _buildAgentStepTool(List<ToolDefinition> tools) {
    final toolNames = tools.map((tool) => tool.name).toList(growable: false);
    final properties = <String, dynamic>{
      'previous_goal_eval': <String, dynamic>{
        'type': 'string',
        'description':
            'One-sentence assessment of your last action. State success, failure, or uncertain. Skip on first step.',
      },
      'memory': <String, dynamic>{
        'type': 'string',
        'description':
            'Key facts to remember for future steps: progress made, items found, counters, field values already collected.',
      },
      'plan': <String, dynamic>{
        'type': 'string',
        'description': 'Your immediate next goal — what action you will take and why.',
      },
      'action_name': <String, dynamic>{
        'type': 'string',
        'description': 'Which action to execute.',
        'enum': toolNames,
      },
    };

    for (final tool in tools) {
      for (final entry in tool.parameters.entries) {
        properties.putIfAbsent(
          entry.key,
          () => <String, dynamic>{
            'type': _normalizeJsonSchemaType(entry.value.type),
            'description': entry.value.description,
            if (entry.value.enumValues != null && entry.value.enumValues!.isNotEmpty)
              'enum': entry.value.enumValues,
          },
        );
      }
    }

    final descriptions = tools
        .map((tool) {
          final params = tool.parameters.keys.join(', ');
          return '- ${tool.name}(${params.isEmpty ? '' : params}): ${tool.description}';
        })
        .join('\n');

    return <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': _agentStepFn,
        'description':
            'Execute one agent step. Choose an action and provide reasoning.\n\nAvailable actions:\n$descriptions',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': properties,
          'required': properties.keys.toList(growable: false),
          'additionalProperties': false,
        },
        'strict': true,
      },
    };
  }

  List<Map<String, dynamic>> _buildMessages({
    required String systemPrompt,
    required String userMessage,
    required List<AgentStep> history,
    String? screenshotBase64,
    List<UserImage>? userImages,
  }) {
    final messages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemPrompt},
    ];

    if (history.isNotEmpty) {
      final historyBuffer = StringBuffer('<agent_history>\n');
      for (var i = 0; i < history.length; i++) {
        final step = history[i];
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
      historyBuffer.write('</agent_history>');
      messages.add(<String, dynamic>{'role': 'user', 'content': historyBuffer.toString()});
    }

    final hasImages = screenshotBase64 != null ||
        (userImages != null && userImages.isNotEmpty);

    if (hasImages) {
      final contentParts = <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': userMessage},
      ];

      if (screenshotBase64 != null && screenshotBase64.isNotEmpty) {
        final imageData = screenshotBase64.startsWith('data:')
            ? screenshotBase64
            : 'data:image/jpeg;base64,$screenshotBase64';
        contentParts.add(<String, dynamic>{
          'type': 'image_url',
          'image_url': <String, dynamic>{'url': imageData, 'detail': 'low'},
        });
      }

      if (userImages != null && userImages.isNotEmpty) {
        for (final img in userImages) {
          final imageData = 'data:${img.mimeType};base64,${img.base64}';
          contentParts.add(<String, dynamic>{
            'type': 'image_url',
            'image_url': <String, dynamic>{'url': imageData, 'detail': 'low'},
          });
        }
        contentParts.add(<String, dynamic>{
          'type': 'text',
          'text':
              '\n[The user attached the above image(s) to their message. '
              'Describe what you see if relevant to their request.]',
        });
      }

      messages.add(<String, dynamic>{'role': 'user', 'content': contentParts});
    } else {
      messages.add(<String, dynamic>{'role': 'user', 'content': userMessage});
    }

    return messages;
  }

  ProviderResult _parseAgentStepResponse(
    Map<String, dynamic> data,
    List<ToolDefinition> tools,
  ) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return ProviderResult(
        actionName: 'done',
        actionParams: const <String, dynamic>{
          'success': false,
          'text': 'No response generated.',
        },
        reasoning: AgentReasoning(),
        text: 'No response generated.',
      );
    }

    final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>? ?? const {};
    final toolCalls = message['tool_calls'];
    final text = message['content']?.toString();

    if (toolCalls is! List || toolCalls.isEmpty) {
      return ProviderResult(
        actionName: 'done',
        actionParams: <String, dynamic>{
          'success': false,
          'text': text ?? 'No action taken.',
        },
        reasoning: AgentReasoning(),
        text: text,
      );
    }

    final function = ((toolCalls.first as Map<String, dynamic>)['function'] as Map<String, dynamic>?);
    if (function == null || function['name'] != _agentStepFn) {
      return ProviderResult(
        actionName: 'done',
        actionParams: <String, dynamic>{
          'success': false,
          'text': text ?? 'Unexpected tool response.',
        },
        reasoning: AgentReasoning(),
        text: text,
      );
    }

    final rawArguments = function['arguments']?.toString() ?? '{}';
    final args = (jsonDecode(rawArguments) as Map).cast<String, dynamic>();
    final actionName = args['action_name']?.toString();
    final reasoning = AgentReasoning(
      previousGoalEval: args['previous_goal_eval']?.toString() ?? '',
      memory: args['memory']?.toString() ?? '',
      plan: args['plan']?.toString() ?? '',
    );

    if (actionName == null || actionName.isEmpty) {
      return ProviderResult(
        actionName: 'done',
        actionParams: const <String, dynamic>{
          'success': false,
          'text': 'Agent did not choose an action.',
        },
        reasoning: reasoning,
        text: text,
      );
    }

    final matchedTool = tools.where((tool) => tool.name == actionName).firstOrNull;
    final actionArgs = <String, dynamic>{};
    if (matchedTool != null) {
      for (final key in matchedTool.parameters.keys) {
        if (args.containsKey(key)) {
          actionArgs[key] = args[key];
        }
      }
    } else {
      for (final entry in args.entries) {
        if (entry.key == 'action_name' ||
            entry.key == 'previous_goal_eval' ||
            entry.key == 'memory' ||
            entry.key == 'plan') {
          continue;
        }
        actionArgs[entry.key] = entry.value;
      }
    }

    return ProviderResult(
      actionName: actionName,
      actionParams: actionArgs,
      reasoning: reasoning,
      text: text,
      rawResponse: data,
    );
  }

  TokenUsage? _extractTokenUsage(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage is! Map) return null;

    final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
    final completionTokens = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
    final totalTokens =
        (usage['total_tokens'] as num?)?.toInt() ?? promptTokens + completionTokens;

    const inputCostPerM = 0.4;
    const outputCostPerM = 1.6;
    final estimatedCostUsd =
        (promptTokens / 1000000) * inputCostPerM + (completionTokens / 1000000) * outputCostPerM;

    return TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      estimatedCostUSD: estimatedCostUsd,
    );
  }

  String _normalizeJsonSchemaType(String type) {
    switch (type) {
      case 'integer':
        return 'integer';
      case 'number':
        return 'number';
      case 'boolean':
        return 'boolean';
      default:
        return 'string';
    }
  }
}
