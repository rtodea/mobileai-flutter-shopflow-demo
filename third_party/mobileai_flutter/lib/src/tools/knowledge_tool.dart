import '../core/types.dart';
import '../services/knowledge_base_service.dart';
import '../utils/logger.dart';
import 'types.dart';

/// KnowledgeTool — Query the knowledge base for domain-specific information.
///
/// This tool enables RAG (Retrieval Augmented Generation) capabilities
/// by providing domain knowledge to the AI agent.
class KnowledgeTool implements AgentTool {
  final KnowledgeBaseService knowledgeService;
  final String Function() getCurrentScreenName;

  KnowledgeTool({
    required this.knowledgeService,
    required this.getCurrentScreenName,
  });

  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'query_knowledge',
    description:
        'Query the knowledge base for domain-specific information. Use this to get answers about business rules, product information, policies, or other domain knowledge.',
    effect: ToolEffect.read,
    parameters: {
      'question': ToolParam(
        type: 'string',
        description: 'The question to ask the knowledge base',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    // Validate parameters
    final question = args['question'] as String?;
    if (question == null || question.trim().isEmpty) {
      throw Exception('Missing required parameter: question');
    }

    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      throw Exception('Question cannot be empty');
    }

    // Get current screen name for context-aware retrieval
    final screenName = getCurrentScreenName();

    try {
      Logger.info(
        'Querying knowledge base for: "$trimmedQuestion" on screen: $screenName',
      );

      // Query the knowledge service
      final result = await knowledgeService.retrieve(
        trimmedQuestion,
        screenName,
      );

      Logger.info('Knowledge base query completed');
      return result;
    } catch (e) {
      Logger.error('Knowledge base query failed: $e');
      return 'Knowledge base query failed: $e. Please answer based on what is visible on screen.';
    }
  }
}
