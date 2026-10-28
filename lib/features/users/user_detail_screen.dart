import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/moav_controller.dart';
import '../../core/moav_services.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import '../operate/operate_provider.dart';
import 'user_bundle_screen.dart';
import 'users_provider.dart';

/// One user at a glance: protocol stores, the subscription blob to paste
/// into a phone app and the bundle (QR codes and configs).
class UserDetailScreen extends ConsumerWidget {
  const UserDetailScreen({super.key, required this.profile, required this.user});

  final ServerProfile profile;
  final MoavUser user;

  static Route<void> route(ServerProfile profile, MoavUser user) =>
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(profile: profile, user: user),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (serverId: profile.id, user: user.name);
    // The list may have been refreshed since this screen opened.
    final current = ref
            .watch(usersProvider(profile.id))
            .value
            ?.where((u) => u.name == user.name)
            .firstOrNull ??
        user;
    final bundle = ref.watch(bundleProvider(key));
    // Which protocols the server hands this user: its `.env` flags crossed
    // with the stores that list the user, not the six store names.
    final flags = ref.watch(serviceFlagsProvider(profile.id)).data;
    final protocols = MoavServices.userProtocols(current.protocols, flags: flags);
    return MoavScaffold(
      appBar: MoavAppBar(
        title: Text(user.name, style: moavMono(size: 17, weight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(bundleProvider(key));
              ref.read(usersProvider(profile.id).notifier).refresh();
              ref.read(serviceFlagsProvider(profile.id).notifier).refresh();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _HeaderCard(user: current, protocols: protocols),
          const SectionHeader('Subscription'),
          _SubscriptionCard(
            user: current,
            bundle: bundle,
            onRetry: () => ref.invalidate(bundleProvider(key)),
          ),
          const SectionHeader('Bundle'),
          MoavCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  bundle.value == null
                      ? 'Every client config for this user: QR codes to scan, '
                          'plus copy and share for each file.'
                      : '${bundle.value!.entries.length} configs, '
                          '${bundle.value!.withQr.length} with a QR code.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                GradientButton(
                  onPressed: () => Navigator.of(context)
                      .push(UserBundleScreen.route(profile, user.name)),
                  icon: Icons.qr_code_2,
                  label: 'Download connection bundle',
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.user, required this.protocols});

  final MoavUser user;

  /// Enabled protocols for this user (see [MoavServices.userProtocols]).
  final List<String> protocols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MoavAvatar(user.name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: moavMono(size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      protocols.isEmpty
                          ? 'No protocols enabled for this user'
                          : '${protocols.length} protocol'
                              '${protocols.length == 1 ? '' : 's'} enabled · '
                              '${user.protocols.length} '
                              '${user.protocols.length == 1 ? 'store' : 'stores'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                user.bundleReady ? 'bundle ready' : 'no bundle',
                tone: user.bundleReady ? StatusTone.pass : StatusTone.warn,
              ),
            ],
          ),
          if (protocols.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in protocols)
                  StatusPill(
                    BundleEntry.titles[p] ?? p,
                    tone: StatusTone.accent,
                    dot: false,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.user,
    required this.bundle,
    required this.onRetry,
  });

  final MoavUser user;
  final AsyncValue<Bundle> bundle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    final b = bundle.value;
    if (b != null) {
      final sub = b.entries.where((e) => e.protocol == 'subscription').firstOrNull;
      if (sub == null) {
        body = Text(
          'This bundle has no subscription.txt. Run moav user package '
          '${user.name} on the server, or Regenerate users.',
          style: theme.textTheme.bodySmall,
        );
      } else {
        final text = sub.content.trim();
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeBlock(
              text.length > 160 ? '${text.substring(0, 160)}…' : text,
              selectable: false,
              maxLines: 3,
              size: 11,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Subscription copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy subscription'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.ios_share, size: 20),
                  tooltip: 'Share',
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: text,
                      subject: 'MoaV subscription (${user.name})',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }
    } else if (bundle.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErrorBanner(error: bundle.error!),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Fetching the bundle…', style: theme.textTheme.bodySmall),
        ],
      );
    }
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste into v2rayNG, Streisand, Hiddify or NekoBox.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}
