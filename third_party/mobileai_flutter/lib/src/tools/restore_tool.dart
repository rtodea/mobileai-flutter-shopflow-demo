import '../core/action_bridge.dart';
import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// Restore a previously simplified or injected zone.
class RestoreTool implements AgentTool {
  final ActionBridgeController actionBridge;

  const RestoreTool({required this.actionBridge});

  @override
  ToolDefinition get definition => ToolDefinition(
        name: 'restore_zone',
        description:
            'Restore a specific AI zone to its default state after simplify or block injection.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The id of the AI zone to restore',
            required: true,
          ),
        },
        handler: (args) async => 'restore_zone',
      );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final zoneId = (args['zoneId'] as String?)?.trim();
    if (zoneId == null || zoneId.isEmpty) {
      throw ArgumentError('zoneId is required');
    }

    Logger.info('[RestoreTool] Restoring zone "$zoneId"');
    await actionBridge.dispatch('restore_zone', {'zoneId': zoneId});
    return 'Restored zone "$zoneId".';
  }
}
