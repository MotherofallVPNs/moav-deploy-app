import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../core/ssh_moav_controller.dart';
import '../operate/user_test_screen.dart';
import 'users_provider.dart';

/// One user's client configs: a QR per phone-friendly link, copy and share.
class UserBundleScreen extends ConsumerWidget {
  const UserBundleScreen({super.key, required this.profile, required this.user});

  final ServerProfile profile;
  final String user;

  static Route<void> route(ServerProfile profile, String user) =>
      MaterialPageRoute(
        builder: (_) => UserBundleScreen(profile: profile, user: user),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (serverId: profile.id, user: user);
    final bundle = ref.watch(bundleProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(user),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check),
            tooltip: 'Test connectivity',
            onPressed: () => Navigator.of(context).push(UserTestScreen.route(profile, user)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-fetch bundle',
            onPressed: () => ref.invalidate(bundleProvider(key)),
          ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(SshMoavController.describeError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (b) => _BundleView(bundle: b),
      ),
    );
  }
}

class _BundleView extends StatelessWidget {
  const _BundleView({required this.bundle});

  final Bundle bundle;

  @override
  Widget build(BuildContext context) {
    final qr = bundle.withQr.toList();
    final other = bundle.entries.where((e) => e.qrPayload == null).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${bundle.entries.length} configs · fetched over SFTP from ${bundle.path ?? 'the server'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final e in qr) _QrCard(entry: e),
        if (other.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Other configs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final e in other)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(e.title),
              subtitle: Text(e.fileName),
              trailing: _ActionRow(entry: e),
            ),
        ],
      ],
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.entry});

  final BundleEntry entry;

  @override
  Widget build(BuildContext context) {
    final payload = entry.qrPayload!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
                      Text(entry.fileName, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _ActionRow(entry: entry),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: payload,
                size: 220,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                errorStateBuilder: (_, _) => const SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(child: Text('Too large for a QR code')),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              payload.length > 80 ? '${payload.substring(0, 80)}…' : payload,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.entry});

  final BundleEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = entry.qrPayload ?? entry.content;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copy',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${entry.title} copied')),
              );
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Share',
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              text: text,
              subject: 'MoaV ${entry.title} config (${entry.fileName})',
            ),
          ),
        ),
      ],
    );
  }
}
