import 'dart:async';
import 'package:flutter/widgets.dart';

class IdleDetectorConfig {
  /// Time in ms before the agent pulses subtly (e.g. 120_000 for 2m)
  final int pulseAfterMs;
  
  /// Time in ms before the agent shows a badge (e.g. 240_000 for 4m)
  final int badgeAfterMs;
  
  /// Callback fired when the user is idle enough for a subtle pulse
  final VoidCallback onPulse;
  
  /// Callback fired when the user is idle enough for a proactive badge.
  final ValueChanged<String> onBadge;
  
  /// Callback fired when the user interacts, cancelling idle states
  final VoidCallback onReset;
  
  /// Dynamic context suggestion generator based on current screen
  final String Function()? generateSuggestion;

  IdleDetectorConfig({
    required this.pulseAfterMs,
    required this.badgeAfterMs,
    required this.onPulse,
    required this.onBadge,
    required this.onReset,
    this.generateSuggestion,
  });
}

class IdleDetector {
  Timer? _pulseTimer;
  Timer? _badgeTimer;
  bool _dismissed = false;
  IdleDetectorConfig? _config;

  void start(IdleDetectorConfig config) {
    _config = config;
    _dismissed = false;
    _resetTimers();
  }

  void reset() {
    if (_config == null || _dismissed) return;
    _config!.onReset();
    _resetTimers();
  }

  void dismiss() {
    _dismissed = true;
    _clearTimers();
    if (_config != null) {
      _config!.onReset();
    }
  }

  void destroy() {
    _clearTimers();
    _config = null;
  }

  void _resetTimers() {
    _clearTimers();

    if (_config == null || _dismissed) return;

    _pulseTimer = Timer(Duration(milliseconds: _config!.pulseAfterMs), () {
      _config?.onPulse();
    });

    _badgeTimer = Timer(Duration(milliseconds: _config!.badgeAfterMs), () {
      final suggestion = _config?.generateSuggestion?.call() ?? "Need help with this screen?";
      _config?.onBadge(suggestion);
    });
  }

  void _clearTimers() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _badgeTimer?.cancel();
    _badgeTimer = null;
  }
}
