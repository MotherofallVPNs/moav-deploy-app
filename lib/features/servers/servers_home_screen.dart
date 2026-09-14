import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import 'add_server_screen.dart';
import 'servers_provider.dart';

class ServersHomeScreen extends ConsumerWidget {
  const ServersHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('MoaV Deploy')),
      body: servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load servers: $e')),
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _ServerTile(profile: list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(AddServerScreen.route()),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 56),
            const SizedBox(height: 16),
            Text('No servers yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Add a server to install and manage MoaV on it. '
              'Credentials stay on this device.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _TileAction { test, remove }

class _ServerTile extends ConsumerWidget {
  const _ServerTile({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = switch (profile.authMethod) {
      SshAuthMethod.generatedKey || SshAuthMethod.importedKey => 'key',
      SshAuthMethod.password => 'password',
    };
    return ListTile(
      leading: const Icon(Icons.dns),
      title: Text(profile.label),
      subtitle: Text('${profile.username}@${profile.host}:${profile.port} · $auth'),
      trailing: PopupMenuButton<_TileAction>(
        onSelected: (a) => switch (a) {
          _TileAction.test => _testConnection(context, ref),
          _TileAction.remove => _confirmRemove(context, ref),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _TileAction.test,
            child: ListTile(
              leading: Icon(Icons.network_check),
              title: Text('Test connection'),
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
    );
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Connecting to ${profile.label}…')),
    );
    final ConnectionCheck check =
        await ref.read(moavControllerProvider(profile.id)).ping();
    messenger.hideCurrentSnackBar();
    final text = !check.reachable
        ? 'Could not connect: ${check.error ?? 'unknown error'}'
        : check.moavInstalled == true
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
