import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../features/wipe/wipe_dialog.dart';
import '../theme/moav_theme.dart';
import 'decoy/decoy_provider.dart';

/// How one unlock attempt authenticates.
enum UnlockMethod {
  /// Face ID, Touch ID or fingerprint only: the prompt never turns into the
  /// passcode sheet on its own.
  biometric,

  /// Whatever the OS offers for the device, ending in its passcode.
  deviceCredential,
}

/// How one system prompt ended.
enum AuthOutcome {
  success,

  /// Not recognised, cancelled or interrupted.
  failed,

  /// The user picked "Use passcode" on a biometric-only prompt.
  fallbackRequested,

  /// Biometrics cannot answer right now (locked out after too many tries,
  /// none enrolled any more, sensor busy); only the passcode can.
  biometricUnavailable,
}

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

  /// The biometrics this app may use right now; empty when none are
  /// enrolled, the OS setting denies them to the app, or it will not say.
  /// Asked again for every unlock attempt, since either can change while
  /// the app is in the background.
  Future<List<BiometricType>> enrolledBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on Object catch (_) {
      return const [];
    }
  }

  /// Prompts the user. Succeeds when no lock is available at all (so the
  /// app is never bricked on devices without a passcode).
  ///
  /// With [biometricOnly] the OS asks for the biometric alone; without it
  /// the OS decides, and after a failed or cancelled biometric that is
  /// usually the passcode sheet straight away.
  ///
  /// With [disguised] the prompt reads as the Notes app's own lock, so the
  /// system sheet names no MoaV while the decoy is on.
  Future<AuthOutcome> authenticate({
    bool disguised = false,
    bool biometricOnly = false,
  }) async {
    if (!await canLock()) return AuthOutcome.success;
    final name = disguised ? 'Notes' : 'MoaV Deploy';
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock $name',
        authMessages: [
          AndroidAuthMessages(
            signInTitle: name,
            signInHint: biometricOnly
                ? 'Unlock with your fingerprint or face'
                : 'Unlock with your fingerprint, face or screen lock',
            cancelButton: 'Not now',
          ),
          const IOSAuthMessages(
            cancelButton: 'Not now',
            localizedFallbackTitle: 'Use passcode',
          ),
        ],
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } on LocalAuthException catch (e) {
      return outcomeFor(e.code, biometricOnly: biometricOnly);
    } on Object catch (_) {
      return AuthOutcome.failed;
    }
  }

  /// Which failures of a biometric-only prompt mean "go to the passcode".
  static AuthOutcome outcomeFor(
    LocalAuthExceptionCode code, {
    required bool biometricOnly,
  }) {
    if (!biometricOnly) return AuthOutcome.failed;
    return switch (code) {
      LocalAuthExceptionCode.userRequestedFallback =>
        AuthOutcome.fallbackRequested,
      LocalAuthExceptionCode.temporaryLockout ||
      LocalAuthExceptionCode.biometricLockout ||
      LocalAuthExceptionCode.noBiometricsEnrolled ||
      LocalAuthExceptionCode.noBiometricHardware ||
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
        AuthOutcome.biometricUnavailable,
      _ => AuthOutcome.failed,
    };
  }
}

final appLockServiceProvider = Provider<AppLockService>((_) => AppLockService());

/// The biometrics the OS lets this app use, as last asked: what the lock
/// screen offers. Empty until the first answer.
class EnrolledBiometricsNotifier extends Notifier<List<BiometricType>> {
  @override
  List<BiometricType> build() => const [];

  Future<List<BiometricType>> refresh() async {
    final found = await ref.read(appLockServiceProvider).enrolledBiometrics();
    if (ref.mounted) state = found;
    return found;
  }
}

final enrolledBiometricsProvider =
    NotifierProvider<EnrolledBiometricsNotifier, List<BiometricType>>(
  EnrolledBiometricsNotifier.new,
);

/// "Face ID", "Touch ID" or a generic word, for the lock screen buttons.
/// Android only reports strength classes, never which sensor it is.
String biometricLabel(List<BiometricType> enrolled, TargetPlatform platform) {
  final apple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  if (apple && enrolled.contains(BiometricType.face)) return 'Face ID';
  if (apple && enrolled.contains(BiometricType.fingerprint)) return 'Touch ID';
  return 'biometrics';
}

enum LockState { locked, unlocking, unlocked, failed }

class AppLockNotifier extends Notifier<LockState> {
  /// The prompt on screen, if any: there is never more than one.
  Future<void>? _attempt;

  @override
  LockState build() => LockState.locked;

  /// One unlock attempt. Without [method] it is the biometric when the OS
  /// offers one to this app, and the device passcode otherwise.
  ///
  /// Nothing is carried over from earlier attempts: a failed or cancelled
  /// biometric prompt does not demote the next one to the passcode, and
  /// enrollment is read again each time.
  Future<void> unlock({UnlockMethod? method}) {
    final running = _attempt;
    if (running != null) {
      // Locked again while the prompt is still up: keep showing it as such.
      if (state == LockState.locked) state = LockState.unlocking;
      return running;
    }
    final attempt = _run(method);
    _attempt = attempt;
    return attempt.whenComplete(() => _attempt = null);
  }

  Future<void> _run(UnlockMethod? method) async {
    state = LockState.unlocking;
    final service = ref.read(appLockServiceProvider);
    final disguised = ref.read(decoyProvider).enabled;
    final enrolled =
        await ref.read(enrolledBiometricsProvider.notifier).refresh();
    if (!ref.mounted) return;
    // Biometric first unless the passcode was asked for. The OS decides
    // whether there is one: Face ID switched off for the app reads as none.
    final biometric =
        method != UnlockMethod.deviceCredential && enrolled.isNotEmpty;
    var outcome = await service.authenticate(
      disguised: disguised,
      biometricOnly: biometric,
    );
    if (biometric &&
        (outcome == AuthOutcome.fallbackRequested ||
            outcome == AuthOutcome.biometricUnavailable)) {
      // Asked for on the sheet, or the only thing that clears a lockout.
      outcome = await service.authenticate(disguised: disguised);
    }
    if (!ref.mounted) return;
    state = outcome == AuthOutcome.success
        ? LockState.unlocked
        : LockState.failed;
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
        } else {
          // Face ID may have been set up or removed in Settings meanwhile.
          ref.read(enrolledBiometricsProvider.notifier).refresh();
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
    final biometrics = ref.watch(enrolledBiometricsProvider);
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
            biometrics: biometrics,
            onUnlock: (method) =>
                ref.read(appLockProvider.notifier).unlock(method: method),
            onWipe: () => showWipeDialog(context, ref),
          ),
      ],
    );
  }
}

/// Opaque branded cover for the whole window. With [lock] `null` it is the
/// plain splash shown while the app is inactive; otherwise it is the lock
/// screen for that state, with the unlock buttons and the emergency wipe.
///
/// With [biometrics] enrolled the main button always goes back to the
/// biometric prompt ("Use Face ID", "Try Face ID again" after a failure)
/// and the device passcode is the secondary way in; without any there is
/// the single "Unlock".
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({
    super.key,
    this.lock,
    this.biometrics = const [],
    required this.onUnlock,
    required this.onWipe,
  });

  final LockState? lock;

  /// Biometrics enrolled on the device; empty hides the biometric button.
  final List<BiometricType> biometrics;

  /// `null` is the default: biometric when there is one, else the passcode.
  final void Function(UnlockMethod? method) onUnlock;
  final VoidCallback onWipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = this.lock;
    final biometric = biometricLabel(biometrics, theme.platform);
    final face = biometrics.contains(BiometricType.face);
    return MoavScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MoavLockup(),
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
                  if (biometrics.isEmpty)
                    GradientButton(
                      onPressed: () => onUnlock(null),
                      icon: Icons.fingerprint,
                      label: 'Unlock',
                    )
                  else ...[
                    GradientButton(
                      onPressed: () => onUnlock(UnlockMethod.biometric),
                      icon: face ? Icons.face : Icons.fingerprint,
                      label: lock == LockState.failed
                          ? 'Try $biometric again'
                          : 'Use $biometric',
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          onUnlock(UnlockMethod.deviceCredential),
                      icon: const Icon(Icons.password, size: 18),
                      label: const Text('Use device passcode'),
                    ),
                  ],
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
