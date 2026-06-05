import 'dart:convert';

import '../core/action_bridge.dart';
import '../core/block_registry.dart';
import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// Render a registered rich block into a zone.
class RenderBlockTool implements AgentTool {
  final ActionBridgeController actionBridge;
  final BlockRegistry blockRegistry;

  const RenderBlockTool({
    required this.actionBridge,
    required this.blockRegistry,
  });

  @override
  ToolDefinition get definition => ToolDefinition(
        name: 'render_block',
        description:
            'Render a registered rich block into a specific AI zone as a local intervention.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The target AI zone id',
            required: true,
          ),
          'blockType': ToolParam(
            type: 'string',
            description: 'The registered block type to render',
            required: true,
          ),
          'props': ToolParam(
            type: 'string',
            description: 'Optional JSON object props',
            required: false,
          ),
        },
        handler: (args) async => 'render_block',
      );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final zoneId = (args['zoneId'] as String?)?.trim();
    final blockType = (args['blockType'] as String?)?.trim();
    final props = _parseProps(args['props']);

    if (zoneId == null || zoneId.isEmpty) {
      throw ArgumentError('zoneId is required');
    }
    if (blockType == null || blockType.isEmpty) {
      throw ArgumentError('blockType is required');
    }

    final block = blockRegistry.get(blockType);
    if (block == null) {
      final available = blockRegistry.getAll().map((item) => item.name).join(', ');
      throw ArgumentError(
        'Unknown block type "$blockType". Available blocks: $available',
      );
    }

    Logger.info(
      '[RenderBlockTool] Rendering "$blockType" in zone "$zoneId" with props: $props',
    );
    await actionBridge.dispatch('render_block', {
      'zoneId': zoneId,
      'blockType': blockType,
      'props': props,
    });
    return 'Rendered "$blockType" in zone "$zoneId".';
  }

  Map<String, dynamic> _parseProps(dynamic rawProps) {
    if (rawProps == null) {
      return const <String, dynamic>{};
    }
    if (rawProps is Map<String, dynamic>) {
      return rawProps;
    }
    if (rawProps is Map) {
      return Map<String, dynamic>.from(rawProps);
    }
    if (rawProps is String) {
      final trimmed = rawProps.trim();
      if (trimmed.isEmpty) {
        return const <String, dynamic>{};
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw ArgumentError('props must decode to a JSON object');
    }
    throw ArgumentError('props must be a JSON string or object');
  }
}

/// Deprecated compatibility alias for render_block.
@Deprecated('Use render_block instead.')
class InjectCardTool implements AgentTool {
  final RenderBlockTool _delegate;

  InjectCardTool({
    required ActionBridgeController actionBridge,
    required BlockRegistry blockRegistry,
  }) : _delegate = RenderBlockTool(
          actionBridge: actionBridge,
          blockRegistry: blockRegistry,
        );

  @override
  ToolDefinition get definition => ToolDefinition(
        name: 'inject_card',
        description: 'Deprecated compatibility alias for render_block.',
        parameters: {
          'zoneId': ToolParam(
            type: 'string',
            description: 'The target AI zone id',
            required: true,
          ),
          'templateName': ToolParam(
            type: 'string',
            description: 'Legacy block/template name',
            required: true,
          ),
          'props': ToolParam(
            type: 'string',
            description: 'Optional JSON object props',
            required: false,
          ),
        },
        handler: (args) async => 'inject_card',
      );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) {
    return _delegate.execute({
      'zoneId': args['zoneId'],
      'blockType': args['templateName'],
      'props': args['props'],
    }, context);
  }
}
