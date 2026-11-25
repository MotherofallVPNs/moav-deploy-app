import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../features/servers/servers_provider.dart';
import '../features/wipe/wipe_dialog.dart';
import '../theme/moav_theme.dart';
import 'app_log.dart';
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
  /// sensor busy); only the passcode can.
  biometricUnavailable,

  /// The device has a sensor with nothing enrolled on it.
  biometricNotEnrolled,

  /// The OS keeps biometrics from this app: no sensor, or (iOS) Face ID
  /// switched off for the app in Settings. iOS reports both alike.
  biometricRefused;

  /// A biometric-only prompt ended where only the passcode can go on.
  bool get wantsPasscode =>
      this == fallbackRequested ||
      this == biometricUnavailable ||
      this == biometricNotEnrolled ||
      this == biometricRefused;
}

/// Where biometric unlock stands for this app, as far as is known.
enum BiometricStatus {
  /// Enrolled and usable: the OS names it.
  ready,

  /// iOS and macOS only: the OS names none, yet the device can lock. Only a
  /// biometric prompt says why (never asked, off in Settings, none enrolled).
  unconfirmed,

  /// Switched off for this app in the system settings.
  denied,

  /// A sensor with nothing enrolled on it.
  notEnrolled,

  /// Nothing to offer: no sensor, or no device lock at all.
  unavailable;

  /// Worth a biometric prompt: it works, or it says why it cannot.
  bool get offered => this == ready || this == unconfirmed;
}

/// Wraps [LocalAuthentication] so it can be swapped in tests.
class AppLockService {
  AppLockService([LocalAuthentication? auth, TargetPlatform? platform])
      : _auth = auth ?? LocalAuthentication(),
        _platform = platform ?? defaultTargetPlatform;

  final LocalAuthentication _auth;
  final TargetPlatform _platform;

  bool get _apple =>
      _platform == TargetPlatform.iOS || _platform == TargetPlatform.macOS;

  /// True when the device can prompt for biometrics or a passcode.
  Future<bool> canLock() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (_) {
      return false;
    }
  }

  /// The biometrics the OS names right now; empty when there are none or it
  /// will not say (see [biometricStatus]). Asked again for every unlock
  /// attempt, since enrollment can change while the app is in the background.
  Future<List<BiometricType>> enrolledBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on Object catch (_) {
      return const [];
    }
  }

  /// What [enrolled] (from [enrolledBiometrics]) means here, without a prompt.
  /// Android's list is the whole answer; iOS lists only what this app may
  /// use now, so its empty list also covers "Face ID is off for the app".
  Future<BiometricStatus> biometricStatus(List<BiometricType> enrolled) async {
    if (enrolled.isNotEmpty) return BiometricStatus.ready;
    if (!_apple || !await canLock()) return BiometricStatus.unavailable;
    return BiometricStatus.unconfirmed;
  }

  /// True when the device has a biometric sensor, whether or not this app
  /// may use it.
  Future<bool> hasBiometricSensor() async {
    try {
      return await _auth.canCheckBiometrics;
    } on Object catch (_) {
      return false;
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
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
        AuthOutcome.biometricUnavailable,
      LocalAuthExceptionCode.noBiometricsEnrolled =>
        AuthOutcome.biometricNotEnrolled,
      LocalAuthExceptionCode.noBiometricHardware =>
        AuthOutcome.biometricRefused,
      _ => AuthOutcome.failed,
    };
  }
}

final appLockServiceProvider = Provider<AppLockService>((_) => AppLockService());

/// Whether an unlock tries the biometric first (default) or leaves the
/// choice to the OS prompt.
class PreferBiometricNotifier extends AsyncNotifier<bool> {
  /// Unreadable storage counts as on: the setting must never lock anyone out.
  @override
  Future<bool> build() async {
    try {
      return await ref.read(secureCredStoreProvider).readPreferBiometric();
    } on Object catch (e) {
      AppLog.warn('lock', 'preference not read: ${e.runtimeType}');
      return true;
    }
  }

  Future<void> set(bool value) async {
    state = AsyncData(value);
    await ref.read(secureCredStoreProvider).writePreferBiometric(value);
  }
}

final preferBiometricProvider =
    AsyncNotifierProvider<PreferBiometricNotifier, bool>(
  PreferBiometricNotifier.new,
);

/// The biometrics the OS named when last asked, for labels and icons. Empty
/// until the first answer; [biometricStatusProvider] keeps it current.
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

/// Whether biometric unlock can be offered, and if not, why: what the lock
/// screen and the setting go by.
class BiometricStatusNotifier extends Notifier<BiometricStatus> {
  /// What a prompt said while the OS itself names nothing.
  BiometricStatus? _learned;

  @override
  BiometricStatus build() => BiometricStatus.unavailable;

  /// Asks the OS again, without prompting.
  Future<BiometricStatus> refresh() async {
    final service = ref.read(appLockServiceProvider);
    final enrolled =
        await ref.read(enrolledBiometricsProvider.notifier).refresh();
    final found = await service.biometricStatus(enrolled);
    if (!ref.mounted) return found;
    if (found != BiometricStatus.unconfirmed) _learned = null;
    return state = _learned ?? found;
  }

  /// Takes in how a biometric-only prompt ended: its refusals are the only
  /// way to tell "off for this app" from "none enrolled" on iOS.
  Future<void> learn(AuthOutcome outcome) async {
    final service = ref.read(appLockServiceProvider);
    final learned = switch (outcome) {
      AuthOutcome.biometricNotEnrolled => BiometricStatus.notEnrolled,
      AuthOutcome.biometricRefused => await service.hasBiometricSensor()
          ? BiometricStatus.denied
          : BiometricStatus.unavailable,
      _ => null,
    };
    if (learned == null || !ref.mounted) return;
    AppLog.info('lock', 'biometric prompt refused: ${learned.name}');
    state = _learned = learned;
  }

  /// Asks for the biometric alone, now: on iOS that is what brings up the
  /// Face ID permission alert, and what says why when it cannot.
  Future<BiometricStatus> confirm() async {
    final outcome = await ref.read(appLockServiceProvider).authenticate(
          disguised: ref.read(decoyProvider).enabled,
          biometricOnly: true,
        );
    if (!ref.mounted) return state;
    await learn(outcome);
    if (!ref.mounted) return state;
    return refresh();
  }
}

final biometricStatusProvider =
    NotifierProvider<BiometricStatusNotifier, BiometricStatus>(
  BiometricStatusNotifier.new,
);

/// "Face ID", "Touch ID" or a generic word, for buttons and the setting.
/// Android only reports strength classes, never which sensor it is, and
/// neither does iOS before the app has been allowed to use it.
String biometricLabel(List<BiometricType> enrolled, TargetPlatform platform) {
  final apple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  if (apple && enrolled.contains(BiometricType.face)) return 'Face ID';
  if (apple && enrolled.contains(BiometricType.fingerprint)) return 'Touch ID';
  if (apple && enrolled.isEmpty) return 'Face ID or Touch ID';
  return 'biometrics';
}

enum LockState { locked, unlocking, unlocked, failed }

class AppLockNotifier extends Notifier<LockState> {
  /// The prompt on screen, if any: there is never more than one.
  Future<void>? _attempt;

  @override
  LockState build() => LockState.locked;

  /// One unlock attempt. Without [method] the "Prefer biometric unlock"
  /// setting picks it.
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
    final biometrics = ref.read(biometricStatusProvider.notifier);
    final status = await biometrics.refresh();
    if (!ref.mounted) return;
    var chosen = method;
    // The setting only matters when there is a biometric to prefer.
    if (chosen == null && status.offered) {
      final prefer = await _preferBiometric();
      if (!ref.mounted) return;
      chosen = prefer ? UnlockMethod.biometric : UnlockMethod.deviceCredential;
    }
    final biometric = chosen == UnlockMethod.biometric && status.offered;
    var outcome = await service.authenticate(
      disguised: disguised,
      biometricOnly: biometric,
    );
    if (biometric && outcome.wantsPasscode) {
      await biometrics.learn(outcome);
      if (!ref.mounted) return;
      // Asked for on the sheet, or the only way in without the biometric.
      outcome = await service.authenticate(disguised: disguised);
    }
    if (!ref.mounted) return;
    if (outcome == AuthOutcome.success &&
        status == BiometricStatus.unconfirmed) {
      // iOS names the biometric once the app has been allowed to use it.
      await biometrics.refresh();
      if (!ref.mounted) return;
    }
    state = outcome == AuthOutcome.success
        ? LockState.unlocked
        : LockState.failed;
  }

  /// The setting, or its default when the store is slow or broken: reading
  /// a preference must never be what keeps the prompt from appearing.
  Future<bool> _preferBiometric() async {
    try {
      return await ref
          .read(preferBiometricProvider.future)
          .timeout(const Duration(seconds: 2), onTimeout: () => true);
    } on Object catch (_) {
      return true;
    }
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
          // Face ID may have been set up, removed or allowed in Settings.
          ref.read(biometricStatusProvider.notifier).refresh();
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
    final status = ref.watch(biometricStatusProvider);
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
            offerBiometric: status.offered,
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
/// With a biometric to offer the main button always goes back to the
/// biometric prompt ("Use Face ID", "Try Face ID again" after a failure)
/// and the device passcode is the secondary way in; without one there is
/// the single "Unlock".
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({
    super.key,
    this.lock,
    this.biometrics = const [],
    bool? offerBiometric,
    required this.onUnlock,
    required this.onWipe,
  }) : _offerBiometric = offerBiometric;

  final LockState? lock;

  /// Biometrics the OS names, for the label and icon.
  final List<BiometricType> biometrics;

  /// Whether the biometric button shows. Defaults to "one is named"; iOS
  /// names none before the app's first Face ID prompt, yet can still ask.
  bool get offerBiometric => _offerBiometric ?? biometrics.isNotEmpty;
  final bool? _offerBiometric;

  /// `null` lets the "Prefer biometric unlock" setting choose.
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
                  if (!offerBiometric)
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
