import 'dart:async';

import 'package:flutter/material.dart';

/// FloatingOverlayWrapper — Wrapper for managing floating overlay widgets.
///
/// Provides a consistent overlay layer for floating elements like:
/// - Proactive hints
/// - Tooltips
/// - Highlights
/// - Notifications
///
/// Handles positioning, z-index, and dismissal behavior.
class FloatingOverlayWrapper extends StatefulWidget {
  final Widget child;
  final List<FloatingOverlayEntry> overlays;
  final bool enableGutter;
  final double gutterPadding;
  final bool enableSafeArea;

  const FloatingOverlayWrapper({
    super.key,
    required this.child,
    this.overlays = const [],
    this.enableGutter = true,
    this.gutterPadding = 16,
    this.enableSafeArea = true,
  });

  @override
  State<FloatingOverlayWrapper> createState() => _FloatingOverlayWrapperState();
}

class _FloatingOverlayWrapperState extends State<FloatingOverlayWrapper> {
  final Set<String> _activeOverlays = {};

  @override
  void didUpdateWidget(FloatingOverlayWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Track which overlays are active
    for (final overlay in widget.overlays) {
      _activeOverlays.add(overlay.id);
    }
  }

  void _removeOverlay(String id) {
    setState(() {
      _activeOverlays.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleOverlays = widget.overlays
        .where((overlay) => _activeOverlays.contains(overlay.id))
        .toList();

    return Stack(
      children: [
        widget.child,
        if (widget.enableSafeArea)
          Positioned.fill(
            child: SafeArea(
              child: _OverlayLayer(
                overlays: visibleOverlays,
                enableGutter: widget.enableGutter,
                gutterPadding: widget.gutterPadding,
                onDismiss: _removeOverlay,
              ),
            ),
          )
        else
          Positioned.fill(
            child: _OverlayLayer(
              overlays: visibleOverlays,
              enableGutter: widget.enableGutter,
              gutterPadding: widget.gutterPadding,
              onDismiss: _removeOverlay,
            ),
          ),
      ],
    );
  }
}

class _OverlayLayer extends StatelessWidget {
  final List<FloatingOverlayEntry> overlays;
  final bool enableGutter;
  final double gutterPadding;
  final void Function(String id) onDismiss;

  const _OverlayLayer({
    required this.overlays,
    required this.enableGutter,
    required this.gutterPadding,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Stack(
      children: overlays.map((overlay) {
        final position = _calculatePosition(overlay, size);

        return Positioned(
          left: position.dx,
          top: position.dy,
          child: _OverlayWidget(
            entry: overlay,
            onDismiss: () => onDismiss(overlay.id),
          ),
        );
      }).toList(),
    );
  }

  Offset _calculatePosition(FloatingOverlayEntry overlay, Size size) {
    final gutter = enableGutter ? gutterPadding : 0.0;

    double dx;
    double dy;

    switch (overlay.anchor) {
      case OverlayAnchor.topLeft:
        dx = gutter;
        dy = gutter;
        break;
      case OverlayAnchor.topCenter:
        dx = (size.width - overlay.preferredSize.width) / 2;
        dy = gutter;
        break;
      case OverlayAnchor.topRight:
        dx = size.width - overlay.preferredSize.width - gutter;
        dy = gutter;
        break;
      case OverlayAnchor.centerLeft:
        dx = gutter;
        dy = (size.height - overlay.preferredSize.height) / 2;
        break;
      case OverlayAnchor.center:
        dx = (size.width - overlay.preferredSize.width) / 2;
        dy = (size.height - overlay.preferredSize.height) / 2;
        break;
      case OverlayAnchor.centerRight:
        dx = size.width - overlay.preferredSize.width - gutter;
        dy = (size.height - overlay.preferredSize.height) / 2;
        break;
      case OverlayAnchor.bottomLeft:
        dx = gutter;
        dy = size.height - overlay.preferredSize.height - gutter;
        break;
      case OverlayAnchor.bottomCenter:
        dx = (size.width - overlay.preferredSize.width) / 2;
        dy = size.height - overlay.preferredSize.height - gutter;
        break;
      case OverlayAnchor.bottomRight:
        dx = size.width - overlay.preferredSize.width - gutter;
        dy = size.height - overlay.preferredSize.height - gutter;
        break;
      case OverlayAnchor.custom:
        dx = overlay.customOffset?.dx ?? gutter;
        dy = overlay.customOffset?.dy ?? gutter;
        break;
    }

    return Offset(dx, dy);
  }
}

class _OverlayWidget extends StatefulWidget {
  final FloatingOverlayEntry entry;
  final VoidCallback onDismiss;

  const _OverlayWidget({
    required this.entry,
    required this.onDismiss,
  });

  @override
  State<_OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<_OverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.entry.animationDuration,
    );

    _scaleAnimation = Tween<double>(
      begin: widget.entry.scaleBegin,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.entry.animationCurve,
    ));

    _opacityAnimation = Tween<double>(
      begin: widget.entry.opacityBegin,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.entry.animationCurve,
    ));

    _controller.forward();

    if (widget.entry.autoDismissDuration != null) {
      _dismissTimer = Timer(widget.entry.autoDismissDuration!, () {
        if (mounted) {
          _handleDismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: TapRegion(
              onTapOutside: widget.entry.dismissOnTapOutside
                  ? (_) => _handleDismiss()
                  : null,
              child: widget.entry.builder(context),
            ),
          ),
        );
      },
    );
  }
}

/// Defines a floating overlay entry.
class FloatingOverlayEntry {
  final String id;
  final WidgetBuilder builder;
  final OverlayAnchor anchor;
  final Size preferredSize;
  final Offset? customOffset;
  final Duration animationDuration;
  final Curve animationCurve;
  final double scaleBegin;
  final double opacityBegin;
  final Duration? autoDismissDuration;
  final bool dismissOnTapOutside;

  const FloatingOverlayEntry({
    required this.id,
    required this.builder,
    this.anchor = OverlayAnchor.bottomCenter,
    this.preferredSize = const Size(300, 200),
    this.customOffset,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeOut,
    this.scaleBegin = 0.8,
    this.opacityBegin = 0.0,
    this.autoDismissDuration,
    this.dismissOnTapOutside = true,
  });

  FloatingOverlayEntry copyWith({
    String? id,
    WidgetBuilder? builder,
    OverlayAnchor? anchor,
    Size? preferredSize,
    Offset? customOffset,
    Duration? animationDuration,
    Curve? animationCurve,
    double? scaleBegin,
    double? opacityBegin,
    Duration? autoDismissDuration,
    bool? dismissOnTapOutside,
  }) {
    return FloatingOverlayEntry(
      id: id ?? this.id,
      builder: builder ?? this.builder,
      anchor: anchor ?? this.anchor,
      preferredSize: preferredSize ?? this.preferredSize,
      customOffset: customOffset ?? this.customOffset,
      animationDuration: animationDuration ?? this.animationDuration,
      animationCurve: animationCurve ?? this.animationCurve,
      scaleBegin: scaleBegin ?? this.scaleBegin,
      opacityBegin: opacityBegin ?? this.opacityBegin,
      autoDismissDuration: autoDismissDuration ?? this.autoDismissDuration,
      dismissOnTapOutside: dismissOnTapOutside ?? this.dismissOnTapOutside,
    );
  }
}

/// Anchor positions for floating overlays.
enum OverlayAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  custom,
}

/// Controller for managing floating overlays.
class FloatingOverlayController extends ChangeNotifier {
  final List<FloatingOverlayEntry> _overlays = [];

  List<FloatingOverlayEntry> get overlays => List.unmodifiable(_overlays);

  void add(FloatingOverlayEntry entry) {
    _overlays.add(entry);
    notifyListeners();
  }

  void remove(String id) {
    _overlays.removeWhere((overlay) => overlay.id == id);
    notifyListeners();
  }

  void clear() {
    _overlays.clear();
    notifyListeners();
  }

  bool hasOverlay(String id) {
    return _overlays.any((overlay) => overlay.id == id);
  }
}

/// Widget that observes a FloatingOverlayController and builds overlays.
class FloatingOverlayControllerWidget extends StatefulWidget {
  final FloatingOverlayController controller;
  final Widget child;

  const FloatingOverlayControllerWidget({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<FloatingOverlayControllerWidget> createState() =>
      _FloatingOverlayControllerWidgetState();
}

class _FloatingOverlayControllerWidgetState
    extends State<FloatingOverlayControllerWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FloatingOverlayWrapper(
      overlays: widget.controller.overlays,
      child: widget.child,
    );
  }
}
