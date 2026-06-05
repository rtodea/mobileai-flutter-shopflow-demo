import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';
import '../../core/types.dart';
import 'pii_scrubber.dart';
import 'feature_flag_service.dart';

/// Extended event type with screen and session tracking
class ExtendedTelemetryEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic> properties;
  final String screen;
  final String sessionId;

  const ExtendedTelemetryEvent({
    required this.name,
    required this.timestamp,
    this.properties = const {},
    this.screen = 'Unknown',
    this.sessionId = '',
  });
}

/// TelemetryService — Batches and sends analytics events to MobileAI Cloud.
///
/// Features:
/// - Event batching (flush every N seconds or N events)
/// - Offline queue with retry on reconnect
/// - PII scrubbing for sensitive data
/// - Session tracking
/// - Screen flow tracking
class TelemetryService {
  final TelemetryConfig config;
  final String sessionId;
  final PiiScrubber piiScrubber;
  final FeatureFlagService flags;

  // Event queue and batching
  final List<ExtendedTelemetryEvent> _queue = [];
  Timer? _flushTimer;
  bool _isFlushing = false;

  // Screen flow tracking
  String _currentScreen = 'Unknown';
  final List<String> _screenFlow = [];

  // Agent state
  bool _isAgentActing = false;

  // Deduplication for wireframes
  final Set<String> _wireframesSent = {};

  // Constants
  static const Duration _defaultFlushInterval = Duration(seconds: 30);
  static const int _defaultMaxBatchSize = 50;
  static const String _sdkVersion = '0.2.0';

  TelemetryService({
    required this.config,
    String? sessionId,
    PiiScrubber? piiScrubber,
    String? baseUrl,
  }) : sessionId = sessionId ?? _generateSessionId(),
       piiScrubber = piiScrubber ?? const PiiScrubber(),
       flags = FeatureFlagService(
         baseUrl: baseUrl ?? _normalizeBaseUrl(config.baseUrl),
       );

  /// Get current screen name
  String get screen => _currentScreen;

  /// Get screen flow history
  List<String> getScreenFlow() => List.unmodifiable(_screenFlow);

  /// True while the AI agent is executing a tool
  bool get isAgentActing => _isAgentActing;

  /// Set agent acting state (called by AgentRuntime)
  void setAgentActing(bool active) {
    _isAgentActing = active;
  }

  /// Start the telemetry service
  Future<void> start() async {
    if (!isEnabled()) {
      Logger.debug('[Telemetry] Disabled — no analyticsKey configured');
      return;
    }

    // Fetch feature flags asynchronously
    if (config.analyticsKey != null && config.analyticsKey!.isNotEmpty) {
      unawaited(
        flags.fetch(config.analyticsKey!).catchError((e) {
          Logger.warn('[Telemetry] Could not sync flags: $e');
        }),
      );
    }

    // Start periodic flush
    _flushTimer = Timer.periodic(_defaultFlushInterval, (_) => flush());

    Logger.debug('[Telemetry] Started with session: $sessionId');
  }

  /// Stop the telemetry service
  void stop() {
    _flushTimer?.cancel();
    _flushTimer = null;
    flush(); // Final flush
    Logger.debug('[Telemetry] Stopped');
  }

  /// Check if telemetry is enabled
  bool isEnabled() {
    return config.enabled &&
        config.analyticsKey != null &&
        config.analyticsKey!.isNotEmpty;
  }

  /// Track an event
  void track(
    String name, {
    Map<String, dynamic> data = const {},
    String? screen,
  }) {
    if (!isEnabled()) {
      return;
    }

    final event = ExtendedTelemetryEvent(
      name: name,
      timestamp: DateTime.now().toUtc(),
      properties: data,
      screen: screen ?? _currentScreen,
      sessionId: sessionId,
    );

    // Scrub PII from event data
    final scrubbedEvent = _scrubEvent(event);

    _queue.add(scrubbedEvent);

    // Auto-flush if batch size reached
    if (_queue.length >= _defaultMaxBatchSize) {
      flush();
    }
  }

  /// Update current screen (tracked in events)
  void updateScreen(String screenName) {
    if (_currentScreen != screenName) {
      _currentScreen = screenName;
      _screenFlow.add(screenName);
      track('screen_view', data: {'screen': screenName});
    }
  }

  /// Flush queued events to server
  Future<void> flush() async {
    if (_isFlushing || _queue.isEmpty) {
      return;
    }

    _isFlushing = true;

    try {
      // Take all events from queue
      final events = List<ExtendedTelemetryEvent>.from(_queue);
      _queue.clear();

      final batch = _buildBatch(events);
      final success = await _sendBatch(batch);

      if (!success) {
        // Re-queue events on failure
        _queue.addAll(events);
      }
    } catch (e) {
      Logger.warn('[Telemetry] Flush error: $e');
    } finally {
      _isFlushing = false;
    }
  }

  // ─── Private Methods ────────────────────────────────────────────────

  static String _generateSessionId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 1000000}';
  }

  static String _normalizeBaseUrl(String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) {
      return 'https://mobileai.cloud';
    }
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  ExtendedTelemetryEvent _scrubEvent(ExtendedTelemetryEvent event) {
    final scrubbedProperties = <String, dynamic>{};

    event.properties.forEach((key, value) {
      if (value is String) {
        scrubbedProperties[key] = piiScrubber.scrub(value);
      } else if (value is Map) {
        scrubbedProperties[key] = _scrubMap(value.cast<String, dynamic>());
      } else if (value is List) {
        scrubbedProperties[key] = _scrubList(value);
      } else {
        scrubbedProperties[key] = value;
      }
    });

    return ExtendedTelemetryEvent(
      name: event.name,
      timestamp: event.timestamp,
      properties: scrubbedProperties,
      screen: piiScrubber.scrub(event.screen),
      sessionId: event.sessionId,
    );
  }

  Map<String, dynamic> _scrubMap(Map<String, dynamic> map) {
    final scrubbed = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is String) {
        scrubbed[key] = piiScrubber.scrub(value);
      } else if (value is Map) {
        scrubbed[key] = _scrubMap(value.cast<String, dynamic>());
      } else if (value is List) {
        scrubbed[key] = _scrubList(value);
      } else {
        scrubbed[key] = value;
      }
    });
    return scrubbed;
  }

  List<dynamic> _scrubList(List list) {
    return list.map((item) {
      if (item is String) {
        return piiScrubber.scrub(item);
      } else if (item is Map) {
        return _scrubMap(item.cast<String, dynamic>());
      } else if (item is List) {
        return _scrubList(item);
      }
      return item;
    }).toList();
  }

  Map<String, dynamic> _buildBatch(List<ExtendedTelemetryEvent> events) {
    return {
      'analyticsKey': config.analyticsKey,
      'appId': 'mobileai_flutter',
      'deviceId': config.userId ?? 'unknown',
      'sdkVersion': _sdkVersion,
      'events': events
          .map(
            (e) => {
              'type': e.name,
              'timestamp': e.timestamp.toIso8601String(),
              'screen': e.screen,
              'sessionId': e.sessionId,
              'data': e.properties,
            },
          )
          .toList(),
    };
  }

  Future<bool> _sendBatch(Map<String, dynamic> batch) async {
    final baseUrl = _normalizeBaseUrl(config.baseUrl);
    final endpoint = '$baseUrl/api/v1/telemetry/events';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.analyticsKey}',
          ...?config.headers,
        },
        body: jsonEncode(batch),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      Logger.warn('[Telemetry] Send failed: $e');
      return false;
    }
  }

  /// Track wireframe snapshot with deduplication
  ///
  /// Dashboard expects:
  /// - deviceWidth: screen width in pixels
  /// - deviceHeight: screen height in pixels
  /// - components: list of interactive elements with positions
  /// - screenshot: optional base64 screenshot
  void trackWireframe({
    required String screen,
    required int deviceWidth,
    required int deviceHeight,
    required List<Map<String, dynamic>> components,
    String? screenshot,
  }) {
    // Dedupe by screen name
    if (_wireframesSent.contains(screen)) {
      return;
    }

    _wireframesSent.add(screen);
    track(
      'wireframe_snapshot',
      data: {
        'deviceWidth': deviceWidth,
        'deviceHeight': deviceHeight,
        'components': components,
        'screenshot': ?screenshot,
      },
    );
  }

  void dispose() {
    stop();
  }
}
