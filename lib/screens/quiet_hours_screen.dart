import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class QuietHoursScreen extends ConsumerWidget {
  const QuietHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Quiet Hours Automation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: state.quietHoursEnabled,
                  title: const Text('Enable Quiet Hours'),
                  subtitle: const Text(
                    'Pause low-priority campaigns after your chosen cutoff time.',
                  ),
                  onChanged: notifier.setQuietHoursEnabled,
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: 'Promotions only',
                  groupValue: state.quietHoursScope,
                  title: const Text('Promotions only'),
                  subtitle: const Text('Leave order updates and returns untouched.'),
                  onChanged: (value) => notifier.setQuietHoursScope(value!),
                ),
                RadioListTile<String>(
                  value: 'Marketing and deals',
                  groupValue: state.quietHoursScope,
                  title: const Text('Marketing and deals'),
                  subtitle: const Text(
                    'Mute promos, restock nudges, and merchandising prompts.',
                  ),
                  onChanged: (value) => notifier.setQuietHoursScope(value!),
                ),
                RadioListTile<String>(
                  value: 'Everything except critical',
                  groupValue: state.quietHoursScope,
                  title: const Text('Everything except critical'),
                  subtitle: const Text(
                    'Keep fraud, delivery, and payment failures flowing.',
                  ),
                  onChanged: (value) => notifier.setQuietHoursScope(value!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE7F6),
              child: Icon(Icons.rule_folder, color: Colors.deepPurple),
            ),
            title: const Text('Advanced Windows'),
            subtitle: const Text(
              'Build blackout windows, assign recurrence, and review edge cases.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(
              '/profile/settings/notifications/channels/quiet-hours/windows',
            ),
          ),
        ],
      ),
    );
  }
}
