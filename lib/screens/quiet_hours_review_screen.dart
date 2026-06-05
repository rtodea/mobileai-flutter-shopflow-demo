import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class QuietHoursReviewScreen extends ConsumerWidget {
  const QuietHoursReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review Quiet Hours')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReviewCard(
            title: 'Delivery Summary',
            rows: [
              _ReviewRow('Push Notifications', state.pushNotificationsEnabled ? 'Enabled' : 'Disabled'),
              _ReviewRow('Digest Mode', state.digestMode),
              _ReviewRow('Preset Bundle', state.presetBundle),
              _ReviewRow('Reminder Style', state.reminderStyle),
            ],
          ),
          const SizedBox(height: 16),
          _ReviewCard(
            title: 'Quiet Hours Window',
            rows: [
              _ReviewRow('Scope', state.quietHoursScope),
              _ReviewRow('Recurrence', state.recurrence),
              _ReviewRow('Effective From', _formatDate(state.effectiveFrom)),
              _ReviewRow('Start Time', state.startTime.format(context)),
              _ReviewRow('End Time', state.endTime.format(context)),
            ],
          ),
          const SizedBox(height: 16),
          _ReviewCard(
            title: 'Muted Topic Buckets',
            rows: state.mutedTopics
                .map((topic) => _ReviewRow(topic, 'Muted'))
                .toList(growable: false),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showConfirmationDialog(context),
            icon: const Icon(Icons.check_circle),
            label: const Text('Activate Quiet Hours'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back to Schedule'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConfirmationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Activate Quiet Hours Automation'),
          content: const Text(
            'This will save the channel matrix, quiet-hours rules, and future schedule window for your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not Yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Activate'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quiet hours automation activated for this profile.'),
        ),
      );
      context.go('/profile');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final List<_ReviewRow> rows;

  const _ReviewCard({
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow {
  final String label;
  final String value;

  const _ReviewRow(this.label, this.value);
}
