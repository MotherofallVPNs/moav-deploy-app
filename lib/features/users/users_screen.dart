import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'user_bundle_screen.dart';
import 'users_provider.dart';

/// Lists MoaV users on a server; add / remove; tap for the bundle + QR.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => UsersScreen(profile: profile));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider(profile.id));
    final notifier = ref.read(usersProvider(profile.id).notifier);

    return MoavScaffold(
      appBar: AppBar(
        title: Text('Users · ${profile.label}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: notifier.refresh,
          ),
        ],
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: notifier.refresh),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.people_outline,
                title: 'No users yet',
                body: 'Add one to generate keys and a client bundle.',
              )
            : RefreshIndicator(
                onRefresh: notifier.refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => i == 0
                      ? SectionHeader(
                          '${list.length} ${list.length == 1 ? 'user' : 'users'}',
                          padding: const EdgeInsets.only(top: 4, bottom: 2),
                          trailing: Text(
                            '${list.where((u) => u.bundleReady).length} with bundles',
                            style: moavLabel(size: 10, color: MoavColors.textMuted),
                          ),
                        )
                      : _UserTile(
                          profile: profile,
                          user: list[i - 1],
                          onRemove: () => _confirmRemove(context, ref, list[i - 1]),
                        ),
                ),
              ),
      ),
      floatingActionButton: MoavFab(
        onPressed: () => _addUser(context, ref),
        icon: Icons.person_add_alt_1,
        label: 'Add user',
      ),
    );
  }

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (name == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Creating $name… this generates keys and a bundle.'),
        duration: const Duration(minutes: 3),
      ),
    );
    try {
      final user = await ref.read(usersProvider(profile.id).notifier).add(name);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Added ${user.name}')));
      if (context.mounted) {
        Navigator.of(context).push(UserBundleScreen.route(profile, user.name));
      }
    } on Object catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add user: ${errorSummary(e)}')),
      );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    MoavUser user,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${user.name}?'),
        content: const Text(
          'This revokes the user from every protocol and deletes their bundle '
          'on the server. Clients using these configs will stop working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MoavColors.fail),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(usersProvider(profile.id).notifier).remove(user.name);
      messenger.showSnackBar(SnackBar(content: Text('Revoked ${user.name}')));
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not revoke: ${errorSummary(e)}')),
      );
    }
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.profile,
    required this.user,
    required this.onRemove,
  });

  final ServerProfile profile;
  final MoavUser user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final subtitle = user.bundleReady
        ? 'Bundle ready · ${user.protocols.length} protocol stores'
        : user.protocols.isEmpty
            ? 'No bundle'
            : 'No bundle · ${user.protocols.join(', ')}';
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      onTap: () => Navigator.of(context).push(UserBundleScreen.route(profile, user.name)),
      child: Row(
        children: [
          MoavAvatar(user.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: moavMono(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            user.bundleReady ? Icons.qr_code_2 : Icons.hourglass_empty,
            size: 20,
            color: user.bundleReady ? MoavColors.cyan : MoavColors.textMuted,
          ),
          IconButton(
            icon: const Icon(Icons.person_remove_outlined),
            tooltip: 'Revoke',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _error {
    final n = _name.text.trim();
    if (n.isEmpty) return null;
    if (!MoavUser.validName.hasMatch(n)) {
      return 'Letters, numbers, _ and - only';
    }
    return null;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _error == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: TextField(
        controller: _name,
        autofocus: true,
        autocorrect: false,
        style: moavMono(size: 14),
        decoration: InputDecoration(
          labelText: 'Username',
          hintText: 'alice',
          errorText: _error,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) =>
            _valid ? Navigator.pop(context, _name.text.trim()) : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, _name.text.trim()) : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
