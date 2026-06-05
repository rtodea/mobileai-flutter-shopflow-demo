import 'types.dart';

/// ScreenDehydrator converts the discovered widget-tree state into the
/// RN-style textual screen representation expected by the synced prompt.
class ScreenDehydrator {
  static const Set<String> _internalOnlyProperties = <String>{
    'actionIndex',
    'bounds',
  };

  static const List<String> _propertyOrder = <String>[
    'id',
    'parentId',
    'scrollHostId',
    'key',
    'widgetType',
    'role',
    'tooltip',
    'orientation',
    'value',
    'checked',
    'selected',
    'enabled',
    'disabled',
    'hint',
    'placeholder',
  ];

  /// Converts interactive elements into the RN-style prompt format:
  /// `[index]<type attrs>Label />`
  /// Visible non-interactive text is emitted as plain text lines.
  static String dehydrate(List<InteractiveElement> elements) {
    if (elements.isEmpty) {
      return 'No interactive elements detected on this screen.';
    }

    final sortedElements = List<InteractiveElement>.from(elements)
      ..sort((a, b) {
        if (a.aiPriority == AiPriority.high && b.aiPriority != AiPriority.high) {
          return -1;
        }
        if (a.aiPriority != AiPriority.high && b.aiPriority == AiPriority.high) {
          return 1;
        }
        final aIsScrollable = a.type == ElementType.scrollable;
        final bIsScrollable = b.type == ElementType.scrollable;
        if (aIsScrollable != bIsScrollable) {
          return aIsScrollable ? 1 : -1;
        }
        return a.index.compareTo(b.index);
      });

    final interactiveLines = <String>[];
    final visibleContent = <String>[];
    final visibleContentSeen = <String>{};
    for (final element in sortedElements) {
      if (element.type == ElementType.text) {
        if (visibleContentSeen.add(element.label)) {
          visibleContent.add(element.label);
        }
        continue;
      }

      final typeString = _formatElementType(element.type);
      final attrs = _formatAttributes(element.properties);
      interactiveLines.add('[${element.index}]<$typeString$attrs>${element.label} />');
    }

    if (interactiveLines.isEmpty && visibleContent.isEmpty) {
      return 'No interactive elements detected on this screen.';
    }

    final sections = <String>[];
    if (interactiveLines.isNotEmpty) {
      sections.add(interactiveLines.join('\n'));
    }
    if (visibleContent.isNotEmpty) {
      sections.add(
        'Visible Content:\n${visibleContent.take(16).map((text) => '- $text').join('\n')}',
      );
    }

    return sections.join('\n\n').trim();
  }

  /// Summarizes currently active control state in a generic, app-agnostic way.
  /// This helps the model reason about constrained views without adding
  /// domain-specific hints.
  static String summarizeActiveState(List<InteractiveElement> elements) {
    final lines = <String>[];

    for (final element in elements) {
      if (element.type == ElementType.text) {
        continue;
      }

      final stateFragments = <String>[];
      final orderedKeys = _orderedPropertyKeys(element.properties);
      for (final key in orderedKeys) {
        final value = element.properties[key];
        if (!_isInterestingStateProperty(key, value)) {
          continue;
        }
        stateFragments.add('$key="${_stringifyAttributeValue(value)}"');
      }

      if (stateFragments.isEmpty) {
        continue;
      }

      lines.add(
        '- <${_formatElementType(element.type)}> ${element.label} | ${stateFragments.join(' | ')}',
      );
    }

    if (lines.isEmpty) {
      return '';
    }

    return 'Active UI State:\n${lines.join('\n')}';
  }

  static String _formatAttributes(Map<String, dynamic> properties) {
    final buffer = StringBuffer();
    for (final key in _orderedPropertyKeys(properties)) {
      final value = properties[key];
      if (!_shouldSurfaceProperty(key, value)) {
        continue;
      }
      buffer.write(' $key="${_stringifyAttributeValue(value)}"');
    }
    return buffer.toString();
  }

  static Iterable<String> _orderedPropertyKeys(Map<String, dynamic> properties) {
    final seen = <String>{};
    final ordered = <String>[];

    for (final key in _propertyOrder) {
      if (properties.containsKey(key)) {
        ordered.add(key);
        seen.add(key);
      }
    }

    final remaining = properties.keys
        .where((key) => !seen.contains(key))
        .toList(growable: false)
      ..sort();
    ordered.addAll(remaining);
    return ordered;
  }

  static bool _shouldSurfaceProperty(String key, Object? value) {
    if (_internalOnlyProperties.contains(key) || value == null) {
      return false;
    }
    final normalized = _stringifyAttributeValue(value);
    return normalized.isNotEmpty;
  }

  static bool _isInterestingStateProperty(String key, Object? value) {
    if (!_shouldSurfaceProperty(key, value)) {
      return false;
    }

    switch (key) {
      case 'id':
      case 'parentId':
      case 'scrollHostId':
      case 'key':
      case 'widgetType':
      case 'tooltip':
      case 'orientation':
        return false;
      case 'value':
      case 'checked':
      case 'selected':
      case 'disabled':
        return true;
      case 'enabled':
        return value == false;
      case 'hint':
      case 'placeholder':
      case 'role':
        return false;
      default:
        return true;
    }
  }

  static final RegExp _dataUriRegex = RegExp(
    r'data:[a-zA-Z0-9/+;=,\-]+base64,[A-Za-z0-9+/=]+',
  );

  static String _stringifyAttributeValue(Object value) {
    final text = value is String ? value : value.toString();
    // Strip inline base64 data URIs from image sources to prevent token overflow
    return text
        .replaceAll(_dataUriRegex, '[inline-image]')
        .replaceAll('"', r'\"')
        .trim();
  }

  static String _formatElementType(ElementType type) {
    switch (type) {
      case ElementType.pressable:
        return 'pressable';
      case ElementType.textInput:
        return 'text-input';
      case ElementType.switchToggle:
        return 'switch';
      case ElementType.scrollable:
        return 'scrollable';
      case ElementType.slider:
        return 'slider';
      case ElementType.picker:
        return 'picker';
      case ElementType.datePicker:
        return 'date-picker';
      case ElementType.checkbox:
        return 'checkbox';
      case ElementType.text:
        return 'text';
    }
  }
}
