import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_links.dart';
import '../../security/app_lock.dart';
import '../../security/onboarding.dart';
import '../../theme/moav_theme.dart';
import '../about/about_screen.dart';

/// Shows [WelcomeDialog] on every launch (once per process) until "Don't
/// show this again" is ticked, and only once the app is unlocked (so it
/// never floats over the privacy shield). With [requireUnlock] false it
/// shows as soon as the flag has loaded; tests use that.
class WelcomeGate extends ConsumerStatefulWidget {
  const WelcomeGate({super.key, required this.child, this.requireUnlock = true});

  final Widget child;
  final bool requireUnlock;

  @override
  ConsumerState<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends ConsumerState<WelcomeGate> {
  var _shown = false;

  void _maybeShow() {
    if (_shown) return;
    final dismissed = ref.read(welcomeProvider).value;
    if (dismissed != false) return;
    if (widget.requireUnlock &&
        ref.read(appLockProvider) != LockState.unlocked) {
      return;
    }
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWelcomeDialog(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(welcomeProvider, (_, _) => _maybeShow());
    ref.listen(appLockProvider, (_, _) => _maybeShow());
    _maybeShow();
    return widget.child;
  }
}

/// Opens the welcome dialog and records the "Don't show this again" choice
/// however the dialog was closed (button, About link or tapping outside).
/// The box starts unticked: closing without it keeps the welcome coming back.
Future<void> showWelcomeDialog(BuildContext context, WidgetRef ref) async {
  final dontShowAgain = ValueNotifier<bool>(false);
  final action = await showDialog<_WelcomeAction>(
    context: context,
    builder: (_) => WelcomeDialog(dontShowAgain: dontShowAgain),
  );
  await ref
      .read(welcomeProvider.notifier)
      .dismiss(forever: dontShowAgain.value);
  dontShowAgain.dispose();
  if (action == _WelcomeAction.about && context.mounted) {
    await Navigator.of(context).push(AboutScreen.route());
  }
}

enum _WelcomeAction { start, about }

/// Logo, two sentences, the three places to learn more, and the checkbox.
class WelcomeDialog extends StatelessWidget {
  const WelcomeDialog({super.key, required this.dontShowAgain});

  final ValueNotifier<bool> dontShowAgain;

  static const title = 'Welcome to MoaV Deploy';
  static const intro =
      'Install, manage and monitor your own MoaV server from your phone. '
      'Keys and credentials never leave this device.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: MoavColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: MoavRadius.card,
        side: const BorderSide(color: MoavColors.borderStrong),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: MoavMark(size: 72)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                intro,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: MoavColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  _Link(
                    icon: Icons.info_outline,
                    label: 'About',
                    onTap: () => Navigator.pop(context, _WelcomeAction.about),
                  ),
                  _Link(
                    icon: Icons.menu_book_outlined,
                    label: 'Docs',
                    onTap: () => _open(MoavLinks.docs),
                  ),
                  _Link(
                    icon: Icons.language,
                    label: 'Website',
                    onTap: () => _open(MoavLinks.website),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GradientButton(
                onPressed: () => Navigator.pop(context, _WelcomeAction.start),
                icon: Icons.arrow_forward,
                label: 'Get started',
                expand: true,
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<bool>(
                valueListenable: dontShowAgain,
                builder: (_, value, _) => CheckboxListTile(
                  key: const ValueKey('welcome-dont-show'),
                  value: value,
                  onChanged: (v) => dontShowAgain.value = v ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    "Don't show this again",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
}
