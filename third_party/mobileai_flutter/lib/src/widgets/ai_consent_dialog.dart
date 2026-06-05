import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _consentStorageKey = '@mobileai_flutter_ai_consent_granted';

class AIConsentConfig {
  final bool required;
  final bool persist;
  final String? title;
  final String? body;
  final String? privacyPolicyUrl;
  final String? providerLabel;
  final VoidCallback? onConsent;
  final VoidCallback? onDecline;

  const AIConsentConfig({
    this.required = true,
    this.persist = true,
    this.title,
    this.body,
    this.privacyPolicyUrl,
    this.providerLabel,
    this.onConsent,
    this.onDecline,
  });
}

class AIConsentController {
  const AIConsentController._();

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentStorageKey) ?? false;
  }

  static Future<void> grant({bool persist = true}) async {
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentStorageKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_consentStorageKey);
  }
}

class AIConsentDialog extends StatelessWidget {
  final bool visible;
  final String providerName;
  final AIConsentConfig config;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const AIConsentDialog({
    super.key,
    required this.visible,
    required this.providerName,
    required this.config,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final title = config.title ?? 'AI Assistant';
    final providerLabel = config.providerLabel ?? providerName;
    final body =
        config.body ??
        'This assistant may send your message and relevant screen context to $providerLabel to help complete tasks and answer questions.';

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Text(
                      'Shared with the AI provider: your message and relevant visible app context needed to answer or act.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onDecline,
                          child: const Text('Not now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: onAccept,
                          child: const Text('Allow AI'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AIConsentInlineCard extends StatelessWidget {
  final String providerName;
  final AIConsentConfig config;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const AIConsentInlineCard({
    super.key,
    required this.providerName,
    required this.config,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final title = config.title ?? 'AI Assistant';
    final providerLabel = config.providerLabel ?? providerName;
    final body =
        config.body ??
        'This assistant may send your message and relevant screen context to $providerLabel to help complete tasks and answer questions.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Assistant',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Text(
              'Shared with the AI provider: your message and relevant visible app context needed to answer or act.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B68EE),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Allow AI'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
