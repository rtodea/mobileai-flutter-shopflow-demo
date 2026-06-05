import 'package:flutter/material.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import '../widgets/highlight_overlay.dart';
import 'types.dart';

class GuideTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'guide_user',
    description:
        'Highlight a specific element to draw the user\'s attention. Use when you want to show the user where to tap next. Auto-dismisses after a few seconds.',
    effect: ToolEffect.navigate,
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The element index to highlight',
      ),
      'message': ToolParam(
        type: 'string',
        description:
            'Short instruction shown near the highlighted element (e.g. "Tap here to continue")',
      ),
      'autoRemoveAfterMs': ToolParam(
        type: 'integer',
        description: 'Auto-dismiss after this many milliseconds. Default: 5000',
        required: false,
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final index = args['index'] as int?;
    final message = args['message'] as String?;
    final autoRemoveAfterMs = args['autoRemoveAfterMs'] as int? ?? 5000;

    if (index == null || message == null) {
      throw Exception('Missing required parameters: index, message');
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw Exception('Message cannot be empty');
    }

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'guide_user',
    );

    if (target.element == null || !target.element!.mounted) {
      throw Exception(
        'Cannot guide to [$index]: no widget reference available for positioning.',
      );
    }

    final renderObject = target.element!.findRenderObject();
    if (renderObject is! RenderBox) {
      throw Exception(
        'Element [$index] is not a RenderBox, cannot determine position.',
      );
    }

    // Scroll element into view first
    try {
      await Scrollable.ensureVisible(
        target.element!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}

    final position = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.paintBounds.size;

    Logger.info(
      'Guiding user to [$index] ${target.label} at ${position.dx},${position.dy}',
    );

    HighlightController.show(HighlightEventData(
      pageX: position.dx,
      pageY: position.dy,
      width: size.width,
      height: size.height,
      message: trimmedMessage,
      action: HighlightAction.read,
      autoRemoveAfterMs: autoRemoveAfterMs,
    ));

    return 'Guiding user to [$index] ${target.label}: "$trimmedMessage"';
  }
}
