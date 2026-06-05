import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/profile/settings'),
          )
        ],
      ),
      body: ListView(
        children: [
          Container(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.deepPurple,
                  child: Text('JD', style: TextStyle(fontSize: 24, color: Colors.white)),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('John Doe', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('john.doe@example.com', style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuSection(
            title: 'Orders',
            items: [
              _MenuItem(icon: Icons.receipt_long, title: 'Order History', onTap: () => _showNotImplemented(context)),
              _MenuItem(icon: Icons.local_shipping, title: 'Track Order', onTap: () => _showNotImplemented(context)),
              _MenuItem(icon: Icons.assignment_return, title: 'Returns & Refunds', onTap: () => _showNotImplemented(context)),
            ],
          ),
          _buildMenuSection(
            title: 'Account Settings',
            items: [
              _MenuItem(icon: Icons.person_outline, title: 'Personal Information', onTap: () => context.push('/profile/settings')),
              _MenuItem(icon: Icons.location_on_outlined, title: 'Shipping Addresses', onTap: () => _showNotImplemented(context)),
              _MenuItem(icon: Icons.payment, title: 'Payment Methods', onTap: () => _showNotImplemented(context)),
              _MenuItem(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                onTap: () => context.push('/profile/settings/notifications'),
              ),
            ],
          ),
          _buildMenuSection(
            title: 'Support',
            items: [
              _MenuItem(icon: Icons.help_outline, title: 'Help Center', onTap: () => _showNotImplemented(context)),
              _MenuItem(icon: Icons.chat_bubble_outline, title: 'Contact Support', onTap: () => _showNotImplemented(context)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out!')));
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMenuSection({required String title, required List<_MenuItem> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        ...items.map((item) => ListTile(
              leading: Icon(item.icon, color: Colors.deepPurple),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: item.onTap,
            )),
        const Divider(),
      ],
    );
  }

  void _showNotImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feature not implemented yet')));
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  _MenuItem({required this.icon, required this.title, required this.onTap});
}
