import 'package:flutter/material.dart';

/// AgentOverlay — Subtle thinking indicator shown while the AI agent is
/// processing. Floats at the top of the screen over all content.
/// Mirrors react-native-agentic-ai's AgentOverlay component.
class AgentOverlay extends StatelessWidget {
  final bool visible;
  final String statusText;
  final VoidCallback? onCancel;

  const AgentOverlay({
    super.key,
    required this.visible,
    required this.statusText,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.5),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: visible
          ? Align(
              key: const ValueKey('overlay'),
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ThinkingPill(
                    statusText: statusText,
                    onCancel: onCancel,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

class _ThinkingPill extends StatelessWidget {
  final String statusText;
  final VoidCallback? onCancel;

  const _ThinkingPill({required this.statusText, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE61A1A2E), // rgba(26, 26, 46, 0.9)
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              statusText.isNotEmpty ? statusText : 'Thinking...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
