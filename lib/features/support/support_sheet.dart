import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_links.dart';
import '../../theme/moav_theme.dart';

/// Opens the "Support us" popup: the money-donation links, plus a pointer to
/// every other way to help. Replaces the old jump straight to a web page.
Future<void> showSupportSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SupportSheet(),
    );

/// Body of the support popup. [onOpen] is injectable so tests can record
/// which link a button opens without a platform url launcher.
class SupportSheet extends StatelessWidget {
  const SupportSheet({super.key, this.onOpen = _launch});

  final Future<void> Function(Uri url) onOpen;

  static Future<void> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(Icons.favorite_outline, gradient: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Support MoaV', style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'MoaV is free and open source. Donations pay for test servers, '
              'domains and the developer accounts that ship this app.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            GradientButton(
              icon: Icons.volunteer_activism_outlined,
              label: 'GitHub Sponsors',
              expand: true,
              onPressed: () => onOpen(MoavLinks.supportGithubSponsors),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.coffee_outlined, size: 18),
              label: const Text('Buy Me a Coffee'),
              onPressed: () => onOpen(MoavLinks.supportBuymeacoffee),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('More ways to support'),
              onPressed: () => onOpen(MoavLinks.supportMore),
            ),
          ],
        ),
      ),
    );
  }
}
