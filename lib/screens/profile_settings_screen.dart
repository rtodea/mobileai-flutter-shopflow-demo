import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _darkMode = false;
  double _volume = 50;
  DateTime? _birthDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE7F6),
              child: Icon(Icons.notifications_active, color: Colors.deepPurple),
            ),
            title: const Text('Notifications'),
            subtitle: const Text(
              'Open the advanced notification lab with channels, quiet hours, and review flows.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/settings/notifications'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: (val) => setState(() => _darkMode = val),
          ),
          const SizedBox(height: 16),
          const Text('Alert Volume', style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: _volume,
            min: 0,
            max: 100,
            divisions: 10,
            label: _volume.round().toString(),
            onChanged: (val) => setState(() => _volume = val),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Birth Date'),
            subtitle: Text(_birthDate != null ? "${_birthDate!.toLocal()}".split(' ')[0] : 'Not set'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() => _birthDate = date);
              }
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Appearance Preset'),
            subtitle: const Text('Open a bottom sheet with quick visual presets'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAppearancePresetSheet(context),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved Settings successfully')),
              );
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppearancePresetSheet(BuildContext context) {
    String selected = 'Midnight Contrast';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appearance Presets',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This bottom sheet exists to stress-test the agent on layered UI surfaces.',
                  ),
                  const SizedBox(height: 16),
                  for (final preset in _appearancePresets)
                    RadioListTile<String>(
                      value: preset,
                      groupValue: selected,
                      title: Text(preset),
                      onChanged: (value) {
                        setModalState(() => selected = value!);
                      },
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

const _appearancePresets = <String>[
  'Midnight Contrast',
  'Soft Lavender',
  'Monochrome Minimal',
];
