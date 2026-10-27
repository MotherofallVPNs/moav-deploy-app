import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import '../admin/admin_panel_screen.dart';
import '../deploy/deploy_screen.dart';
import '../operate/operate_screen.dart';
import '../servers/servers_provider.dart';
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
      SshAuthMethod.generatedKey => 'key',
      SshAuthMethod.importedKey => 'imported key',
      SshAuthMethod.password => 'password',
    };
    return MoavScaffold(
      appBar: MoavAppBar(title: Text(profile.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          MoavCard(
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const IconBadge(
                      Icons.dns_outlined,
                      size: 46,
                      gradient: true,
                    ),
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
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 4),
                _ConnectionRow(profile: profile),
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
          _HubTile(
            icon: Icons.dns_outlined,
            title: 'Server info',
            subtitle: 'CPU, RAM, disk, versions and MoaV updates',
            onTap: () => Navigator.of(context)
                .push(OperateScreen.route(profile, tab: OperateTab.server)),
          ),
          _HubTile(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Admin dashboard',
            subtitle: 'The MoaV web panel, through this SSH connection',
            onTap: () =>
                Navigator.of(context).push(AdminPanelScreen.route(profile)),
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

/// "Check connection" with the result shown inline: a green pill when the
/// server answers, a quiet notice stating the cause when it does not.
class _ConnectionRow extends ConsumerStatefulWidget {
  const _ConnectionRow({required this.profile});

  final ServerProfile profile;

  @override
  ConsumerState<_ConnectionRow> createState() => _ConnectionRowState();
}

class _ConnectionRowState extends ConsumerState<_ConnectionRow> {
  bool _checking = false;
  ConnectionCheck? _result;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final check = await ref
        .read(moavControllerProvider(widget.profile.id))
        .ping();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = check;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final Widget status;
    if (_checking) {
      status = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Connecting…', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    } else if (r == null) {
      status = Text(
        'Not checked yet',
        style: Theme.of(context).textTheme.bodySmall,
      );
    } else if (!r.reachable) {
      status = ConnectionNotice(
        error: r.failure ?? r.error ?? 'Could not connect.',
      );
    } else {
      final label = r.moavInstalled == true
          ? 'Connected. MoaV ${r.moavVersion ?? ''} is installed.'
          : r.moavInstalled == false
          ? 'Connected. MoaV is not installed yet.'
          : 'Connected.';
      status = Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: MoavColors.pass),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.replaceAll('  ', ' '),
              style: const TextStyle(color: MoavColors.text, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(padding: const EdgeInsets.only(top: 8), child: status),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _checking ? null : _check,
          icon: const Icon(Icons.network_check, size: 16),
          label: const Text('Check connection'),
        ),
      ],
    );
  }
}
