import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/servers/servers_provider.dart';
import '../app_log.dart';
import '../secure_cred_store.dart';
import 'decoy_config.dart';
import 'decoy_identity.dart';
import 'decoy_pin.dart';

/// The config read before the first frame (see `main.dart`), so the very
/// first build already knows whether to show Notes or MoaV Deploy. Tests
/// and the default leave disguise off.
final decoyBootProvider = Provider<DecoyConfig>((_) => DecoyConfig.off);

/// PBKDF2 work factor; tests override this to keep hashing fast.
final decoyPinIterationsProvider =
    Provider<int>((_) => DecoyPin.defaultIterations);

/// Clock for the attempt lockout, injectable in tests.
final decoyClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Reads the persisted disguise config. Never throws: a store failure
/// is logged and treated as "disguise off".
Future<DecoyConfig> loadDecoyConfig(SecureCredStore store) async {
  try {
    final json = await store.readDecoy();
    return json == null ? DecoyConfig.off : DecoyConfig.fromJson(json);
  } on Object catch (e) {
    AppLog.warn('decoy', 'config not read: ${e.runtimeType}');
    return DecoyConfig.off;
  }
}

enum PinCheck {
  /// Correct passcode: reveal the real app.
  ok,

  /// Wrong passcode (or no passcode set).
  wrong,

  /// Too many failures; [DecoyNotifier.lockoutRemaining] says how long.
  lockedOut,
}

/// Disguise on/off plus the passcode check and its rate limit.
class DecoyNotifier extends Notifier<DecoyConfig> {
  @override
  DecoyConfig build() => ref.read(decoyBootProvider);

  SecureCredStore get _store => ref.read(secureCredStoreProvider);
  DecoyIdentity get _identity => ref.read(decoyIdentityProvider);
  DateTime get _now => ref.read(decoyClockProvider)();

  /// Sets the passcode, persists the config and switches the launcher
  /// identity. On a native failure the config is rolled back and the error
  /// is rethrown for the UI to show.
  Future<void> enable({
    required String pin,
    required DecoyGesture gesture,
  }) async {
    if (!DecoyPin.isValid(pin)) {
      throw ArgumentError('Passcode must be ${DecoyPin.minLength} to '
          '${DecoyPin.maxLength} digits');
    }
    final iterations = ref.read(decoyPinIterationsProvider);
    final derived = await DecoyPin.hash(pin, iterations: iterations);
    final config = DecoyConfig(
      enabled: true,
      pinHash: derived.hash,
      salt: derived.salt,
      iterations: iterations,
      gesture: gesture,
    );
    final previous = state;
    await _store.writeDecoy(config.toJson());
    // We are inside the real app: keep it on screen while the gate flips.
    ref.read(decoyRevealedProvider.notifier).reveal();
    state = config;
    try {
      await _identity.apply(notes: true);
    } on Object {
      state = previous;
      if (previous.enabled) {
        await _store.writeDecoy(previous.toJson());
      } else {
        await _store.deleteDecoy();
      }
      rethrow;
    }
  }

  /// Restores the MoaV Deploy identity first, then forgets the passcode.
  Future<void> disable() async {
    await _identity.apply(notes: false);
    await _store.deleteDecoy();
    state = DecoyConfig.off;
  }

  /// Re-applies the Notes identity when disguise is on, so an interrupted
  /// switch (killed mid-way) heals on the next launch. Never restores the
  /// MoaV identity on its own: only [disable] does that.
  Future<void> reconcileIdentity() async {
    if (!state.enabled) return;
    try {
      await _identity.apply(notes: true);
    } on Object catch (e) {
      AppLog.warn('decoy', 'identity not applied: ${e.runtimeType}');
    }
  }

  /// Time left on the current lockout, zero when attempts are allowed.
  Duration get lockoutRemaining {
    final until = state.lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks the passcode typed on the Notes sheet. Every failure is
  /// persisted so restarting the app does not reset the counter.
  Future<PinCheck> verifyPin(String pin) async {
    final config = state;
    if (!config.enabled || !config.hasPin) return PinCheck.wrong;
    if (lockoutRemaining > Duration.zero) return PinCheck.lockedOut;
    final ok = await DecoyPin.verify(
      pin,
      hash: config.pinHash!,
      salt: config.salt!,
      iterations: config.iterations,
    );
    if (ok) {
      await _persist(config.copyWith(failedAttempts: 0, clearLockout: true));
      ref.read(decoyRevealedProvider.notifier).reveal();
      return PinCheck.ok;
    }
    final failures = config.failedAttempts + 1;
    final wait = DecoyLockout.after(failures);
    await _persist(config.copyWith(
      failedAttempts: failures,
      lockedUntil: wait == Duration.zero ? null : _now.add(wait),
      clearLockout: wait == Duration.zero,
    ));
    return wait == Duration.zero ? PinCheck.wrong : PinCheck.lockedOut;
  }

  Future<void> _persist(DecoyConfig config) async {
    state = config;
    try {
      await _store.writeDecoy(config.toJson());
    } on Object catch (e) {
      AppLog.warn('decoy', 'attempt count not saved: ${e.runtimeType}');
    }
  }
}

final decoyProvider =
    NotifierProvider<DecoyNotifier, DecoyConfig>(DecoyNotifier.new);

/// Whether the real app is currently shown behind the decoy. In-memory
/// only: every cold start and every return from the background begins at
/// the Notes screen.
class DecoyRevealNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void reveal() => state = true;

  void hide() => state = false;
}

final decoyRevealedProvider =
    NotifierProvider<DecoyRevealNotifier, bool>(DecoyRevealNotifier.new);
