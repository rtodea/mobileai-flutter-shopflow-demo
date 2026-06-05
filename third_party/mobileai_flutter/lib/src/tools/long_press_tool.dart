import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// LongPressTool — Long-press interactive elements to trigger context menus,
/// reordering, or secondary actions.
///
/// Uses a dual-strategy approach:
/// 1. SemanticsAction.longPress via SemanticsOwner (preferred)
/// 2. Direct widget callback invocation (onLongPress) as fallback
class LongPressTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'long_press',
    description:
        'Long-press an interactive element by its index. Use for actions that require a longer touch, such as showing context menus, reordering items, or triggering secondary actions.',
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The index of the element to long-press',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    // Validate parameters
    final index = args['index'] as int?;
    if (index == null) {
      throw Exception('Missing required parameter: index');
    }

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'long_press',
    );

    // Strategy 1: Dispatch via SemanticsOwner.performAction (preferred — works for
    // NavigationBar, Tab, and other widgets that use semantics)
    if (target.semanticsNodeId != null) {
      final owner = RendererBinding.instance.rootPipelineOwner.semanticsOwner;
      if (owner != null) {
        try {
          owner.performAction(
            target.semanticsNodeId!,
            SemanticsAction.longPress,
          );
          await Future.delayed(const Duration(milliseconds: 500));
          Logger.info('Executed SemanticsAction.longPress on [$index]');
          return 'Long-pressed [${target.index}] ${target.label} successfully.';
        } catch (e) {
          Logger.warn(
            'SemanticsAction.longPress failed for [$index]: $e — trying widget callback fallback',
          );
        }
      }
    }

    // Strategy 2: Widget callback fallback (for elements found via widget tree)
    if (target.element != null && target.element!.mounted) {
      final success = _performWidgetLongPress(target.element!);
      if (success) {
        await Future.delayed(const Duration(milliseconds: 500));
        Logger.info('Executed widget onLongPress callback on [$index]');
        return 'Long-pressed [${target.index}] ${target.label} successfully.';
      }
    }

    throw Exception(
      'Could not long-press [${target.index}] ${target.label}. Element may not have a long-press handler.',
    );
  }

  bool _performWidgetLongPress(dynamic targetElement) {
    final widget = targetElement.widget;

    // Try common long press callback patterns
    final matchers = [
      // Material Design components
      () {
        try {
          if (widget.onLongPress != null) {
            widget.onLongPress!();
            return true;
          }
        } catch (_) {}
        return false;
      },
      // ListTile-specific
      () {
        try {
          if (widget is ListTile && widget.onLongPress != null) {
            widget.onLongPress!();
            return true;
          }
        } catch (_) {}
        return false;
      },
      // IconButton-specific
      () {
        try {
          if (widget is IconButton && widget.onLongPress != null) {
            widget.onLongPress!();
            return true;
          }
        } catch (_) {}
        return false;
      },
    ];

    for (final matcher in matchers) {
      if (matcher()) return true;
    }
    return false;
  }
}
