import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class NotificationChannelsScreen extends ConsumerWidget {
  const NotificationChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Channel Matrix')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: state.smsBackupEnabled,
                  title: const Text('SMS Backup Channel'),
                  subtitle: const Text(
                    'Fallback for delivery exceptions and payment issues.',
                  ),
                  onChanged: notifier.setSmsBackupEnabled,
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: 'Push first',
                  groupValue: state.reminderStyle,
                  title: const Text('Push first'),
                  subtitle: const Text('Use push before escalating to email.'),
                  onChanged: (value) => notifier.setReminderStyle(value!),
                ),
                RadioListTile<String>(
                  value: 'Email first',
                  groupValue: state.reminderStyle,
                  title: const Text('Email first'),
                  subtitle: const Text('Best for low-noise reminder journeys.'),
                  onChanged: (value) => notifier.setReminderStyle(value!),
                ),
                RadioListTile<String>(
                  value: 'Push and email',
                  groupValue: state.reminderStyle,
                  title: const Text('Push and email'),
                  subtitle: const Text(
                    'Send a multi-channel burst for cart and stock events.',
                  ),
                  onChanged: (value) => notifier.setReminderStyle(value!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Advanced Routing',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE7F6),
              child: Icon(Icons.bedtime, color: Colors.deepPurple),
            ),
            title: const Text('Quiet Hours Automation'),
            subtitle: Text(
              state.quietHoursEnabled
                  ? 'Enabled for ${state.quietHoursScope}'
                  : 'Disabled',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(
              '/profile/settings/notifications/channels/quiet-hours',
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.calendar_month, color: Colors.blue),
            ),
            title: const Text('Calendar Binding'),
            subtitle: Text(state.calendarName),
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
