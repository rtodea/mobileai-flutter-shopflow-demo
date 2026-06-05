import 'package:flutter/widgets.dart';

import '../core/data_registry.dart';
import '../core/types.dart';

class AIData extends StatefulWidget {
  final DataDefinition definition;
  final Widget child;

  const AIData({
    super.key,
    required this.definition,
    required this.child,
  });

  @override
  State<AIData> createState() => _AIDataState();
}

class _AIDataState extends State<AIData> {
  @override
  void initState() {
    super.initState();
    dataRegistry.register(widget.definition);
  }

  @override
  void didUpdateWidget(AIData oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition.name != widget.definition.name) {
      dataRegistry.unregister(oldWidget.definition.name);
    }
    dataRegistry.register(widget.definition);
  }

  @override
  void dispose() {
    dataRegistry.unregister(widget.definition.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

@Deprecated('Use AIData instead.')
typedef AiData = AIData;
