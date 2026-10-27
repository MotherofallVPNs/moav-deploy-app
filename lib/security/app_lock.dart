import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../features/wipe/wipe_dialog.dart';
import '../theme/moav_theme.dart';

/// Wraps [LocalAuthentication] so it can be swapped in tests.
class AppLockService {
  AppLockService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device can prompt for biometrics or a passcode.
  Future<bool> canLock() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (_) {
      return false;
    }
  }

  /// Prompts the user. Returns true on success or when no lock is available
  /// (so the app is never bricked on devices without a passcode).
  Future<bool> authenticate() async {
    if (!await canLock()) return true;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock MoaV Deploy',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'MoaV Deploy',
            signInHint: 'Unlock with your fingerprint, face or screen lock',
            cancelButton: 'Not now',
          ),
          IOSAuthMessages(
            cancelButton: 'Not now',
            localizedFallbackTitle: 'Use passcode',
          ),
        ],
        persistAcrossBackgrounding: true,
      );
    } on Object catch (_) {
      return false;
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>((_) => AppLockService());

enum LockState { locked, unlocking, unlocked, failed }

class AppLockNotifier extends Notifier<LockState> {
  @override
  LockState build() => LockState.locked;

  Future<void> unlock() async {
    if (state == LockState.unlocking) return;
    state = LockState.unlocking;
    final ok = await ref.read(appLockServiceProvider).authenticate();
    state = ok ? LockState.unlocked : LockState.failed;
  }

  void lock() => state = LockState.locked;
}

final appLockProvider =
    NotifierProvider<AppLockNotifier, LockState>(AppLockNotifier.new);

/// Gate shown on launch and on resume from background.
///
/// Prompts once on launch and again whenever the app returns to the
/// foreground. The emergency wipe is reachable **without** unlocking: under
/// duress, destroying the keys must be faster than proving who you are.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appLockProvider.notifier).unlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(appLockProvider.notifier).lock();
    } else if (state == AppLifecycleState.resumed &&
        ref.read(appLockProvider) == LockState.locked) {
      ref.read(appLockProvider.notifier).unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (lock == LockState.unlocked) return widget.child;
    final theme = Theme.of(context);
    return MoavScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MoavMark(size: 120),
              const SizedBox(height: 24),
              const MoavWordmark(suffix: 'Deploy', size: 26),
              const SizedBox(height: 8),
              Text(
                lock == LockState.failed ? 'Unlock failed' : 'Locked',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              if (lock == LockState.unlocking)
                const CircularProgressIndicator()
              else ...[
                GradientButton(
                  onPressed: () => ref.read(appLockProvider.notifier).unlock(),
                  icon: Icons.fingerprint,
                  label: 'Unlock',
                ),
                const SizedBox(height: 40),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: MoavColors.fail),
                  onPressed: () => showWipeDialog(context, ref),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Emergency wipe'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
