import 'package:flutter/material.dart';

import '../core/types.dart';

class AIApprovalInlineCard extends StatelessWidget {
  final AskUserRequest? request;
  final VoidCallback onGrant;
  final VoidCallback onDeny;

  const AIApprovalInlineCard({
    super.key,
    required this.request,
    required this.onGrant,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    if (request == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _buildHint(request!),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Don’t Allow',
                  isPrimary: false,
                  onPressed: onDeny,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Allow',
                  isPrimary: true,
                  onPressed: onGrant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildHint(AskUserRequest request) {
    return 'The AI agent is requesting permission to perform this action. Tap "Allow" to approve, or "Don’t Allow" to cancel.';
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFF7B68EE)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isPrimary
                ? Colors.white
                : Colors.white.withValues(alpha: 0.82),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
