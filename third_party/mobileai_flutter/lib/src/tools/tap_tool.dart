import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

class TapTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'tap',
    description: 'Tap an interactive element by its index.',
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The index of the element to tap',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final index = args['index'] as int?;
    if (index == null) {
      throw Exception('Missing required parameter: index');
    }

    Logger.info(
      '[TapTool] Attempting tap index=$index. '
      'available=${_summarizeElements(context.lastElements)}',
    );
    Logger.debug(
      '[TapTool] Full interactive list: ${_summarizeElements(context.lastElements, limit: context.lastElements.length)}',
    );

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'tap',
    );

    if (target.element != null && target.element!.mounted) {
      Logger.info(
        '[TapTool] Direct target widget=${target.element!.widget.runtimeType} '
        'label=${target.label} path=${_describeElementPath(target.element!)}',
      );
      final success = _performWidgetTap(target.element!, target);
      if (success) {
        return 'Tapped [${target.index}] ${target.label} successfully.';
      }
      Logger.warn(
        '[TapTool] Direct widget tap failed for [${target.index}] '
        '${target.label} on ${target.element!.widget.runtimeType}',
      );
    }

    if (target.semanticsNodeId != null) {
      final owner = RendererBinding.instance.rootPipelineOwner.semanticsOwner;
      if (owner != null) {
        try {
          owner.performAction(target.semanticsNodeId!, SemanticsAction.tap);
          return 'Tapped [${target.index}] ${target.label} successfully.';
        } catch (error) {
          Logger.warn(
            'SemanticsAction.tap failed for [${target.index}]: $error',
          );
        }
      }
    }

    final fallback = _findFallbackElement(
      context.rootContext as Element,
      target,
    );
    if (fallback != null) {
      Logger.info(
        '[TapTool] Found fallback widget=${fallback.widget.runtimeType} '
        'for [${target.index}] ${target.label} '
        'path=${_describeElementPath(fallback)}',
      );
      final success = _performWidgetTap(fallback, target);
      if (success) {
        return 'Tapped [${target.index}] ${target.label} successfully.';
      }
      Logger.warn(
        '[TapTool] Fallback widget tap failed for [${target.index}] '
        '${target.label} on ${fallback.widget.runtimeType}',
      );
    }

    Logger.warn(
      '[TapTool] Tap failed completely for [${target.index}] ${target.label}. '
      'targetWidget=${target.element?.widget.runtimeType ?? 'none'}, '
      'semanticsNodeId=${target.semanticsNodeId}',
    );
    throw Exception(
      'Could not tap [${target.index}] ${target.label}. Element may not be interactive.',
    );
  }

  bool _performWidgetTap(Element targetElement, InteractiveElement target) {
    final widget = targetElement.widget;
    final actionIndex = target.properties['actionIndex'] as int?;

    if (widget is BottomNavigationBar &&
        widget.onTap != null &&
        actionIndex != null) {
      widget.onTap!(actionIndex);
      return true;
    }

    if (widget is NavigationBar &&
        widget.onDestinationSelected != null &&
        actionIndex != null) {
      widget.onDestinationSelected!(actionIndex);
      return true;
    }

    if (widget is TabBar && actionIndex != null) {
      if (widget.onTap != null) {
        widget.onTap!(actionIndex);
        return true;
      }
      widget.controller?.animateTo(actionIndex);
      return widget.controller != null;
    }

    if (widget is ButtonStyleButton && widget.onPressed != null) {
      widget.onPressed!();
      return true;
    }

    if (widget is IconButton && widget.onPressed != null) {
      widget.onPressed!();
      return true;
    }

    if (widget is FloatingActionButton && widget.onPressed != null) {
      widget.onPressed!();
      return true;
    }

    if (widget is InkWell && widget.onTap != null) {
      widget.onTap!();
      return true;
    }

    if (widget is GestureDetector && widget.onTap != null) {
      widget.onTap!();
      return true;
    }

    if (widget is ListTile) {
      if (widget.onTap != null) {
        widget.onTap!();
        return true;
      }
      if (widget.onLongPress != null) {
        widget.onLongPress!();
        return true;
      }
    }

    if (widget is Switch && widget.onChanged != null) {
      widget.onChanged!(!widget.value);
      return true;
    }

    if (widget is SwitchListTile && widget.onChanged != null) {
      widget.onChanged!(!widget.value);
      return true;
    }

    if (widget is Checkbox && widget.onChanged != null) {
      widget.onChanged!(!(widget.value ?? false));
      return true;
    }

    if (widget is CheckboxListTile && widget.onChanged != null) {
      widget.onChanged!(!(widget.value ?? false));
      return true;
    }

    if (widget is Radio) {
      final dynamic dynamicWidget = widget;
      final onChanged = dynamicWidget.onChanged;
      if (onChanged != null) {
        onChanged(dynamicWidget.value);
        return true;
      }
    }

    if (widget is RadioListTile) {
      final dynamic dynamicWidget = widget;
      final onChanged = dynamicWidget.onChanged;
      if (onChanged != null) {
        onChanged(dynamicWidget.value);
        return true;
      }
    }

    if (widget is FilterChip && widget.onSelected != null) {
      widget.onSelected!(!widget.selected);
      return true;
    }

    if (widget is ChoiceChip && widget.onSelected != null) {
      widget.onSelected!(!widget.selected);
      return true;
    }

    if (widget is ActionChip && widget.onPressed != null) {
      widget.onPressed!();
      return true;
    }

    if (widget is InputChip) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
      if (widget.onSelected != null) {
        widget.onSelected!(!(widget.selected));
        return true;
      }
    }

    final widgetType = widget.runtimeType.toString();
    if (widgetType.contains('CupertinoButton')) {
      try {
        final dynamic dynamicWidget = widget;
        final VoidCallback? onPressed =
            dynamicWidget.onPressed as VoidCallback?;
        if (onPressed != null) {
          onPressed();
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  Element? _findFallbackElement(Element root, InteractiveElement target) {
    final label = target.label.toLowerCase();
    Element? found;

    void visit(Element element) {
      if (found != null) return;

      final widget = element.widget;
      if (_matchesWidget(widget, target, label)) {
        found = element;
        return;
      }

      element.visitChildElements(visit);
    }

    visit(root);
    return found;
  }

  bool _matchesWidget(Widget widget, InteractiveElement target, String label) {
    if (widget is ListTile) {
      final title = widget.title is Text
          ? ((widget.title as Text).data ?? '')
          : '';
      return title.toLowerCase().contains(label);
    }

    if (widget is ButtonStyleButton) {
      final child = widget.child;
      if (child is Text) {
        return (child.data ?? '').toLowerCase().contains(label);
      }
    }

    if (target.type == ElementType.switchToggle) {
      return widget is Switch || widget is SwitchListTile;
    }

    if (target.type == ElementType.checkbox) {
      return widget is Checkbox || widget is CheckboxListTile;
    }

    if (target.properties['role'] == 'radio') {
      return widget is Radio || widget is RadioListTile;
    }

    return false;
  }

  String _summarizeElements(
    List<InteractiveElement> elements, {
    int limit = 8,
  }) {
    if (elements.isEmpty) {
      return '(none)';
    }
    return elements
        .take(limit)
        .map(
          (element) =>
              '[${element.index}] ${element.label} (${element.type.name})',
        )
        .join(' | ');
  }

  String _describeElementPath(Element element, {int maxAncestors = 12}) {
    final path = <String>[element.widget.runtimeType.toString()];
    var count = 0;
    element.visitAncestorElements((ancestor) {
      if (count >= maxAncestors) return false;
      path.add(ancestor.widget.runtimeType.toString());
      count += 1;
      return true;
    });
    return path.join(' <- ');
  }
}
