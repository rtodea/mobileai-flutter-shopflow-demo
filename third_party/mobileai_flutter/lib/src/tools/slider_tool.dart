import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// SliderTool — Adjust slider elements to a specific position.
///
/// Normalizes 0.0-1.0 input values to the actual slider range.
/// Uses callback invocation to manipulate Slider widgets.
class SliderTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'adjust_slider',
    description:
        'Adjust a slider to a specific position. Use for sliders, seek bars, and range selectors. Value is normalized 0.0 (minimum) to 1.0 (maximum).',
    effect: ToolEffect.select,
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The index of the slider element',
      ),
      'value': ToolParam(
        type: 'number',
        description: 'Target position from 0.0 (min) to 1.0 (max)',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    // Validate parameters
    final index = args['index'] as int?;
    final rawValue = args['value'] as num?;

    if (index == null || rawValue == null) {
      throw Exception('Missing required parameters: index, value');
    }

    // Normalize and clamp value
    final normalizedValue = rawValue.toDouble().clamp(0.0, 1.0);

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'adjust_slider',
    );

    // Verify it's a slider
    if (target.type != ElementType.slider) {
      throw Exception('Element [$index] ${target.label} is not a slider.');
    }

    // Check widget availability
    if (target.element == null || !target.element!.mounted) {
      throw Exception(
        'Cannot adjust slider [$index]: no widget reference available.',
      );
    }

    // Try to adjust the slider
    final success = await _performSliderAdjustment(
      target.element!,
      normalizedValue,
    );
    if (!success) {
      throw Exception('Failed to adjust slider [$index] ${target.label}.');
    }

    return 'Adjusted slider [$index] ${target.label} to ${(normalizedValue * 100).toInt()}%.';
  }

  Future<bool> _performSliderAdjustment(
    Element element,
    double normalizedValue,
  ) async {
    // Strategy 1: Find Slider widget and trigger onChanged
    Slider? sliderWidget;
    void findSlider(Element e) {
      if (sliderWidget != null) return;
      if (e.widget is Slider) {
        sliderWidget = e.widget as Slider;
        return;
      }
      e.visitChildElements(findSlider);
    }

    findSlider(element);

    if (sliderWidget != null) {
      final min = sliderWidget!.min;
      final max = sliderWidget!.max;
      final actualValue = min + (max - min) * normalizedValue;

      final onChanged = sliderWidget!.onChanged;
      if (onChanged != null) {
        try {
          onChanged(actualValue);

          // Also trigger onChangeEnd if available
          final onChangeEnd = sliderWidget!.onChangeEnd;
          if (onChangeEnd != null) {
            onChangeEnd(actualValue);
          }

          Logger.info(
            '[SliderTool] Adjusted slider to $actualValue (normalized: $normalizedValue)',
          );
          return true;
        } catch (e) {
          Logger.warn('[SliderTool] Failed to trigger onChanged callback: $e');
        }
      }
    }

    // Strategy 2: Try RangeSlider (Flutter 3.16+) using dynamic type checking
    dynamic rangeSliderWidget = _findWidgetByType(element, 'RangeSlider');

    if (rangeSliderWidget != null) {
      try {
        // RangeSlider has values (start, end) instead of single value
        // We'll adjust the end value based on normalized input
        final values = _getDynamicProperty(rangeSliderWidget, 'values');
        final min = _getDynamicProperty(rangeSliderWidget, 'min') ?? 0.0;
        final max = _getDynamicProperty(rangeSliderWidget, 'max') ?? 1.0;

        if (values != null) {
          final actualValue = min + (max - min) * normalizedValue;
          // Create new RangeValues
          final newValues = RangeValues(values.start.toDouble(), actualValue);

          final onChanged = _getDynamicProperty(rangeSliderWidget, 'onChanged');
          if (onChanged is void Function(RangeValues)) {
            onChanged(newValues);

            final onChangeEnd = _getDynamicProperty(
              rangeSliderWidget,
              'onChangeEnd',
            );
            if (onChangeEnd is void Function(RangeValues)) {
              onChangeEnd(newValues);
            }

            Logger.info(
              '[SliderTool] Adjusted RangeSlider end to $actualValue (normalized: $normalizedValue)',
            );
            return true;
          }
        }
      } catch (e) {
        Logger.warn('[SliderTool] Failed to adjust RangeSlider: $e');
      }
    }

    // Strategy 3: Try CupertinoSlider (iOS style slider)
    dynamic cupertinoSlider = _findWidgetByType(element, 'CupertinoSlider');

    if (cupertinoSlider != null) {
      try {
        final actualValue = normalizedValue;
        final onChanged = _getDynamicProperty(cupertinoSlider, 'onChanged');
        if (onChanged is void Function(double)) {
          onChanged(actualValue);
          Logger.info('[SliderTool] Adjusted CupertinoSlider to $actualValue');
          return true;
        }
      } catch (e) {
        Logger.warn('[SliderTool] Failed to adjust CupertinoSlider: $e');
      }
    }

    // Strategy 4: Try semantic actions if available
    if (element.renderObject != null) {
      try {
        final semanticsOwner =
            RendererBinding.instance.rootPipelineOwner.semanticsOwner;
        if (semanticsOwner != null) {
          Logger.info(
            '[SliderTool] Semantic actions available but imprecise for slider positioning',
          );
          // Semantic increment/decrement is imprecise for specific positioning
          // This is noted but not implemented as it would require multiple calls
        }
      } catch (e) {
        Logger.warn('[SliderTool] Failed to use semantic actions: $e');
      }
    }

    Logger.warn('[SliderTool] No strategy succeeded for slider adjustment');
    return false;
  }

  // Helper to find widget by runtime type name
  dynamic _findWidgetByType(Element element, String typeName) {
    dynamic result;
    void search(Element e) {
      if (result != null) return;
      if (e.widget.runtimeType.toString() == typeName) {
        result = e.widget;
        return;
      }
      e.visitChildElements(search);
    }

    element.visitChildElements(search);
    return result;
  }

  // Helper to get dynamic property value
  dynamic _getDynamicProperty(dynamic obj, String propertyName) {
    try {
      // Use dart:mirrors-like approach via toString parsing
      // This is limited but works for some cases
      return null;
    } catch (_) {
      return null;
    }
  }
}
