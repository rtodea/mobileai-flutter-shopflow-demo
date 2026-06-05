import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class QuietHoursScheduleScreen extends ConsumerWidget {
  const QuietHoursScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Builder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Effective From'),
                  subtitle: Text(_formatDate(state.effectiveFrom)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: state.effectiveFrom,
                      firstDate: DateTime(2026, 1, 1),
                      lastDate: DateTime(2027, 12, 31),
                    );
                    if (selected != null) {
                      notifier.setEffectiveFrom(selected);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: const Text('Start Time'),
                  subtitle: Text(state.startTime.format(context)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: state.startTime,
                    );
                    if (selected != null) {
                      notifier.setStartTime(selected);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('End Time'),
                  subtitle: Text(state.endTime.format(context)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: state.endTime,
                    );
                    if (selected != null) {
                      notifier.setEndTime(selected);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: state.calendarName,
            decoration: const InputDecoration(
              labelText: 'Calendar Source',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Primary', child: Text('Primary')),
              DropdownMenuItem(value: 'Launch Calendar', child: Text('Launch Calendar')),
              DropdownMenuItem(value: 'Promo Freeze Calendar', child: Text('Promo Freeze Calendar')),
            ],
            onChanged: (value) => notifier.setCalendarName(value!),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Push first', label: Text('Push first')),
              ButtonSegment(value: 'Email first', label: Text('Email first')),
              ButtonSegment(value: 'Push and email', label: Text('Push and email')),
            ],
            selected: <String>{state.reminderStyle},
            onSelectionChanged: (selection) {
              notifier.setReminderStyle(selection.first);
            },
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: state.previewSummary,
            onChanged: (value) => notifier.setPreviewSummary(value ?? false),
            title: const Text('Generate preview summary before saving'),
            subtitle: const Text(
              'Shows a final review modal with all quiet-hours decisions.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.push(
              '/profile/settings/notifications/channels/quiet-hours/windows/schedule/review',
            ),
            child: const Text('Review Automation'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
