import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum HighlightAction { tap, read, type, verify, scroll, fill, wait }

const _actionGlyph = <HighlightAction, String>{
  HighlightAction.tap: '›',
  HighlightAction.read: '◉',
  HighlightAction.type: '⌨',
  HighlightAction.verify: '✓',
  HighlightAction.scroll: '↕',
  HighlightAction.fill: '✎',
  HighlightAction.wait: '⏱',
};

const _actionFallbackLabel = <HighlightAction, String>{
  HighlightAction.tap: 'Tap',
  HighlightAction.read: 'Reading',
  HighlightAction.type: 'Typing',
  HighlightAction.verify: 'Verifying',
  HighlightAction.scroll: 'Scrolling',
  HighlightAction.fill: 'Filling',
  HighlightAction.wait: 'Working',
};

class HighlightEventData {
  final double pageX;
  final double pageY;
  final double width;
  final double height;
  final String message;
  final HighlightAction? action;
  final int autoRemoveAfterMs;
  final bool borderOnly;

  const HighlightEventData({
    required this.pageX,
    required this.pageY,
    required this.width,
    required this.height,
    this.message = '',
    this.action,
    this.autoRemoveAfterMs = 5000,
    this.borderOnly = false,
  });
}

class HighlightController {
  static final _controller = StreamController<HighlightEventData?>.broadcast();

  static Stream<HighlightEventData?> get stream => _controller.stream;

  static void show(HighlightEventData data) => _controller.add(data);

  static void dismiss() => _controller.add(null);
}

/// Event-driven highlight overlay matching the React Native SDK.
///
/// Place this widget at the top of your widget tree (inside an Overlay or Stack).
/// It listens to [HighlightController.stream] for highlight events.
class ActionHighlightOverlay extends StatefulWidget {
  const ActionHighlightOverlay({super.key});

  @override
  State<ActionHighlightOverlay> createState() => _ActionHighlightOverlayState();
}

class _ActionHighlightOverlayState extends State<ActionHighlightOverlay>
    with TickerProviderStateMixin {
  HighlightEventData? _highlight;
  StreamSubscription<HighlightEventData?>? _sub;
  Timer? _dismissTimer;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _tipController;

  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _tipFadeAnim;
  late Animation<double> _tipSlideAnim;

  double _tooltipWidth = 0;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_fadeController);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _tipFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _tipController, curve: Curves.easeOut),
    );
    _tipSlideAnim = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(parent: _tipController, curve: Curves.easeOut),
    );

    _sub = HighlightController.stream.listen(_onEvent);
  }

  void _onEvent(HighlightEventData? data) {
    _dismissTimer?.cancel();
    _pulseController.stop();

    if (data == null) {
      _dismiss();
      return;
    }

    setState(() {
      _highlight = data;
      _tooltipWidth = 0;
    });

    _fadeController.value = 0;
    _tipController.value = 0;

    _fadeController.forward().then((_) {
      if (!mounted || data.borderOnly) return;
      _pulseController.repeat(reverse: true);
    });

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _tipController.forward();
    });

    _dismissTimer = Timer(
      Duration(milliseconds: data.autoRemoveAfterMs),
      _dismiss,
    );
  }

  void _dismiss() {
    _pulseController.stop();
    _fadeController.reverse().then((_) {
      if (mounted) setState(() => _highlight = null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _tipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_highlight == null) return const SizedBox.shrink();

    final h = _highlight!;
    final screenW = MediaQuery.sizeOf(context).width;

    const pad = 4.0;
    final ringLeft = h.pageX - pad;
    final ringTop = h.pageY - pad;
    final ringW = h.width + pad * 2;
    final ringH = h.height + pad * 2;

    final isTooHigh = h.pageY < 80;
    const tipH = 38.0;
    const tipGap = 10.0;
    final tooltipTop =
        isTooHigh ? ringTop + ringH + tipGap : ringTop - tipH - tipGap;

    var tooltipLeft = ringLeft + ringW / 2 - _tooltipWidth / 2;
    tooltipLeft = math.max(10, math.min(tooltipLeft, screenW - _tooltipWidth - 10));

    final label =
        h.message.isNotEmpty ? h.message : (h.action != null ? _actionFallbackLabel[h.action]! : '');
    final glyph = h.action != null ? _actionGlyph[h.action] : null;

    return Positioned.fill(
      child: Stack(
        children: [
          // Tap-to-dismiss zone
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // Pulsing ring
          AnimatedBuilder(
            animation: Listenable.merge([_fadeAnim, _pulseAnim]),
            builder: (context, _) {
              final scale = _pulseAnim.value;
              final scaledW = ringW * scale;
              final scaledH = ringH * scale;
              final dx = ringLeft - (scaledW - ringW) / 2;
              final dy = ringTop - (scaledH - ringH) / 2;

              return Positioned(
                left: dx,
                top: dy,
                child: Opacity(
                  opacity: _fadeAnim.value,
                  child: Container(
                    width: scaledW,
                    height: scaledH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF007AFF),
                        width: 3,
                      ),
                      color: h.borderOnly ? null : const Color(0x26007AFF),
                    ),
                  ),
                ),
              );
            },
          ),

          // Tooltip
          AnimatedBuilder(
            animation: Listenable.merge([_tipFadeAnim, _tipSlideAnim]),
            builder: (context, child) {
              final slideDir = isTooHigh ? 1.0 : -1.0;
              return Positioned(
                top: tooltipTop + _tipSlideAnim.value * slideDir,
                left: _tooltipWidth > 0 ? tooltipLeft : null,
                child: Opacity(
                  opacity: _tipFadeAnim.value,
                  child: child,
                ),
              );
            },
            child: _buildTooltip(label, glyph, isTooHigh, screenW),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltip(
    String label,
    String? glyph,
    bool isTooHigh,
    double screenW,
  ) {
    return UnconstrainedBox(
      child: _TooltipMeasurer(
        onMeasured: (width) {
          if (_tooltipWidth != width) {
            setState(() => _tooltipWidth = width);
          }
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: screenW * 0.8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0x38FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    glyph,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (label.isNotEmpty)
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TooltipMeasurer extends StatefulWidget {
  final ValueChanged<double> onMeasured;
  final Widget child;

  const _TooltipMeasurer({required this.onMeasured, required this.child});

  @override
  State<_TooltipMeasurer> createState() => _TooltipMeasurerState();
}

class _TooltipMeasurerState extends State<_TooltipMeasurer> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(_) {
    final box = _key.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      widget.onMeasured(box.size.width);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(key: _key, child: widget.child);
  }
}
