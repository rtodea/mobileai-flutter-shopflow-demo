import 'dart:async';

import '../../utils/logger.dart';
import 'telemetry_service.dart';

/// MobileAI — Public static API for consumer event tracking.
///
/// Usage:
///   import 'package:mobileai_flutter/mobileai_flutter.dart';
///   MobileAI.track('purchase_complete', properties: {'total': 29.99});
///   MobileAI.identify('user_123', traits: {'plan': 'premium'});
///   final flag = MobileAI.getFlag('new_checkout_flow');
///
/// The TelemetryService instance is injected by the `AIAgent` component.
/// If no analyticsKey is configured, all calls are no-ops.
class MobileAI {
  MobileAI._();

  static TelemetryService? _service;

  /// Internal: Set by AIAgent when telemetry is configured
  static void setService(TelemetryService? service) {
    _service = service;
  }

  /// Internal: Get the current service
  static TelemetryService? get service => _service;

  /// Track a custom business event.
  ///
  /// [name] - Name of the event (e.g., 'purchase_complete')
  /// [properties] - Event-specific key-value data
  /// [screen] - Optional screen name override
  static void track(
    String name, {
    Map<String, dynamic> properties = const {},
    String? screen,
  }) {
    if (_service == null) {
      Logger.debug("[MobileAI] track('$name') ignored — no analyticsKey configured");
      return;
    }
    _service!.track(name, data: properties, screen: screen);
  }

  /// Identify the current user (optional, for user-level analytics).
  ///
  /// [userId] - Unique user identifier (hashed by consumer)
  /// [traits] - Optional user traits (plan, role, etc.)
  static void identify(String userId, {Map<String, dynamic> traits = const {}}) {
    if (_service == null) {
      Logger.debug('[MobileAI] identify() ignored — no analyticsKey configured');
      return;
    }
    _service!.track('identify', data: {
      'user_id': userId,
      ...traits,
    });
  }

  /// Get an assigned feature flag variation for the current device.
  ///
  /// Deterministic via murmurhash. Call after MobileAI has initialized.
  ///
  /// [key] - Flag key
  /// [defaultValue] - Fallback if not assigned
  static String getFlag(String key, {String? defaultValue}) {
    if (_service == null) {
      return defaultValue ?? '';
    }
    return _service!.flags.getFlag(key, defaultValue: defaultValue);
  }

  /// Check if a flag is enabled (boolean-style).
  static bool isFlagEnabled(String key) {
    if (_service == null) return false;
    return _service!.flags.isEnabled(key);
  }

  /// Get a numeric flag value.
  static int getNumericFlag(String key, {int defaultValue = 0}) {
    if (_service == null) return defaultValue;
    return _service!.flags.getNumericFlag(key, defaultValue: defaultValue);
  }

  /// Update current screen for tracking.
  static void updateScreen(String screenName) {
    if (_service == null) return;
    _service!.updateScreen(screenName);
  }

  /// Get screen flow history.
  static List<String> getScreenFlow() {
    if (_service == null) return [];
    return _service!.getScreenFlow();
  }

  /// Track a screen view event.
  static void screenView(String screenName, {Map<String, dynamic> properties = const {}}) {
    track('screen_view', properties: {
      'screen': screenName,
      ...properties,
    });
  }

  /// Track an agent request event.
  static void agentRequest({
    required String instruction,
    String? screen,
  }) {
    track('agent_request', properties: {
      'instruction': instruction,
      'screen': ?screen,
    });
  }

  /// Track an agent step event.
  static void agentStep({
    required String action,
    Map<String, dynamic>? args,
    String? result,
  }) {
    track('agent_step', properties: {
      'action': action,
      'args': ?args,
      'result': ?result,
    });
  }

  /// Track an agent completion event.
  static void agentComplete({
    required bool success,
    required int steps,
    String? message,
  }) {
    track('agent_complete', properties: {
      'success': success,
      'steps': steps,
      'message': ?message,
    });
  }

  /// Track an escalation event.
  static void escalation({
    required String reason,
    String? ticketId,
  }) {
    track('escalation', properties: {
      'reason': reason,
      'ticket_id': ?ticketId,
    });
  }

  /// Track a knowledge query event.
  static void knowledgeQuery({
    required String query,
    required bool found,
    int? resultCount,
  }) {
    track(found ? 'knowledge_query' : 'knowledge_miss', properties: {
      'query': query,
      'result_count': ?resultCount,
    });
  }

  /// Track a CSAT survey response.
  static void csatResponse({
    required int rating,
    String? feedback,
  }) {
    track('csat_response', properties: {
      'rating': rating,
      'feedback': ?feedback,
    });
  }

  /// Track a rage click event.
  static void rageClick({
    required String element,
    required int clickCount,
    int? x,
    int? y,
    String? elementType,
    String? zoneId,
  }) {
    track('rage_click_detected', properties: {
      'element': element,
      'click_count': clickCount,
      'x': ?x,
      'y': ?y,
      'element_type': ?elementType,
      'zone_id': ?zoneId,
    });
  }

  /// Track a dead click event.
  static void deadClick({
    required String element,
  }) {
    track('dead_click_detected', properties: {
      'element': element,
    });
  }

  /// Track an error screen event.
  static void errorScreen({
    required String errorMessage,
    String? errorCode,
  }) {
    track('error_screen', properties: {
      'error_message': errorMessage,
      'error_code': ?errorCode,
    });
  }

  /// Track a checkout started event.
  static void checkoutStarted({
    required Map<String, dynamic> cart,
  }) {
    track('checkout_started', properties: cart);
  }

  /// Track a purchase completed event.
  static void purchaseComplete({
    required String orderId,
    required double total,
    String? currency,
    Map<String, dynamic>? items,
  }) {
    track('purchase_complete', properties: {
      'order_id': orderId,
      'total': total,
      'currency': ?currency,
      'items': ?items,
    });
  }

  /// Flush queued events immediately.
  static Future<void> flush() async {
    await _service?.flush();
  }

  /// Enable/disable debug logging for telemetry.
  static void setDebug(bool enabled) {
    Logger.debug('[MobileAI] Debug mode: $enabled');
  }

  /// Track a wireframe snapshot for heatmap analytics.
  ///
  /// Call this when a screen loads to capture the layout for analytics.
  static void wireframeSnapshot({
    required String screen,
    required int deviceWidth,
    required int deviceHeight,
    required List<Map<String, dynamic>> components,
    String? screenshot,
  }) {
    if (_service == null) return;
    _service!.trackWireframe(
      screen: screen,
      deviceWidth: deviceWidth,
      deviceHeight: deviceHeight,
      components: components,
      screenshot: screenshot,
    );
  }
}
