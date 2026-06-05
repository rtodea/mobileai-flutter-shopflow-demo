import 'package:flutter/widgets.dart';
import '../core/types.dart';

/// Context injected into tools during execution.
class ToolContext {
  /// The root widget context used for Element Tree walking
  final BuildContext rootContext;

  /// The current Agent Config
  final AgentConfig config;

  /// The most recently discovered interactive elements list
  final List<InteractiveElement> lastElements;

  /// Screen name for the snapshot that produced [lastElements].
  final String? observedScreenName;

  /// Freshly discover interactive elements before executing an index action.
  final Future<List<InteractiveElement>> Function()? getCurrentElements;

  /// Get current screen name
  final String Function() getCurrentScreenName;

  /// Get available route names
  final List<String> Function() getRouteNames;

  /// Build nested path
  final List<String> Function(String)? findScreenPath;

  /// Optional function to capture a screenshot base64
  final Future<String?> Function()? captureScreenshot;

  ToolContext({
    required this.rootContext,
    AgentConfig? config,
    required this.lastElements,
    this.observedScreenName,
    this.getCurrentElements,
    String Function()? getCurrentScreenName,
    List<String> Function()? getRouteNames,
    this.findScreenPath,
    this.captureScreenshot,
  }) : config = config ?? AgentConfig(),
       getCurrentScreenName = getCurrentScreenName ?? (() => 'Unknown'),
       getRouteNames = getRouteNames ?? (() => const <String>[]);

  /// Resolve a model-selected index against the latest UI before acting.
  ///
  /// Indexes are only stable within one observed snapshot. This guard preserves
  /// the old direct-index behavior when no fresh resolver is wired, but when it
  /// is available it refuses ambiguous stale targets instead of executing the
  /// wrong widget after a rebuild.
  Future<InteractiveElement> resolveInteractiveElement(
    int index, {
    String actionName = 'action',
  }) async {
    final observed = _findByIndex(lastElements, index);
    if (observed == null) {
      throw StaleTargetException(
        'STALE_TARGET: [$index] was not in the last observed screen for $actionName. Re-read the current screen and choose a current index.',
      );
    }

    final currentElementsProvider = getCurrentElements;
    if (currentElementsProvider == null) {
      return observed;
    }

    final observedScreen = _normalizeScreenName(observedScreenName);
    final currentScreen = _normalizeScreenName(getCurrentScreenName());
    if (observedScreen.isNotEmpty &&
        currentScreen.isNotEmpty &&
        observedScreen != currentScreen) {
      throw StaleTargetException(
        'STALE_TARGET: screen changed from "$observedScreen" to "$currentScreen" before $actionName. Re-read the current screen and choose a current index.',
      );
    }

    final currentElements = await currentElementsProvider();
    final sameIndex = _findByIndex(currentElements, index);
    if (sameIndex != null && _isSameIndexSafe(observed, sameIndex)) {
      return sameIndex;
    }

    final match = _relocateTarget(observed, currentElements);
    if (match != null) {
      return match;
    }

    final sameIndexReason = sameIndex == null
        ? 'index [$index] no longer exists'
        : 'index [$index] now looks like "${sameIndex.label}" (${sameIndex.type.name})';
    throw StaleTargetException(
      'STALE_TARGET: ${observed.type.name} [$index] "${observed.label}" could not be matched safely; $sameIndexReason. Re-read the current screen and choose a current index.',
    );
  }
}

/// Abstract base class for all UI Interaction Tools.
abstract class AgentTool {
  ToolDefinition get definition;

  Future<String> execute(Map<String, dynamic> args, ToolContext context);
}

class StaleTargetException implements Exception {
  final String message;

  const StaleTargetException(this.message);

  @override
  String toString() => message;
}

InteractiveElement? _findByIndex(List<InteractiveElement> elements, int index) {
  for (final element in elements) {
    if (element.index == index) {
      return element;
    }
  }
  return null;
}

bool _isSameIndexSafe(InteractiveElement observed, InteractiveElement current) {
  if (observed.type != current.type) {
    return false;
  }
  if (_strongConflict(
    _stableProperty(observed, 'key'),
    _stableProperty(current, 'key'),
  )) {
    return false;
  }
  if (_strongConflict(
    _stableProperty(observed, 'role'),
    _stableProperty(current, 'role'),
  )) {
    return false;
  }
  if (_strongConflict(observed.zoneId, current.zoneId)) {
    return false;
  }

  final observedLabel = _normalizeSemanticText(observed.label);
  final currentLabel = _normalizeSemanticText(current.label);
  if (_isStrongLabel(observedLabel) &&
      _isStrongLabel(currentLabel) &&
      observedLabel != currentLabel) {
    return false;
  }

  return true;
}

InteractiveElement? _relocateTarget(
  InteractiveElement observed,
  List<InteractiveElement> currentElements,
) {
  final candidates = <_ScoredElement>[];
  for (final candidate in currentElements) {
    final score = _scoreCandidate(observed, candidate);
    if (score >= 60) {
      candidates.add(_ScoredElement(candidate, score));
    }
  }

  if (candidates.isEmpty) {
    return null;
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;
  final runnerUp = candidates.length > 1 ? candidates[1] : null;
  if (runnerUp != null && runnerUp.score >= best.score - 10) {
    return null;
  }
  return best.element;
}

int _scoreCandidate(InteractiveElement observed, InteractiveElement candidate) {
  if (observed.type != candidate.type) {
    return 0;
  }

  var score = 20;

  final observedKey = _stableProperty(observed, 'key');
  final candidateKey = _stableProperty(candidate, 'key');
  if (observedKey != null && candidateKey != null) {
    if (observedKey == candidateKey) {
      score += 100;
    } else {
      return 0;
    }
  }

  final observedRuntimeId = _stableProperty(observed, 'id');
  final candidateRuntimeId = _stableProperty(candidate, 'id');
  if (observedRuntimeId != null &&
      candidateRuntimeId != null &&
      observedRuntimeId == candidateRuntimeId) {
    score += 60;
  }

  final observedLabel = _normalizeSemanticText(observed.label);
  final candidateLabel = _normalizeSemanticText(candidate.label);
  if (observedLabel.isNotEmpty && candidateLabel.isNotEmpty) {
    if (observedLabel == candidateLabel) {
      score += _isStrongLabel(observedLabel) ? 45 : 10;
    } else if (_isStrongLabel(observedLabel) &&
        _isStrongLabel(candidateLabel)) {
      return 0;
    }
  }

  score += _matchingPropertyScore(observed, candidate, 'tooltip', 18);
  score += _matchingPropertyScore(observed, candidate, 'role', 15);
  score += _matchingPropertyScore(observed, candidate, 'widgetType', 12);
  score += _matchingPropertyScore(observed, candidate, 'actionIndex', 10);

  if (observed.zoneId != null && candidate.zoneId != null) {
    if (observed.zoneId == candidate.zoneId) {
      score += 14;
    } else {
      return 0;
    }
  }

  score += _matchingPropertyScore(observed, candidate, 'parentId', 5);
  score += _matchingPropertyScore(observed, candidate, 'scrollHostId', 5);
  score += _matchingPropertyScore(observed, candidate, 'selected', 4);
  score += _matchingPropertyScore(observed, candidate, 'checked', 4);
  score += _matchingPropertyScore(observed, candidate, 'enabled', 3);

  return score;
}

int _matchingPropertyScore(
  InteractiveElement observed,
  InteractiveElement candidate,
  String key,
  int points,
) {
  final observedValue = _stableProperty(observed, key);
  final candidateValue = _stableProperty(candidate, key);
  if (observedValue == null || candidateValue == null) {
    return 0;
  }
  return observedValue == candidateValue ? points : 0;
}

String? _stableProperty(InteractiveElement element, String key) {
  final value = element.properties[key];
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool _strongConflict(String? observed, String? current) {
  return observed != null && current != null && observed != current;
}

String _normalizeSemanticText(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeScreenName(String? value) {
  return (value ?? '').trim();
}

bool _isStrongLabel(String label) {
  if (label.isEmpty || label.length < 3) {
    return false;
  }
  const weakLabels = <String>{
    'button',
    'icon button',
    'floating action button',
    'switch',
    'checkbox',
    'radio',
    'slider',
    'picker',
    'text field',
    'date picker',
    'scroll view',
    'vertical scroll view',
    'horizontal scroll view',
    'filter',
    'choice',
    'action',
    'chip',
  };
  return !weakLabels.contains(label);
}

class _ScoredElement {
  final InteractiveElement element;
  final int score;

  const _ScoredElement(this.element, this.score);
}
