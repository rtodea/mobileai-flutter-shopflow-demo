import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/preferences_provider.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: state.pushNotificationsEnabled,
                  title: const Text('Push Notifications'),
                  subtitle: const Text(
                    'Master switch for alerts, nudges, and assistant reminders.',
                  ),
                  onChanged: notifier.setPushNotificationsEnabled,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: state.emailDigestEnabled,
                  title: const Text('Email Digest'),
                  subtitle: const Text('Receive morning and evening summaries.'),
                  onChanged: notifier.setEmailDigestEnabled,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: state.inAppBannersEnabled,
                  title: const Text('In-App Banners'),
                  subtitle: const Text(
                    'Show promotional banners while browsing the storefront.',
                  ),
                  onChanged: notifier.setInAppBannersEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Delivery Style',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Live', label: Text('Live')),
              ButtonSegment(value: 'Smart Digest', label: Text('Smart Digest')),
              ButtonSegment(value: 'Daily Summary', label: Text('Daily Summary')),
            ],
            selected: <String>{state.digestMode},
            onSelectionChanged: (selection) {
              notifier.setDigestMode(selection.first);
            },
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE7F6),
              child: Icon(Icons.tune, color: Colors.deepPurple),
            ),
            title: const Text('Preset Bundle'),
            subtitle: Text(state.presetBundle),
            trailing: const Icon(Icons.expand_more),
            onTap: () => _showPresetSheet(context, notifier, state.presetBundle),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Muted Topic Buckets'),
            subtitle: Text('${state.mutedTopics.length} categories muted'),
            children: [
              for (final topic in _topics)
                CheckboxListTile(
                  value: state.mutedTopics.contains(topic),
                  onChanged: (_) => notifier.toggleMutedTopic(topic),
                  title: Text(topic),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/profile/settings/notifications/channels'),
            icon: const Icon(Icons.alt_route),
            label: const Text('Open Channel Matrix'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPresetSheet(
    BuildContext context,
    NotificationPreferencesNotifier notifier,
    String selectedPreset,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            var currentPreset = selectedPreset;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notification Presets',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a ready-made bundle before drilling into advanced rules.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final preset in _presets)
                        ChoiceChip(
                          label: Text(preset),
                          selected: currentPreset == preset,
                          onSelected: (_) {
                            setModalState(() => currentPreset = preset);
                            notifier.setPresetBundle(preset);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Preset Notes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ..._presetNotes.entries.map(
                    (entry) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key),
                      subtitle: Text(entry.value),
                      trailing: entry.key == currentPreset
                          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

const _presets = <String>['Minimal', 'Balanced', 'High Touch'];
const _topics = <String>[
  'Flash deals',
  'Style picks',
  'Back in stock',
  'Cart nudges',
  'Recommended bundles',
];
const _presetNotes = <String, String>{
  'Minimal': 'Essential order updates and payment alerts only.',
  'Balanced': 'Orders, inventory changes, and one daily merch digest.',
  'High Touch': 'Real-time promos, drops, bundles, and recovery reminders.',
};
