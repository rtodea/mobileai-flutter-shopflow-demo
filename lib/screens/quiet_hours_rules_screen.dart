import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class QuietHoursRulesScreen extends ConsumerWidget {
  const QuietHoursRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Windows')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  value: state.criticalAlertsBypass,
                  title: const Text('Critical Alerts Bypass Quiet Hours'),
                  subtitle: const Text(
                    'Always deliver fraud, payment, and delivery failure updates.',
                  ),
                  onChanged: (value) =>
                      notifier.setCriticalAlertsBypass(value ?? false),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Recurrence Pattern'),
                  subtitle: Text(state.recurrence),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: DropdownButtonFormField<String>(
                    value: state.recurrence,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Weekdays',
                        child: Text('Weekdays'),
                      ),
                      DropdownMenuItem(
                        value: 'Weekends',
                        child: Text('Weekends'),
                      ),
                      DropdownMenuItem(
                        value: 'Every day',
                        child: Text('Every day'),
                      ),
                      DropdownMenuItem(
                        value: 'Custom shopping calendar',
                        child: Text('Custom shopping calendar'),
                      ),
                    ],
                    onChanged: (value) => notifier.setRecurrence(value!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ExpansionTile(
            initiallyExpanded: true,
            title: const Text('Muted Buckets During Quiet Hours'),
            subtitle: Text('${state.mutedTopics.length} categories selected'),
            children: [
              for (final topic in _ruleTopics)
                CheckboxListTile(
                  value: state.mutedTopics.contains(topic),
                  title: Text(topic),
                  onChanged: (_) => notifier.toggleMutedTopic(topic),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push(
              '/profile/settings/notifications/channels/quiet-hours/windows/schedule',
            ),
            icon: const Icon(Icons.calendar_today),
            label: const Text('Open Schedule Builder'),
          ),
        ],
      ),
    );
  }
}

const _ruleTopics = <String>[
  'Flash deals',
  'Back in stock',
  'Cart nudges',
  'Price drops',
  'New arrival spotlights',
];
