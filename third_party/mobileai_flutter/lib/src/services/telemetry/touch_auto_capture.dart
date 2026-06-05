import 'package:flutter/foundation.dart';

import '../../utils/logger.dart';
import 'mobile_ai.dart';

/// TouchAutoCapture — Extracts a human-readable label from a Flutter
/// touch event target by walking up the element tree.
///
/// Used by AIAgent to auto-track every tap in the app without
/// any developer code changes (zero-config analytics).
///
/// Strategy:
/// 1. Read the touched element's semanticsLabel (best signal).
/// 2. Use the element's label text from tree walking.
/// 3. Fallback to the widget's key or type.
/// 4. Last resort: "Unknown Element".

/// Tap record for rage click detection.
class TapRecord {
  final String label;
  final String screen;
  final int timestamp;
  final int? x;
  final int? y;

  TapRecord({
    required this.label,
    required this.screen,
    required this.timestamp,
    this.x,
    this.y,
  });

  @override
  String toString() => 'TapRecord($label @ $screen, $timestamp, x=$x, y=$y)';
}

/// Touch auto-capture service with rage click detection.
class TouchAutoCapture {
  final VoidCallback? onRageClick;

  static const int _rageWindowMs = 1000; // 1 second window
  static const int _rageThreshold = 3; // 3+ taps = rage
  static const int _maxTapBuffer = 8;

  final List<TapRecord> _recentTaps = [];
  String? _currentScreen;

  // Labels naturally tapped multiple times (wizards, onboarding, etc.)
  static const Set<String> _navigationLabels = {
    'next',
    'continue',
    'skip',
    'back',
    'done',
    'ok',
    'cancel',
    'previous',
    'dismiss',
    'close',
    'got it',
    'confirm',
    'proceed',
    'التالي',
    'متابعة',
    'تخطي',
    'رجوع',
    'تم',
    'إلغاء',
    'إغلاق',
    'حسناً',
  };

  TouchAutoCapture({this.onRageClick});

  /// Update the current screen name.
  void updateScreen(String screenName) {
    _currentScreen = screenName;
  }

  /// Record a tap event and check for rage clicks.
  /// Returns the detected label for analytics.
  String? recordTap({
    required String? label,
    required String? screen,
    int? x,
    int? y,
    String? elementType,
    String? zoneId,
  }) {
    if (label == null || label.isEmpty) return null;

    final effectiveScreen = screen ?? _currentScreen ?? 'Unknown';
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedLabel = _normalizeLabel(label);

    // Skip navigation labels from rage detection
    if (_navigationLabels.contains(normalizedLabel)) {
      _cleanupOldTaps(now);
      return label;
    }

    // Add to recent taps
    _recentTaps.add(TapRecord(
      label: normalizedLabel,
      screen: effectiveScreen,
      timestamp: now,
      x: x,
      y: y,
    ));

    // Trim buffer
    if (_recentTaps.length > _maxTapBuffer) {
      _recentTaps.removeAt(0);
    }

    // Check for rage click
    _checkRageClick(normalizedLabel, effectiveScreen, now, x: x, y: y, elementType: elementType, zoneId: zoneId);

    return label;
  }

  /// Check if the current tap constitutes a rage click.
  void _checkRageClick(
    String label,
    String screen,
    int now, {
    int? x,
    int? y,
    String? elementType,
    String? zoneId,
  }) {
    // Count taps on the same label within the window
    final count = _recentTaps.where((tap) {
      final timeDiff = now - tap.timestamp;
      final sameLabel = tap.label == label;
      final sameScreen = tap.screen == screen;
      return sameLabel && sameScreen && timeDiff <= _rageWindowMs;
    }).length;

    if (count >= _rageThreshold) {
      Logger.warn('[TouchAutoCapture] 🤬 Rage click detected: "$label" ($count taps in ${_rageWindowMs}ms)');
      MobileAI.rageClick(
        element: label,
        clickCount: count,
        x: x,
        y: y,
        elementType: elementType,
        zoneId: zoneId,
      );

      // Clear this label's taps to avoid duplicate reports
      _recentTaps.removeWhere((tap) => tap.label == label);

      onRageClick?.call();
    }

    _cleanupOldTaps(now);
  }

  /// Remove taps older than the rage window.
  void _cleanupOldTaps(int now) {
    _recentTaps.removeWhere((tap) => now - tap.timestamp > _rageWindowMs);
  }

  /// Normalize label for comparison.
  String _normalizeLabel(String label) {
    return label.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Clear all recorded taps.
  void clear() {
    _recentTaps.clear();
  }

  /// Get recent tap count for a label (for debugging).
  int getRecentTapCount(String label) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = _normalizeLabel(label);
    return _recentTaps.where((tap) =>
        tap.label == normalized &&
        now - tap.timestamp <= _rageWindowMs).length;
  }
}

/// Dead click detector - tracks taps on non-interactive elements.
class DeadClickDetector {
  final Set<String> _nonInteractiveSelectors = {};
  final VoidCallback? onDeadClick;

  DeadClickDetector({this.onDeadClick});

  /// Record a potential dead click (tap on non-interactive element).
  void recordDeadClick({
    required String element,
    required String screen,
  }) {
    Logger.warn('[DeadClickDetector] Dead click on: "$element" @ $screen');
    MobileAI.deadClick(element: element);
    onDeadClick?.call();
  }

  /// Mark an element selector as non-interactive.
  void markNonInteractive(String selector) {
    _nonInteractiveSelectors.add(selector);
  }

  /// Check if a selector is known to be non-interactive.
  bool isNonInteractive(String selector) {
    return _nonInteractiveSelectors.contains(selector);
  }
}
