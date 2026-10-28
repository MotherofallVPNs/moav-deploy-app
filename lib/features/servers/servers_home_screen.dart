import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_controller.dart';
import '../../core/moav_links.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import '../about/about_screen.dart';
import '../deploy/deploy_screen.dart';
import '../keys/keyring_screen.dart';
import '../operate/grafana_screen.dart';
import '../server/server_screen.dart';
import '../users/users_screen.dart';
import '../wipe/wipe_dialog.dart';
import 'add_server_screen.dart';
import 'edit_server_screen.dart';
import 'servers_provider.dart';

class ServersHomeScreen extends ConsumerWidget {
  const ServersHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);

    return MoavScaffold(
      appBar: MoavAppBar(
        title: const MoavWordmark(suffix: 'Deploy'),
        actions: [
          PopupMenuButton<_HomeAction>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onSelected: (action) =>
                _handleHomeAction(context, ref, action, servers.value?.length),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _HomeAction.keys,
                child: ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text('SSH keys'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.docs,
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('Documentation'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.support,
                child: ListTile(
                  leading: Icon(Icons.favorite_outline),
                  title: Text('Support us'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.about,
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
              _SocialRow(),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _HomeAction.wipe,
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined),
                  title: Text('Emergency wipe'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(serversProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.dns_outlined,
                title: 'No servers yet',
                body:
                    'Add a server to install and manage MoaV on it. '
                    'Credentials stay on this device.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: list.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => i == 0
                    ? SectionHeader(
                        list.length == 1
                            ? '1 server'
                            : '${list.length} servers',
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                      )
                    : _ServerTile(profile: list[i - 1]),
              ),
      ),
      floatingActionButton: MoavFab(
        onPressed: () => Navigator.of(context).push(AddServerScreen.route()),
        icon: Icons.add,
        label: 'Add server',
      ),
    );
  }
}

enum _HomeAction { keys, docs, support, about, github, x, telegram, wipe }

Future<void> _handleHomeAction(
  BuildContext context,
  WidgetRef ref,
  _HomeAction action,
  int? serverCount,
) async {
  switch (action) {
    case _HomeAction.keys:
      await Navigator.of(context).push(KeyringScreen.route());
    case _HomeAction.wipe:
      await showWipeDialog(context, ref, serverCount: serverCount);
    case _HomeAction.docs:
      await _open(MoavLinks.docs);
    case _HomeAction.support:
      await _open(MoavLinks.support);
    case _HomeAction.about:
      await Navigator.of(context).push(AboutScreen.route());
    case _HomeAction.github:
      await _open(MoavLinks.github);
    case _HomeAction.x:
      await _open(MoavLinks.x);
    case _HomeAction.telegram:
      await _open(MoavLinks.telegram);
  }
}

Future<void> _open(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// One menu row with the project's GitHub, X and Telegram as icon buttons.
/// Tapping one closes the menu with that action, like a normal item.
class _SocialRow extends PopupMenuEntry<_HomeAction> {
  const _SocialRow();

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(_HomeAction? value) =>
      value == _HomeAction.github ||
      value == _HomeAction.x ||
      value == _HomeAction.telegram;

  @override
  State<_SocialRow> createState() => _SocialRowState();
}

class _SocialRowState extends State<_SocialRow> {
  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, _HomeAction action) =>
        IconButton(
          icon: Icon(icon),
          tooltip: label,
          onPressed: () => Navigator.pop(context, action),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          button(Icons.code, 'GitHub', _HomeAction.github),
          button(Icons.alternate_email, 'X', _HomeAction.x),
          button(Icons.send_outlined, 'Telegram', _HomeAction.telegram),
        ],
      ),
    );
  }
}

enum _TileAction { test, edit, users, grafana, deploy, remove }

class _ServerTile extends ConsumerWidget {
  const _ServerTile({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (auth, tone) = switch (profile.authMethod) {
      SshAuthMethod.generatedKey ||
      SshAuthMethod.importedKey => ('key', StatusTone.accent),
      SshAuthMethod.password => ('password', StatusTone.warn),
    };
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      onTap: () => Navigator.of(context).push(ServerScreen.route(profile)),
      child: Row(
        children: [
          const IconBadge(Icons.dns_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${profile.username}@${profile.host}:${profile.port}',
                  style: moavMono(size: 12, color: MoavColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(auth, tone: tone, dot: false),
          PopupMenuButton<_TileAction>(
            onSelected: (a) => switch (a) {
              _TileAction.test => _testConnection(context, ref),
              _TileAction.edit => Navigator.of(
                context,
              ).push(EditServerScreen.route(profile)),
              _TileAction.users => Navigator.of(
                context,
              ).push(UsersScreen.route(profile)),
              _TileAction.grafana => Navigator.of(
                context,
              ).push(GrafanaScreen.route(profile)),
              _TileAction.deploy => Navigator.of(
                context,
              ).push(DeployScreen.route(profile)),
              _TileAction.remove => _confirmRemove(context, ref),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _TileAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit server'),
                ),
              ),
              PopupMenuItem(
                value: _TileAction.test,
                child: ListTile(
                  leading: Icon(Icons.network_check),
                  title: Text('Test connection'),
                ),
              ),
              PopupMenuItem(
                value: _TileAction.users,
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('Users'),
                ),
              ),
              PopupMenuItem(
                value: _TileAction.grafana,
                child: ListTile(
                  leading: Icon(Icons.dashboard_outlined),
                  title: Text('Grafana'),
                ),
              ),
              PopupMenuItem(
                value: _TileAction.deploy,
                child: ListTile(
                  leading: Icon(Icons.rocket_launch_outlined),
                  title: Text('Deploy MoaV'),
                ),
              ),
              PopupMenuItem(
                value: _TileAction.remove,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Remove'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Connecting to ${profile.label}…')),
    );
    final ConnectionCheck check = await ref
        .read(moavControllerProvider(profile.id))
        .ping();
    messenger.hideCurrentSnackBar();
    if (!check.reachable) {
      showErrorSnackBar(
        messenger,
        check.failure ?? check.error ?? 'Could not connect.',
        prefix: 'Could not connect.',
      );
      return;
    }
    final text = check.moavInstalled == true
        ? 'Connected. MoaV ${check.moavVersion ?? ''} is installed.'
        : check.moavInstalled == false
        ? 'Connected. MoaV is not installed yet.'
        : 'Connected. ${check.error ?? ''}';
    messenger.showSnackBar(SnackBar(content: Text(text.trim())));
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove server?'),
        content: Text(
          'This deletes the saved credential for ${profile.label} from this '
          'device. The server itself is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(serversProvider.notifier).remove(profile.id);
    }
  }
}
