import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/rich_ui_theme.dart';

/// ProactiveHint — Context-aware hint that appears when user might need help.
///
/// Shows a floating hint card based on triggers like:
/// - Idle time on a screen
/// - Repeated failed actions
/// - Contextual hints for complex screens
class ProactiveHint extends StatefulWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final Duration delay;
  final Duration? autoDismiss;
  final bool showManually;

  const ProactiveHint({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.delay = const Duration(seconds: 2),
    this.autoDismiss,
    this.showManually = false,
  });

  @override
  State<ProactiveHint> createState() => _ProactiveHintState();
}

class _ProactiveHintState extends State<ProactiveHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _showTimer;
  Timer? _dismissTimer;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.showManually) {
      _show();
    } else {
      _showTimer = Timer(widget.delay, _show);
    }
  }

  @override
  void didUpdateWidget(ProactiveHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showManually && !oldWidget.showManually) {
      _show();
    }
  }

  void _show() {
    if (!mounted) return;
    setState(() => _isVisible = true);
    _controller.forward();

    if (widget.autoDismiss != null) {
      _dismissTimer = Timer(widget.autoDismiss!, _dismiss);
    }
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) {
        setState(() => _isVisible = false);
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final theme = RichUiThemeScope.of(context).chat;

    return Positioned.fill(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: _ProactiveHintCard(
                title: widget.title,
                message: widget.message,
                actionLabel: widget.actionLabel,
                onAction: widget.onAction,
                onDismiss: _dismiss,
                accentColor: theme.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProactiveHintCard extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final Color accentColor;

  const _ProactiveHintCard({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lightbulb_outline,
                  color: accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                onDismiss();
                onAction!();
              },
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                minimumSize: const Size.fromHeight(40),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trigger conditions for showing proactive hints.
enum ProactiveTrigger {
  /// Show after being idle on screen for X seconds
  idle,

  /// Show after repeated failed actions
  repeatedFailure,

  /// Show on first visit to a screen
  firstVisit,

  /// Show manually via controller
  manual,
}

/// Controller for programmatically showing proactive hints.
class ProactiveHintController {
  final Map<String, bool> _shownHints = {};
  final Map<String, int> _failureCounts = {};

  bool shouldShowHint(String hintId, ProactiveTrigger trigger) {
    switch (trigger) {
      case ProactiveTrigger.firstVisit:
        return !_shownHints.containsKey(hintId);
      case ProactiveTrigger.repeatedFailure:
        return (_failureCounts[hintId] ?? 0) >= 3;
      case ProactiveTrigger.idle:
      case ProactiveTrigger.manual:
        return true;
    }
  }

  void markHintShown(String hintId) {
    _shownHints[hintId] = true;
  }

  void recordFailure(String hintId) {
    _failureCounts[hintId] = (_failureCounts[hintId] ?? 0) + 1;
  }

  void resetFailure(String hintId) {
    _failureCounts.remove(hintId);
  }

  void clearHistory() {
    _shownHints.clear();
    _failureCounts.clear();
  }
}

/// Widget that manages proactive hints based on user behavior.
class ProactiveHintManager extends StatefulWidget {
  final String hintId;
  final ProactiveTrigger trigger;
  final ProactiveHintController controller;
  final Widget child;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? idleDuration;
  final Color? accentColor;

  const ProactiveHintManager({
    super.key,
    required this.hintId,
    required this.trigger,
    required this.controller,
    required this.child,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.idleDuration,
    this.accentColor,
  });

  @override
  State<ProactiveHintManager> createState() => _ProactiveHintManagerState();
}

class _ProactiveHintManagerState extends State<ProactiveHintManager> {
  Timer? _idleTimer;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    switch (widget.trigger) {
      case ProactiveTrigger.idle:
        if (widget.idleDuration != null) {
          _idleTimer = Timer(widget.idleDuration!, () {
            if (mounted) {
              setState(() => _showHint = true);
            }
          });
        }
        break;
      case ProactiveTrigger.firstVisit:
        if (widget.controller.shouldShowHint(widget.hintId, widget.trigger)) {
          _showHint = true;
          widget.controller.markHintShown(widget.hintId);
        }
        break;
      case ProactiveTrigger.repeatedFailure:
        // Check externally via controller
        break;
      case ProactiveTrigger.manual:
        // Show externally via controller
        break;
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showHint)
          ProactiveHint(
            title: widget.title,
            message: widget.message,
            actionLabel: widget.actionLabel,
            onAction: widget.onAction,
            onDismiss: () => setState(() => _showHint = false),
            showManually: true,
          ),
      ],
    );
  }
}
