import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// device has a biometric enrolled. Enrollment is read when the sheet
/// opens, so it reflects what the OS says now.
class AppLockSheet extends ConsumerStatefulWidget {
  const AppLockSheet({super.key});

  @override
  ConsumerState<AppLockSheet> createState() => _AppLockSheetState();
}

class _AppLockSheetState extends ConsumerState<AppLockSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(enrolledBiometricsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enrolled = ref.watch(enrolledBiometricsProvider);
    final prefer = ref.watch(preferBiometricProvider).value ?? true;
    final available = enrolled.isNotEmpty;
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
              subtitle: Text(
                available
                    ? 'Always try $name first. If it fails you can try again '
                        'or use the device passcode.'
                    : 'No Face ID or fingerprint is set up on this device, so '
                        'the app unlocks with the device passcode.',
              ),
              // Shown as it will behave: nothing to prefer without one.
              value: available && prefer,
              onChanged: available
                  ? (v) => ref.read(preferBiometricProvider.notifier).set(v)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
