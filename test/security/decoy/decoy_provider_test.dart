import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/decoy/decoy_config.dart';
import 'package:moav_deploy/security/decoy/decoy_identity.dart';
import 'package:moav_deploy/security/decoy/decoy_pin.dart';
import 'package:moav_deploy/security/decoy/decoy_provider.dart';

import '../../support/fake_decoy_identity.dart';
import '../../support/memory_cred_store.dart';

/// Disguise mode (issue #15): enable/disable state, rollback on a failed
/// launcher switch, and the passcode check with its lockout.
void main() {
  const fast = 1000;
  late MemoryCredStore store;
  late FakeDecoyIdentity identity;
  var now = DateTime.utc(2026, 10, 28, 12);

  ProviderContainer container({DecoyConfig boot = DecoyConfig.off}) {
    final c = ProviderContainer(overrides: [
      secureCredStoreProvider.overrideWithValue(store),
      decoyIdentityProvider.overrideWithValue(identity),
      decoyBootProvider.overrideWithValue(boot),
      decoyPinIterationsProvider.overrideWithValue(fast),
      decoyClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    store = MemoryCredStore();
    identity = FakeDecoyIdentity();
    now = DateTime.utc(2026, 10, 28, 12);
  });

  test('boot config is the initial state', () {
    final c = container(
      boot: const DecoyConfig(enabled: true, pinHash: 'h', salt: 's'),
    );
    expect(c.read(decoyProvider).enabled, isTrue);
    expect(c.read(decoyRevealedProvider), isFalse);
  });

  test('loadDecoyConfig reads the store and never throws', () async {
    expect(await loadDecoyConfig(store), DecoyConfig.off);
    store.decoy = const DecoyConfig(enabled: true, pinHash: 'h', salt: 's')
        .toJson();
    expect((await loadDecoyConfig(store)).enabled, isTrue);
    store.decoy = {'enabled': 'garbage', 'iterations': 'x'};
    expect((await loadDecoyConfig(store)).enabled, isFalse);
  });

  test('enable hashes the passcode, persists, switches and keeps revealed',
      () async {
    final c = container();
    await c.read(decoyProvider.notifier).enable(
          pin: '2580',
          gesture: DecoyGesture.tapTitleFiveTimes,
        );
    final state = c.read(decoyProvider);
    expect(state.enabled, isTrue);
    expect(state.hasPin, isTrue);
    expect(state.gesture, DecoyGesture.tapTitleFiveTimes);
    expect(state.iterations, fast);
    expect(store.decoy, state.toJson());
    expect(store.decoy.toString(), isNot(contains('2580')));
    expect(identity.applied, [true]);
    expect(c.read(decoyRevealedProvider), isTrue);
  });

  test('enable rejects a bad passcode before touching anything', () async {
    final c = container();
    await expectLater(
      c.read(decoyProvider.notifier).enable(
            pin: '12',
            gesture: DecoyGesture.longPressTitle,
          ),
      throwsArgumentError,
    );
    expect(store.decoy, isNull);
    expect(identity.applied, isEmpty);
    expect(c.read(decoyProvider).enabled, isFalse);
  });

  test('a failed launcher switch rolls the config back and rethrows',
      () async {
    final c = container();
    identity.fail = true;
    await expectLater(
      c.read(decoyProvider.notifier).enable(
            pin: '2580',
            gesture: DecoyGesture.longPressTitle,
          ),
      throwsA(isA<PlatformException>()),
    );
    expect(c.read(decoyProvider), DecoyConfig.off);
    expect(store.decoy, isNull);
  });

  test('disable restores the launcher first, then forgets the passcode',
      () async {
    final c = container();
    final n = c.read(decoyProvider.notifier);
    await n.enable(pin: '2580', gesture: DecoyGesture.longPressTitle);
    await n.disable();
    expect(identity.applied, [true, false]);
    expect(store.decoy, isNull);
    expect(c.read(decoyProvider), DecoyConfig.off);
  });

  test('disable keeps the config when the launcher switch fails', () async {
    final c = container();
    final n = c.read(decoyProvider.notifier);
    await n.enable(pin: '2580', gesture: DecoyGesture.longPressTitle);
    identity.fail = true;
    await expectLater(n.disable(), throwsA(isA<PlatformException>()));
    expect(c.read(decoyProvider).enabled, isTrue);
    expect(store.decoy, isNotNull);
  });

  test('reconcile re-applies Notes when on and never restores MoaV', () async {
    final off = container();
    await off.read(decoyProvider.notifier).reconcileIdentity();
    expect(identity.applied, isEmpty);

    final on = container(
      boot: const DecoyConfig(enabled: true, pinHash: 'h', salt: 's'),
    );
    await on.read(decoyProvider.notifier).reconcileIdentity();
    expect(identity.applied, [true]);

    identity.fail = true;
    await on.read(decoyProvider.notifier).reconcileIdentity();
    expect(on.read(decoyProvider).enabled, isTrue);
  });

  group('verifyPin', () {
    late DecoyConfig boot;

    setUp(() async {
      final d = await DecoyPin.hash('2580', iterations: fast);
      boot = DecoyConfig(
        enabled: true,
        pinHash: d.hash,
        salt: d.salt,
        iterations: fast,
      );
    });

    test('correct passcode reveals and resets the counter', () async {
      final c = container(boot: boot.copyWith(failedAttempts: 3));
      final n = c.read(decoyProvider.notifier);
      expect(await n.verifyPin('2580'), PinCheck.ok);
      expect(c.read(decoyRevealedProvider), isTrue);
      expect(c.read(decoyProvider).failedAttempts, 0);
      expect(store.decoy?['failedAttempts'], 0);
    });

    test('wrong passcode counts, persists and locks out after five',
        () async {
      final c = container(boot: boot);
      final n = c.read(decoyProvider.notifier);
      for (var i = 1; i <= 4; i++) {
        expect(await n.verifyPin('0000'), PinCheck.wrong, reason: '$i');
        expect(c.read(decoyProvider).failedAttempts, i);
        expect(c.read(decoyProvider).lockedUntil, isNull);
      }
      expect(c.read(decoyRevealedProvider), isFalse);
      expect(store.decoy?['failedAttempts'], 4);

      // Fifth failure: 30 seconds, and the right passcode is refused too.
      expect(await n.verifyPin('0000'), PinCheck.lockedOut);
      expect(n.lockoutRemaining, const Duration(seconds: 30));
      expect(await n.verifyPin('2580'), PinCheck.lockedOut);
      expect(c.read(decoyProvider).failedAttempts, 5);

      now = now.add(const Duration(seconds: 31));
      expect(n.lockoutRemaining, Duration.zero);
      expect(await n.verifyPin('0000'), PinCheck.lockedOut);
      expect(n.lockoutRemaining, const Duration(minutes: 1));

      now = now.add(const Duration(minutes: 2));
      expect(await n.verifyPin('2580'), PinCheck.ok);
      expect(c.read(decoyProvider).lockedUntil, isNull);
    });

    test('a persisted lockout survives a restart', () async {
      final c = container(
        boot: boot.copyWith(
          failedAttempts: 6,
          lockedUntil: now.add(const Duration(seconds: 45)),
        ),
      );
      final n = c.read(decoyProvider.notifier);
      expect(await n.verifyPin('2580'), PinCheck.lockedOut);
      expect(n.lockoutRemaining, const Duration(seconds: 45));
    });

    test('without a passcode nothing unlocks', () async {
      final c = container(boot: const DecoyConfig(enabled: true));
      expect(await c.read(decoyProvider.notifier).verifyPin(''), PinCheck.wrong);
      expect(await c.read(decoyProvider.notifier).verifyPin('1234'),
          PinCheck.wrong);
      expect(c.read(decoyRevealedProvider), isFalse);
    });
  });
}
