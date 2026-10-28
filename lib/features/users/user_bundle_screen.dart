import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import 'qr_layout.dart';
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
    return MoavScaffold(
      appBar: MoavAppBar(
        title: Text(user, style: moavMono(size: 17, weight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-fetch bundle',
            onPressed: () => ref.invalidate(bundleProvider(key)),
          ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(bundleProvider(key)),
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
    final theme = Theme.of(context);
    final qr = bundle.withQr.toList();
    final other = bundle.entries.where((e) => e.qrPayload == null).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        MoavCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              MoavAvatar(bundle.user, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bundle.entries.length} configs · ${qr.length} QR',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bundle.path ?? 'fetched over SFTP',
                      style: moavMono(
                        size: 11,
                        weight: FontWeight.w400,
                        color: MoavColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (qr.isNotEmpty) const SectionHeader('Scan to import'),
        for (final e in qr) _QrCard(entry: e),
        if (other.isNotEmpty) ...[
          const SectionHeader('Other configs'),
          MoavCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, e) in other.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: const Icon(Icons.description_outlined, color: MoavColors.cyan),
                    title: Text(e.title),
                    subtitle: Text(
                      e.fileName,
                      style: moavMono(
                        size: 11,
                        weight: FontWeight.w400,
                        color: MoavColors.textMuted,
                      ),
                    ),
                    trailing: _ActionRow(entry: e),
                  ),
                ],
              ],
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MoavCard(
        accent: true,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        entry.fileName,
                        style: moavMono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: MoavColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _ActionRow(entry: entry),
              ],
            ),
            const SizedBox(height: 14),
            BundleQr(payload: payload),
            const SizedBox(height: 12),
            CodeBlock(
              payload.length > 96 ? '${payload.substring(0, 96)}…' : payload,
              selectable: false,
              maxLines: 2,
              size: 11,
            ),
          ],
        ),
      ),
    );
  }
}

/// One bundle entry's QR on a white card, sized from its module count so
/// dense codes (2 KB subscriptions) stay crisp instead of blurring grey.
class BundleQr extends StatelessWidget {
  const BundleQr({super.key, required this.payload});

  final String payload;

  /// White margin around the modules; the quiet zone scanners need.
  static const quietZone = 12.0;

  @override
  Widget build(BuildContext context) {
    final code = encodeQr(payload);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = code == null
            ? null
            : qrGeometry(
                modules: code.moduleCount,
                maxWidth: constraints.maxWidth - 2 * quietZone,
                dpr: MediaQuery.devicePixelRatioOf(context),
              );
        return Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MoavRadius.card,
              boxShadow: moavGlow(blur: 32, alpha: 0.12),
            ),
            padding: const EdgeInsets.all(quietZone),
            child: code == null || geometry == null
                ? const SizedBox(
                    width: 216,
                    height: 216,
                    child: Center(
                      child: Text(
                        'Too large for a QR code',
                        style: TextStyle(color: MoavColors.bg),
                      ),
                    ),
                  )
                : RepaintBoundary(
                    child: QrImageView.withQr(
                      qr: code,
                      size: geometry.size,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
          ),
        );
      },
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
          icon: const Icon(Icons.copy, size: 20),
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
          icon: const Icon(Icons.ios_share, size: 20),
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
