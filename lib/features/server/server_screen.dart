import 'package:flutter/material.dart';

import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../deploy/deploy_screen.dart';
import '../operate/operate_screen.dart';
import '../users/users_screen.dart';

/// Hub for one server: everything the app can do with it.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => ServerScreen(profile: profile));

  @override
  Widget build(BuildContext context) {
    final auth = switch (profile.authMethod) {
      SshAuthMethod.generatedKey => 'device key',
      SshAuthMethod.importedKey => 'imported key',
      SshAuthMethod.password => 'password',
    };
    return MoavScaffold(
      appBar: AppBar(title: Text(profile.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          MoavCard(
            accent: true,
            child: Row(
              children: [
                const IconBadge(Icons.dns_outlined, size: 46, gradient: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${profile.username}@${profile.host}',
                        style: moavMono(size: 14, weight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'port ${profile.port} · ssh',
                        style: moavMono(
                          size: 12,
                          weight: FontWeight.w400,
                          color: MoavColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  auth,
                  tone: profile.authMethod == SshAuthMethod.password
                      ? StatusTone.warn
                      : StatusTone.accent,
                  dot: false,
                ),
              ],
            ),
          ),
          const SectionHeader('Manage'),
          _HubTile(
            icon: Icons.people_outline,
            title: 'Users',
            subtitle: 'Add, revoke, share bundles and QR codes',
            onTap: () => Navigator.of(context).push(UsersScreen.route(profile)),
          ),
          _HubTile(
            icon: Icons.settings_outlined,
            title: 'Services',
            subtitle: 'Start, stop, restart; regenerate user bundles',
            onTap: () => Navigator.of(context).push(OperateScreen.route(profile)),
          ),
          _HubTile(
            icon: Icons.monitor_heart_outlined,
            title: 'Health',
            subtitle: 'moav doctor, check by check',
            onTap: () => Navigator.of(context)
                .push(OperateScreen.route(profile, tab: OperateTab.health)),
          ),
          _HubTile(
            icon: Icons.insights_outlined,
            title: 'Analytics',
            subtitle: 'Headline metrics, protocol status and Grafana',
            onTap: () => Navigator.of(context)
                .push(OperateScreen.route(profile, tab: OperateTab.monitoring)),
          ),
          const SectionHeader('Install'),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MoavCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            IconBadge(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: MoavColors.textMuted),
          ],
        ),
      ),
    );
  }
}
