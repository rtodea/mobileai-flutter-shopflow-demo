import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/types.dart';
import '../core/element_tree_walker.dart';
import '../services/telemetry/index.dart';
import '../utils/logger.dart';

/// TouchCaptureWidget — Captures touch events for telemetry.
///
/// Wraps the app and records tap coordinates for:
/// - Rage click detection with X/Y positions
/// - Dead click detection
/// - Element metadata (zone, ancestor path, etc.)
///
/// Uses HitTestBehavior.translucent to not interfere with gestures.
class TouchCaptureWidget extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final ElementTreeWalker? walker;

  const TouchCaptureWidget({
    super.key,
    required this.child,
    this.enabled = true,
    this.walker,
  });

  @override
  State<TouchCaptureWidget> createState() => _TouchCaptureWidgetState();
}

class _TouchCaptureWidgetState extends State<TouchCaptureWidget> {
  final TouchAutoCapture _touchCapture = TouchAutoCapture();
  final DeadClickDetector _deadClickDetector = DeadClickDetector();
  String? _currentScreen;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _initializeScreenTracking();
    }
  }

  void _initializeScreenTracking() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Logger.debug('[TouchCapture] Initialized with controller');
      }
    });
  }

  @override
  void didUpdateWidget(TouchCaptureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _touchCapture.clear();
    }
  }

  @override
  void dispose() {
    _touchCapture.clear();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (widget.walker == null) return;

    // Find element at touch position
    final element = _findElementAtPosition(event.position);
    if (element == null) {
      // No interactive element found - potential dead click
      _deadClickDetector.recordDeadClick(
        element: 'unknown (${event.position.dx.toInt()}, ${event.position.dy.toInt()})',
        screen: _currentScreen ?? 'Unknown',
      );
      return;
    }

    // Record the tap with label
    _touchCapture.recordTap(
      label: element.label,
      screen: _currentScreen ?? 'Unknown',
    );

    // Track the tap with coordinates
    MobileAI.track('user_action', properties: {
      'label': element.label,
      'element_type': element.type.name,
      'x': (event.position.dx * 10).round(), // Normalize to 0-10000 scale
      'y': (event.position.dy * 10).round(),
      'zone_id': element.zoneId,
    });
  }

  InteractiveElement? _findElementAtPosition(Offset position) {
    if (widget.walker == null) return null;

    final elements = widget.walker!.walk(null);
    if (elements.isEmpty) return null;

    // Find element that contains the position
    for (final element in elements) {
      final bounds = _getElementBounds(element);
      if (bounds != null && bounds.contains(position)) {
        return element;
      }
    }

    return null;
  }

  Rect? _getElementBounds(InteractiveElement element) {
    if (element.element != null) {
      final renderObj = element.element!.renderObject;
      if (renderObj is RenderBox) {
        try {
          final pos = renderObj.localToGlobal(Offset.zero);
          final size = renderObj.size;
          return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
        } catch (_) {
          // Bounds not available
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: widget.child,
    );
  }
}

/// Touch data for telemetry.
class TouchData {
  final String label;
  final String elementType;
  final int x;
  final int y;
  final String? zoneId;
  final String screen;

  TouchData({
    required this.label,
    required this.elementType,
    required this.x,
    required this.y,
    this.zoneId,
    required this.screen,
  });

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'elementType': elementType,
      'x': x,
      'y': y,
      if (zoneId != null) 'zoneId': zoneId,
      'screen': screen,
    };
  }
}
