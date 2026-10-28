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
///
/// Privacy: the moment the app stops being the foreground focus
/// ([AppLifecycleState.inactive], which precedes the OS task-switcher
/// snapshot), the content is replaced by the branded [PrivacyShield]; it
/// comes back only once the app is active again **and** unlocked. The
/// child stays in the tree (offstage) so navigation state survives.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// True while the app is not the active foreground app.
  bool _obscured = false;

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
    switch (state) {
      case AppLifecycleState.resumed:
        setState(() => _obscured = false);
        if (ref.read(appLockProvider) == LockState.locked) {
          ref.read(appLockProvider.notifier).unlock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        setState(() => _obscured = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        setState(() => _obscured = true);
        ref.read(appLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final unlocked = lock == LockState.unlocked;
    final covered = _obscured || !unlocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Offstage: not painted, not hit-testable, not read by screen readers,
        // yet the navigator stack underneath survives the lock.
        Visibility(
          visible: !covered,
          maintainState: true,
          child: widget.child,
        ),
        if (covered)
          PrivacyShield(
            lock: unlocked ? null : lock,
            onUnlock: () => ref.read(appLockProvider.notifier).unlock(),
            onWipe: () => showWipeDialog(context, ref),
          ),
      ],
    );
  }
}

/// Opaque branded cover for the whole window. With [lock] `null` it is the
/// plain splash shown while the app is inactive; otherwise it is the lock
/// screen for that state, with the unlock button and the emergency wipe.
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({
    super.key,
    this.lock,
    required this.onUnlock,
    required this.onWipe,
  });

  final LockState? lock;
  final VoidCallback onUnlock;
  final VoidCallback onWipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = this.lock;
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
              if (lock != null) ...[
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
                    onPressed: onUnlock,
                    icon: Icons.fingerprint,
                    label: 'Unlock',
                  ),
                  const SizedBox(height: 40),
                  TextButton.icon(
                    style:
                        TextButton.styleFrom(foregroundColor: MoavColors.fail),
                    onPressed: onWipe,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Emergency wipe'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
