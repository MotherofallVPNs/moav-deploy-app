import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

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
/// M1 stub: prompts once on launch and again whenever the app returns to the
/// foreground. The wipe action lands in M5.
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
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              lock == LockState.failed ? 'Unlock failed' : 'MoaV Deploy is locked',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (lock == LockState.unlocking)
              const CircularProgressIndicator()
            else
              FilledButton(
                onPressed: () => ref.read(appLockProvider.notifier).unlock(),
                child: const Text('Unlock'),
              ),
          ],
        ),
      ),
    );
  }
}
