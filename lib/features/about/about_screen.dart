import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_identity.dart';
import '../../core/moav_links.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';

/// Version, signing fingerprint and how to verify a sideloaded APK, so a
/// user who did not install from a store can tell an official build from a
/// re-signed copy. Reached from the home menu (issue #25).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const AboutScreen());

  static const appName = 'MoaV Deploy';

  /// Shown instead of a fingerprint where the platform has no signing API
  /// the app can read (iOS, desktop, tests).
  static const noFingerprint = 'Not available on this platform';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(appIdentityProvider);
    final value = identity.value;
    return MoavScaffold(
      appBar: MoavAppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(identity: identity),
          const SectionHeader('Signing certificate'),
          _FingerprintCard(
            fingerprint: value?.signingFingerprint,
            loading: identity.isLoading,
          ),
          const SectionHeader('Verify your download'),
          const _VerifyCard(),
          const SectionHeader('Links'),
          _LinkTile(
            icon: Icons.code,
            title: 'Source code',
            subtitle: MoavLinks.repoUrl.replaceFirst('https://', ''),
            onTap: () => _open(MoavLinks.repo),
          ),
          _LinkTile(
            icon: Icons.new_releases_outlined,
            title: 'Releases',
            subtitle: 'Signed APK, AAB and SHA256SUMS for every version',
            onTap: () => _open(MoavLinks.releases),
          ),
          _LinkTile(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
            subtitle: 'Flutter, Dart packages and the bundled fonts',
            onTap: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationVersion: value?.versionLabel,
              applicationIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: MoavMark(size: 56),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}

class _Header extends StatelessWidget {
  const _Header({required this.identity});

  final AsyncValue<AppIdentity> identity;

  @override
  Widget build(BuildContext context) {
    final label = switch (identity) {
      AsyncData(:final value) => 'Version ${value.versionLabel}',
      AsyncError() => 'Version unavailable',
      _ => 'Reading version…',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const MoavMark(size: 72),
          const SizedBox(height: 14),
          const MoavWordmark(suffix: 'Deploy', size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            key: const ValueKey('about-version'),
            style: moavMono(size: 13, color: MoavColors.cyan),
          ),
          const SizedBox(height: 6),
          Text(
            'Deploy, manage and monitor MoaV servers from your phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: MoavColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FingerprintCard extends StatelessWidget {
  const _FingerprintCard({required this.fingerprint, required this.loading});

  final String? fingerprint;
  final bool loading;

  /// `AA:BB:...` as four lines of eight bytes, easier to compare by eye.
  static String wrap(String fp) {
    final bytes = fp.split(':');
    final lines = <String>[];
    for (var i = 0; i < bytes.length; i += 8) {
      lines.add(bytes.sublist(i, (i + 8).clamp(0, bytes.length)).join(':'));
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: MoavColors.textSecondary, height: 1.4);
    final fp = fingerprint;
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHA-256 of the certificate that signed this installed build, read '
            'from the system at runtime. Official APKs from GitHub Releases all '
            'carry the same fingerprint, so it should never change between '
            'updates. A different value means someone re-signed the APK.',
            style: body,
          ),
          const SizedBox(height: 12),
          if (fp != null)
            CodeBlock(wrap(fp), size: 13)
          else
            CodeBlock(
              loading ? 'Reading signing certificate…' : AboutScreen.noFingerprint,
              selectable: false,
            ),
          if (fp != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _copy(context, fp),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy fingerprint'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String fp) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: fp));
    messenger.showSnackBar(
      const SnackBar(content: Text('Fingerprint copied')),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  const _VerifyCard();

  static const steps = [
    'Every GitHub release ships app-release.apk next to a SHA256SUMS file '
        'written by the same build. If you got the APK anywhere else, check '
        'it against that file before installing.',
    '1. From the release page, download SHA256SUMS into the folder that '
        'holds the APK, named app-release.apk.',
    '2. In that folder, run:',
  ];

  static const command = 'sha256sum --ignore-missing -c SHA256SUMS\n'
      '# macOS: shasum -a 256 --ignore-missing -c SHA256SUMS';

  static const after =
      '3. Install only if it prints "app-release.apk: OK". After installing, '
      'the fingerprint above should match the one the project publishes.';

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: MoavColors.textSecondary, height: 1.4);
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in steps) ...[
            Text(step, style: body),
            const SizedBox(height: 8),
          ],
          const CodeBlock(command),
          const SizedBox(height: 10),
          Text(after, style: body),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
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
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: MoavColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, size: 18, color: MoavColors.textMuted),
          ],
        ),
      ),
    );
  }
}
