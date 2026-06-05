import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/rich_ui_theme.dart';

/// DiscoveryTooltip — Highlights new features for first-time discovery.
///
/// Shows a tooltip pointing to a specific widget to introduce
/// new features to users. Useful for onboarding and feature discovery.
class DiscoveryTooltip extends StatefulWidget {
  final Widget child;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final bool showOnce;
  final String? featureKey;
  final bool showManually;
  final TooltipPosition position;

  const DiscoveryTooltip({
    super.key,
    required this.child,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.showOnce = true,
    this.featureKey,
    this.showManually = false,
    this.position = TooltipPosition.bottom,
  });

  @override
  State<DiscoveryTooltip> createState() => _DiscoveryTooltipState();
}

class _DiscoveryTooltipState extends State<DiscoveryTooltip>
    with SingleTickerProviderStateMixin {
  final GlobalKey _targetKey = GlobalKey();
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  bool _isVisible = false;
  bool _hasShownBefore = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.showManually) {
      _show();
    } else if (widget.showOnce) {
      _checkIfShownBefore();
    } else {
      _show();
    }
  }

  Future<void> _checkIfShownBefore() async {
    if (widget.featureKey == null) {
      _show();
      return;
    }

    // Check shared preferences or similar storage
    // For now, just show
    _show();
  }

  void _show() {
    if (_hasShownBefore) return;
    if (!mounted) return;

    setState(() => _isVisible = true);
    _controller.repeat();

    if (widget.showOnce && widget.featureKey != null) {
      _markAsShown();
    }
  }

  void _markAsShown() {
    _hasShownBefore = true;
    // Store in shared preferences
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() => _isVisible = false);
    _controller.stop();
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isVisible)
          _DiscoveryTooltipOverlay(
            targetKey: _targetKey,
            title: widget.title,
            description: widget.description,
            actionLabel: widget.actionLabel,
            onAction: widget.onAction,
            onDismiss: _dismiss,
            position: widget.position,
            pulseAnimation: _pulseAnimation,
          ),
      ],
    );
  }
}

class _DiscoveryTooltipOverlay extends StatelessWidget {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final TooltipPosition position;
  final Animation<double> pulseAnimation;

  const _DiscoveryTooltipOverlay({
    required this.targetKey,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
    required this.position,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;

    return _TargetPositioned(
      targetKey: targetKey,
      builder: (context, targetRect) {
        return _DiscoveryTooltipContent(
          targetRect: targetRect,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
          onDismiss: onDismiss,
          position: position,
          accentColor: theme.accent,
          pulseAnimation: pulseAnimation,
        );
      },
    );
  }
}

class _TargetPositioned extends StatefulWidget {
  final GlobalKey targetKey;
  final Widget Function(BuildContext context, Rect targetRect) builder;

  const _TargetPositioned({
    required this.targetKey,
    required this.builder,
  });

  @override
  State<_TargetPositioned> createState() => _TargetPositionedState();
}

class _TargetPositionedState extends State<_TargetPositioned> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_findTarget);
  }

  void _findTarget(_) {
    final renderObject = widget.targetKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      try {
        final position = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        if (mounted) {
          setState(() {
            _targetRect = Rect.fromLTWH(
              position.dx,
              position.dy,
              size.width,
              size.height,
            );
          });
        }
      } catch (_) {
        // Target not available
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_targetRect == null) return const SizedBox.shrink();
    return widget.builder(context, _targetRect!);
  }
}

class _DiscoveryTooltipContent extends StatelessWidget {
  final Rect targetRect;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final TooltipPosition position;
  final Color accentColor;
  final Animation<double> pulseAnimation;

  const _DiscoveryTooltipContent({
    required this.targetRect,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
    required this.position,
    required this.accentColor,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tooltipSize = const Size(280, 140);
    final spotlightPadding = 8.0;

    // Calculate tooltip position based on anchor
    final tooltipPosition = _calculateTooltipPosition(
      targetRect,
      tooltipSize,
      size,
      spotlightPadding,
    );

    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.4),
        child: CustomPaint(
          size: size,
          painter: _SpotlightPainter(
            spotlightRect: targetRect.inflate(spotlightPadding),
            spotlightRadius: 12,
            pulseAnimation: pulseAnimation,
            accentColor: accentColor,
          ),
          child: Stack(
            children: [
              // Tooltip card
              Positioned(
                left: tooltipPosition.dx,
                top: tooltipPosition.dy,
                child: _TooltipCard(
                  title: title,
                  description: description,
                  actionLabel: actionLabel,
                  onAction: onAction,
                  onDismiss: onDismiss,
                  accentColor: accentColor,
                  position: position,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _calculateTooltipPosition(
    Rect target,
    Size tooltip,
    Size screen,
    double padding,
  ) {
    double dx;
    double dy;

    // Determine best position based on available space
    final spaceAbove = target.top;
    final spaceBelow = screen.height - target.bottom;
    final spaceLeft = target.left;
    final spaceRight = screen.width - target.right;

    final preferAbove = spaceAbove > spaceBelow;
    final preferLeft = spaceLeft > spaceRight;

    // Default to position parameter if enough space, otherwise adjust
    switch (position) {
      case TooltipPosition.top:
        dx = target.center.dx - tooltip.width / 2;
        dy = target.top - tooltip.height - padding;
        if (dy < padding && spaceBelow > spaceAbove) {
          dy = target.bottom + padding;
        }
        break;
      case TooltipPosition.bottom:
        dx = target.center.dx - tooltip.width / 2;
        dy = target.bottom + padding;
        if (dy + tooltip.height > screen.height - padding && spaceAbove > spaceBelow) {
          dy = target.top - tooltip.height - padding;
        }
        break;
      case TooltipPosition.left:
        dx = target.left - tooltip.width - padding;
        dy = target.center.dy - tooltip.height / 2;
        if (dx < padding && spaceRight > spaceLeft) {
          dx = target.right + padding;
        }
        break;
      case TooltipPosition.right:
        dx = target.right + padding;
        dy = target.center.dy - tooltip.height / 2;
        if (dx + tooltip.width > screen.width - padding && spaceLeft > spaceRight) {
          dx = target.left - tooltip.width - padding;
        }
        break;
      case TooltipPosition.auto:
        // Auto-select best position
        if (preferAbove && spaceAbove >= tooltip.height + padding) {
          dx = target.center.dx - tooltip.width / 2;
          dy = target.top - tooltip.height - padding;
        } else if (spaceBelow >= tooltip.height + padding) {
          dx = target.center.dx - tooltip.width / 2;
          dy = target.bottom + padding;
        } else if (preferLeft && spaceLeft >= tooltip.width + padding) {
          dx = target.left - tooltip.width - padding;
          dy = target.center.dy - tooltip.height / 2;
        } else if (spaceRight >= tooltip.width + padding) {
          dx = target.right + padding;
          dy = target.center.dy - tooltip.height / 2;
        } else {
          // Fallback: center at bottom
          dx = target.center.dx - tooltip.width / 2;
          dy = target.bottom + padding;
        }
        break;
    }

    // Constrain to screen bounds
    dx = dx.clamp(padding, screen.width - tooltip.width - padding);
    dy = dy.clamp(padding, screen.height - tooltip.height - padding);

    return Offset(dx, dy);
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect spotlightRect;
  final double spotlightRadius;
  final Animation<double> pulseAnimation;
  final Color accentColor;

  _SpotlightPainter({
    required this.spotlightRect,
    required this.spotlightRadius,
    required this.pulseAnimation,
    required this.accentColor,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw dark overlay with hole
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        spotlightRect,
        Radius.circular(spotlightRadius),
      ))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw pulsing border
    final pulseValue = pulseAnimation.value;
    final pulseWidth = 3.0 + (2.0 * math.sin(pulseValue * math.pi * 2));
    final pulseOpacity = 0.7 + (0.3 * math.sin(pulseValue * math.pi * 2));

    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = pulseWidth
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final rRect = RRect.fromRectAndRadius(
      spotlightRect.inflate(pulseWidth / 2),
      Radius.circular(spotlightRadius + pulseWidth / 2),
    );

    canvas.drawRRect(rRect, borderPaint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) {
    return oldDelegate.spotlightRect != spotlightRect ||
        oldDelegate.accentColor != accentColor;
  }
}

class _TooltipCard extends StatelessWidget {
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final Color accentColor;
  final TooltipPosition position;

  const _TooltipCard({
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
    required this.accentColor,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIconForPosition(),
                  color: accentColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  onDismiss();
                  onAction!();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  minimumSize: const Size.fromHeight(36),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIconForPosition() {
    switch (position) {
      case TooltipPosition.top:
        return Icons.arrow_downward_rounded;
      case TooltipPosition.bottom:
        return Icons.arrow_upward_rounded;
      case TooltipPosition.left:
        return Icons.arrow_forward_rounded;
      case TooltipPosition.right:
        return Icons.arrow_back_rounded;
      case TooltipPosition.auto:
        return Icons.touch_app_rounded;
    }
  }
}

/// Position for the tooltip relative to its target.
enum TooltipPosition {
  top,
  bottom,
  left,
  right,
  auto,
}

/// Service for tracking which discovery tooltips have been shown.
class DiscoveryTooltipService {
  final Set<String> _shownFeatures = {};

  bool hasShown(String featureKey) {
    return _shownFeatures.contains(featureKey);
  }

  void markAsShown(String featureKey) {
    _shownFeatures.add(featureKey);
    // Persist to storage
  }

  void reset() {
    _shownFeatures.clear();
    // Clear storage
  }
}

/// Global discovery tooltip service instance.
final discoveryTooltipService = DiscoveryTooltipService();
