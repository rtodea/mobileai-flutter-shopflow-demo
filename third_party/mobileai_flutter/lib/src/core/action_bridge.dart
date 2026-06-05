import 'package:flutter/widgets.dart';

typedef BlockActionHandler = Future<void> Function(Map<String, dynamic> payload);

class ActionBridgeController {
  final Map<String, BlockActionHandler> _handlers;

  const ActionBridgeController(this._handlers);

  Future<void> dispatch(String actionId, [Map<String, dynamic> payload = const {}]) async {
    final handler = _handlers[actionId];
    if (handler == null) {
      throw ArgumentError('No block action handler registered for "$actionId".');
    }
    await handler(payload);
  }
}

class ActionBridge extends InheritedWidget {
  final ActionBridgeController controller;

  const ActionBridge({
    super.key,
    required this.controller,
    required super.child,
  });

  static ActionBridgeController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ActionBridge>()?.controller;
  }

  static ActionBridgeController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No ActionBridge found in context');
    return controller!;
  }

  @override
  bool updateShouldNotify(ActionBridge oldWidget) => controller != oldWidget.controller;
}
