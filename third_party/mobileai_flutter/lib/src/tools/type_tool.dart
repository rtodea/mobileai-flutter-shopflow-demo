import 'package:flutter/material.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

class TypeTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'type',
    description: 'Type text into a text-input element by its index.',
    effect: ToolEffect.fill,
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The geometric index of the text input to type into',
      ),
      'text': ToolParam(
        type: 'string',
        description: 'The exact string to type',
      ),
    },
    handler: (args) => throw UnimplementedError(),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final index = args['index'] as int?;
    final text = args['text'] as String?;

    if (index == null || text == null) {
      throw Exception('Missing required parameters: index, text');
    }

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'type',
    );

    if (target.type != ElementType.textInput) {
      throw Exception('Element [$index] ${target.label} is not a text input.');
    }

    try {
      if (target.element == null) {
        return 'Cannot type into [$index] ${target.label}: no widget reference available.';
      }
      final success = _performType(target.element!, text);
      if (!success) {
        return 'Failed to type into [$index] ${target.label}. It might be read-only.';
      }
      return 'Typed "$text" into [$index] ${target.label}.';
    } catch (e) {
      Logger.error('Type execution failed: $e');
      throw Exception('Failed to type text: $e');
    }
  }

  bool _performType(Element element, String text) {
    if (!element.mounted) return false;

    // Strategy 1: If it's a TextField with a controller, update it directly
    if (element.widget is TextField) {
      final controller = (element.widget as TextField).controller;
      if (controller != null) {
        controller.text = text;
        final onChanged = (element.widget as TextField).onChanged;
        if (onChanged != null) onChanged(text);
        return true;
      }
    }

    // Strategy 2: Find the underlying EditableTextState
    EditableTextState? editableState;
    void findEditableTextState(Element e) {
      if (editableState != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        editableState = e.state as EditableTextState;
        return;
      }
      e.visitChildElements(findEditableTextState);
    }

    findEditableTextState(element);

    if (editableState != null) {
      editableState!.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );

      // Also attempt to trigger onChanged manually if possible
      if (element.widget is TextFormField) {
        // FormFields manage their own state
        final state = element.findAncestorStateOfType<FormFieldState<String>>();
        if (state != null) {
          state.didChange(text);
        }
      }

      return true;
    }

    return false;
  }
}
