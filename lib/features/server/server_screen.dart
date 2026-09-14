import 'package:flutter/material.dart';

import '../../core/server_profile.dart';
import '../deploy/deploy_screen.dart';
import '../users/users_screen.dart';

/// Hub for one server: everything the app can do with it.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => ServerScreen(profile: profile));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(profile.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${profile.username}@${profile.host}:${profile.port}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _HubTile(
            icon: Icons.people_outline,
            title: 'Users',
            subtitle: 'Add, revoke, share bundles and QR codes',
            onTap: () => Navigator.of(context).push(UsersScreen.route(profile)),
          ),
          _HubTile(
            icon: Icons.rocket_launch_outlined,
            title: 'Deploy',
            subtitle: 'Install or re-run MoaV setup (idempotent)',
            onTap: () => Navigator.of(context).push(DeployScreen.route(profile)),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
