import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../security/app_lock.dart';
import '../../theme/moav_theme.dart';

/// Opens the app lock settings: how the app asks to be unlocked.
Future<void> showAppLockSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const AppLockSheet(),
    );

/// "Prefer biometric unlock": on by default, and only a choice while the
/// device has a biometric to offer. That is read when the sheet opens, so
/// it reflects what the OS says now; when there is none, the sheet says
/// which kind of none and what to do about it.
class AppLockSheet extends ConsumerStatefulWidget {
  const AppLockSheet({super.key, this.openSettings = _openAppSettings});

  /// Opens this app's page in the iOS Settings app; injectable so widget
  /// tests can record it.
  final Future<void> Function() openSettings;

  static Future<void> _openAppSettings() =>
      launchUrl(Uri.parse('app-settings:'));

  @override
  ConsumerState<AppLockSheet> createState() => _AppLockSheetState();
}

class _AppLockSheetState extends ConsumerState<AppLockSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(biometricStatusProvider.notifier).refresh();
    });
  }

  /// Switching it on where iOS has not named a biometric yet asks for one
  /// straight away, which is also what gets the app allowed to use it.
  Future<void> _setPrefer(bool value, BiometricStatus status) async {
    await ref.read(preferBiometricProvider.notifier).set(value);
    if (value && status == BiometricStatus.unconfirmed) {
      await ref.read(biometricStatusProvider.notifier).confirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enrolled = ref.watch(enrolledBiometricsProvider);
    final status = ref.watch(biometricStatusProvider);
    final prefer = ref.watch(preferBiometricProvider).value ?? true;
    final available = status.offered;
    final name = biometricLabel(enrolled, theme.platform);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(Icons.lock_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('App lock', style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'The app locks whenever it leaves the foreground and asks the '
              'device to confirm it is you before showing anything.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prefer biometric unlock'),
              subtitle: Text(switch (status) {
                BiometricStatus.ready =>
                  'Always try $name first. If it fails you can try again '
                      'or use the device passcode.',
                BiometricStatus.unconfirmed =>
                  'Always try $name first. The device may ask once to allow '
                      'it for this app.',
                BiometricStatus.denied =>
                  '$name is switched off for this app, so it unlocks with '
                      'the device passcode. Allow it in Settings, then come '
                      'back here.',
                BiometricStatus.notEnrolled ||
                BiometricStatus.unavailable =>
                  'No Face ID or fingerprint is set up on this device, so '
                      'the app unlocks with the device passcode.',
              }),
              // Shown as it will behave: nothing to prefer without one.
              value: available && prefer,
              onChanged: available ? (v) => _setPrefer(v, status) : null,
            ),
            if (status == BiometricStatus.unconfirmed && prefer)
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(biometricStatusProvider.notifier).confirm(),
                icon: const Icon(Icons.fingerprint),
                label: Text('Set up $name'),
              ),
            if (status == BiometricStatus.denied &&
                theme.platform == TargetPlatform.iOS)
              OutlinedButton.icon(
                onPressed: widget.openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Settings'),
              ),
          ],
        ),
      ),
    );
  }
}
