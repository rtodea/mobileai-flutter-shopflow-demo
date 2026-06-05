import 'package:flutter/widgets.dart';

import '../core/types.dart';
import 'types.dart';

class KeyboardTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'keyboard',
    description: 'Dismiss or hide the on-screen keyboard.',
    effect: ToolEffect.select,
    parameters: {},
    handler: (args) => throw UnimplementedError(),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode != null && focusNode.hasFocus) {
      focusNode.unfocus();
      return 'Keyboard dismissed.';
    }
    return 'Keyboard was not open.';
  }
}
