import 'package:flutter/widgets.dart';
import '../core/types.dart';
import '../core/action_registry.dart';

/// A declarative widget to register custom AI actions in the Widget tree.
/// Actions are registered on mount and unregistered on unmount.
class AIAction extends StatefulWidget {
  final ActionDefinition action;
  final Widget child;

  const AIAction({
    super.key,
    required this.action,
    required this.child,
  });

  @override
  State<AIAction> createState() => _AIActionState();
}

class _AIActionState extends State<AIAction> {
  @override
  void initState() {
    super.initState();
    actionRegistry.register(widget.action);
  }

  @override
  void didUpdateWidget(AIAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.name != widget.action.name) {
      actionRegistry.unregister(oldWidget.action.name);
      actionRegistry.register(widget.action);
    } else {
      // Re-register to update handler closure if changed
      actionRegistry.register(widget.action);
    }
  }

  @override
  void dispose() {
    actionRegistry.unregister(widget.action.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

@Deprecated('Use AIAction instead.')
typedef AiAction = AIAction;
