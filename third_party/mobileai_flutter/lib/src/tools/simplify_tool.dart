import '../core/action_bridge.dart';
import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// Simplify an AI zone by hiding low-priority content.
class SimplifyTool implements AgentTool {
  final ActionBridgeController actionBridge;

  const SimplifyTool({required this.actionBridge});

  @override
  ToolDefinition get definition => ToolDefinition(
        name: 'simplify_zone',
        description:
            'Simplify an AI zone to reduce visual clutter and focus the user on the immediate task.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The id of the AI zone to simplify',
            required: true,
          ),
        },
        handler: (args) async => 'simplify_zone',
      );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final zoneId = (args['zoneId'] as String?)?.trim();
    if (zoneId == null || zoneId.isEmpty) {
      throw ArgumentError('zoneId is required');
    }

    Logger.info('[SimplifyTool] Simplifying zone "$zoneId"');
    await actionBridge.dispatch('simplify_zone', {'zoneId': zoneId});
    return 'Simplified zone "$zoneId".';
  }
}
