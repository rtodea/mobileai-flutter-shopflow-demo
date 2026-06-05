import '../../core/types.dart';

/// Analytics label source priority.
enum AnalyticsLabelSource {
  accessibility,
  deepText,
  siblingText,
  placeholder,
  title,
  testId,
  icon,
  context,
}

/// Analytics element kind (button, link, input, etc.).
enum AnalyticsElementKind {
  button,
  link,
  input,
  text,
  image,
  unknown,
}

/// Analytics label confidence level.
enum AnalyticsLabelConfidence {
  high,
  medium,
  low,
}

/// Analytics label candidate.
class AnalyticsLabelCandidate {
  final String? text;
  final AnalyticsLabelSource source;
  final bool isInteractiveContext;

  const AnalyticsLabelCandidate({
    this.text,
    required this.source,
    this.isInteractiveContext = false,
  });

  @override
  String toString() => 'AnalyticsLabelCandidate($text, $source)';
}

/// Metadata about an analytics target (tapped element).
class AnalyticsTargetMetadata {
  final String? label;
  final AnalyticsElementKind elementKind;
  final AnalyticsLabelConfidence labelConfidence;
  final String? zoneId;
  final List<String>? ancestorPath;
  final List<String>? siblingLabels;
  final String? componentName;

  const AnalyticsTargetMetadata({
    this.label,
    required this.elementKind,
    required this.labelConfidence,
    this.zoneId,
    this.ancestorPath,
    this.siblingLabels,
    this.componentName,
  });

  @override
  String toString() =>
      'AnalyticsTargetMetadata(label: $label, kind: $elementKind, confidence: $labelConfidence)';

  /// Convert to JSON for analytics.
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'elementKind': elementKind.name,
      'labelConfidence': labelConfidence.name,
      if (zoneId != null) 'zoneId': zoneId,
      if (ancestorPath != null) 'ancestorPath': ancestorPath,
      if (siblingLabels != null) 'siblingLabels': siblingLabels,
      if (componentName != null) 'componentName': componentName,
    };
  }
}

/// Generic labels to avoid in analytics.
const Set<String> _genericLabels = {
  'button',
  'buttons',
  'component',
  'components',
  'container',
  'containers',
  'content',
  'cta',
  'item',
  'items',
  'label',
  'labels',
  'root',
  'row',
  'rows',
  'screen',
  'screens',
  'text',
  'texts',
  'title',
  'titles',
  'unknown',
  'value',
  'values',
  'view',
  'views',
  'wrapper',
  'tap',
  'click',
  'press',
  'element',
};

/// Analytics labeling service.
class AnalyticsLabeling {
  /// Extract the best analytics label from an interactive element.
  static AnalyticsTargetMetadata extractMetadata(InteractiveElement element) {
    final candidates = _extractCandidates(element);
    final best = _chooseBestCandidate(candidates, element);

    return AnalyticsTargetMetadata(
      label: best.text,
      elementKind: _inferElementKind(element),
      labelConfidence: _inferConfidence(best, element),
      zoneId: element.zoneId,
      componentName: element.type.name,
    );
  }

  /// Extract all label candidates from an element.
  static List<AnalyticsLabelCandidate> _extractCandidates(InteractiveElement element) {
    final candidates = <AnalyticsLabelCandidate>[];

    // 1. Accessibility/semantics label (highest priority)
    if (element.label.isNotEmpty) {
      candidates.add(AnalyticsLabelCandidate(
        text: element.label,
        source: AnalyticsLabelSource.accessibility,
        isInteractiveContext: true,
      ));
    }

    // 2. Check for common button text patterns
    if (element.label.isNotEmpty) {
      candidates.add(AnalyticsLabelCandidate(
        text: element.label,
        source: AnalyticsLabelSource.deepText,
      ));
    }

    // 3. Check widget key (testID equivalent)
    if (element.properties['key'] != null) {
      final key = element.properties['key'].toString();
      if (key.isNotEmpty && !key.startsWith('_')) {
        candidates.add(AnalyticsLabelCandidate(
          text: key,
          source: AnalyticsLabelSource.testId,
        ));
      }
    }

    // 4. Check for placeholder/hint text
    if (element.properties['hint'] != null) {
      final hint = element.properties['hint'].toString();
      if (hint.isNotEmpty) {
        candidates.add(AnalyticsLabelCandidate(
          text: hint,
          source: AnalyticsLabelSource.placeholder,
        ));
      }
    }

    // 5. Value text (for inputs)
    if (element.properties['value'] != null) {
      final value = element.properties['value'].toString();
      if (value.isNotEmpty && value.length < 50) {
        candidates.add(AnalyticsLabelCandidate(
          text: value,
          source: AnalyticsLabelSource.context,
        ));
      }
    }

    return candidates;
  }

  /// Choose the best label candidate.
  static AnalyticsLabelCandidate _chooseBestCandidate(
    List<AnalyticsLabelCandidate> candidates,
    InteractiveElement element,
  ) {
    // Priority order: accessibility > deepText > placeholder > testId > context
    for (final source in [
      AnalyticsLabelSource.accessibility,
      AnalyticsLabelSource.deepText,
      AnalyticsLabelSource.placeholder,
      AnalyticsLabelSource.testId,
      AnalyticsLabelSource.context,
    ]) {
      final match = candidates.where((c) => c.source == source).firstOrNull;
      if (match != null && match.text != null && !_isGeneric(match.text!)) {
        return match;
      }
    }

    // Fallback to element type name
    return AnalyticsLabelCandidate(
      text: _getFallbackLabel(element),
      source: AnalyticsLabelSource.icon,
    );
  }

  /// Check if a label is too generic to be useful.
  static bool _isGeneric(String label) {
    final normalized = label.toLowerCase().trim();
    return _genericLabels.contains(normalized) ||
        normalized.length < 2 ||
        RegExp(r'^[0-9]+$').hasMatch(normalized);
  }

  /// Get fallback label based on element type.
  static String _getFallbackLabel(InteractiveElement element) {
    switch (element.type) {
      case ElementType.pressable:
        return 'Button';
      case ElementType.textInput:
        return 'Text Field';
      case ElementType.slider:
        return 'Slider';
      case ElementType.picker:
        return 'Dropdown';
      case ElementType.datePicker:
        return 'Date Picker';
      case ElementType.checkbox:
        return 'Checkbox';
      case ElementType.switchToggle:
        return 'Switch';
      case ElementType.scrollable:
        return 'Scroll View';
      case ElementType.text:
        return 'Text';
    }
  }

  /// Infer element kind from type and properties.
  static AnalyticsElementKind _inferElementKind(InteractiveElement element) {
    switch (element.type) {
      case ElementType.pressable:
        return AnalyticsElementKind.button;
      case ElementType.textInput:
      case ElementType.picker:
      case ElementType.datePicker:
        return AnalyticsElementKind.input;
      case ElementType.text:
        return AnalyticsElementKind.text;
      default:
        return AnalyticsElementKind.unknown;
    }
  }

  /// Infer confidence level from candidate and element.
  static AnalyticsLabelConfidence _inferConfidence(
    AnalyticsLabelCandidate candidate,
    InteractiveElement element,
  ) {
    if (candidate.source == AnalyticsLabelSource.accessibility &&
        candidate.text != null &&
        !_isGeneric(candidate.text!)) {
      return AnalyticsLabelConfidence.high;
    }

    if (candidate.source == AnalyticsLabelSource.deepText &&
        candidate.text != null &&
        candidate.text!.length > 3 &&
        !_isGeneric(candidate.text!)) {
      return AnalyticsLabelConfidence.high;
    }

    if (candidate.text != null && !_isGeneric(candidate.text!)) {
      return AnalyticsLabelConfidence.medium;
    }

    return AnalyticsLabelConfidence.low;
  }

  /// Choose the best analytics target from multiple elements.
  /// Used when multiple elements are under the touch point.
  static AnalyticsTargetMetadata? chooseBestTarget(List<InteractiveElement> elements) {
    if (elements.isEmpty) return null;

    // Prefer pressable elements
    final pressable = elements.where((e) => e.type == ElementType.pressable).firstOrNull;
    if (pressable != null) {
      return extractMetadata(pressable);
    }

    // Then inputs
    final input = elements.where((e) =>
        e.type == ElementType.textInput ||
        e.type == ElementType.picker).firstOrNull;
    if (input != null) {
      return extractMetadata(input);
    }

    // Fall back to first element with a good label
    for (final element in elements) {
      final metadata = extractMetadata(element);
      if (metadata.label != null &&
          metadata.labelConfidence != AnalyticsLabelConfidence.low) {
        return metadata;
      }
    }

    // Last resort
    return extractMetadata(elements.first);
  }

  /// Get analytics element kind as string.
  static String getAnalyticsElementKind(AnalyticsElementKind kind) {
    return kind.name;
  }

  /// Get label confidence as string.
  static String getLabelConfidence(AnalyticsLabelConfidence confidence) {
    return confidence.name;
  }
}
