import 'dart:async';

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/lock/app_lock_sheet.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_lock.dart';
import '../support/memory_cred_store.dart';

/// Device feedback: after one failed Face ID the app ended up on the
/// passcode and never offered Face ID again in that session. Every unlock
/// attempt now picks its method afresh, biometric first, and the lock
/// screen always has a way back to the biometric prompt.

/// A [LocalAuthentication] that answers from fields, to check how
/// [AppLockService] asks and how it reads the platform's errors.
class _FakeAuth implements LocalAuthentication {
  bool supported = true;
  List<BiometricType> enrolled = const [BiometricType.face];
  Object? enrolledError;

  /// Returned by `authenticate`, or thrown when it is an exception.
  Object answer = true;
  final asked = <bool>[];

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    final e = enrolledError;
    if (e != null) throw e;
    return enrolled;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    asked.add(biometricOnly);
    final a = answer;
    if (a is bool) return a;
    throw a;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A secure store whose preference read never completes.
class _StuckStore extends MemoryCredStore {
  @override
  Future<bool> readPreferBiometric() => Completer<bool>().future;
}

ProviderContainer _container(ScriptedLock lock, {bool prefer = true}) {
  final c = ProviderContainer(
    retry: noProviderRetry,
    overrides: [
      secureCredStoreProvider
          .overrideWithValue(MemoryCredStore()..preferBiometric = prefer),
      appLockServiceProvider.overrideWithValue(lock),
    ],
  );
  addTearDown(c.dispose);
  c.listen(appLockProvider, (_, _) {});
  return c;
}

Widget _app(AppLockService lock, {MemoryCredStore? store, bool lockEnabled = true}) =>
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store ?? MemoryCredStore()),
        onboardingStoreProvider.overrideWithValue(OnboardedStore()),
        appLockServiceProvider.overrideWithValue(lock),
      ],
      child: MoavDeployApp(lockEnabled: lockEnabled),
    );

void main() {
  group('AppLockService', () {
    test('asks for the biometric alone only when told to', () async {
      final auth = _FakeAuth();
      final service = AppLockService(auth);
      expect(await service.authenticate(biometricOnly: true), AuthOutcome.success);
      expect(await service.authenticate(), AuthOutcome.success);
      expect(auth.asked, [true, false]);
      auth.answer = false;
      expect(await service.authenticate(biometricOnly: true), AuthOutcome.failed);
    });

    test('reads the platform errors of a biometric-only prompt', () async {
      final auth = _FakeAuth();
      final service = AppLockService(auth);
      Future<AuthOutcome> ask(LocalAuthExceptionCode code, {bool biometricOnly = true}) {
        auth.answer = LocalAuthException(code: code);
        return service.authenticate(biometricOnly: biometricOnly);
      }

      expect(await ask(LocalAuthExceptionCode.userCanceled), AuthOutcome.failed);
      expect(await ask(LocalAuthExceptionCode.systemCanceled), AuthOutcome.failed);
      expect(await ask(LocalAuthExceptionCode.userRequestedFallback),
          AuthOutcome.fallbackRequested);
      for (final code in [
        LocalAuthExceptionCode.temporaryLockout,
        LocalAuthExceptionCode.biometricLockout,
        LocalAuthExceptionCode.noBiometricsEnrolled,
        LocalAuthExceptionCode.noBiometricHardware,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
      ]) {
        expect(await ask(code), AuthOutcome.biometricUnavailable, reason: code.name);
      }
      // The passcode prompt has nowhere further to fall back to.
      expect(await ask(LocalAuthExceptionCode.biometricLockout, biometricOnly: false),
          AuthOutcome.failed);
      auth.answer = StateError('plugin missing');
      expect(await service.authenticate(biometricOnly: true), AuthOutcome.failed);
    });

    test('enrollment: what the OS says, empty when it will not say', () async {
      final auth = _FakeAuth();
      final service = AppLockService(auth);
      expect(await service.enrolledBiometrics(), [BiometricType.face]);
      auth.enrolledError = StateError('no plugin');
      expect(await service.enrolledBiometrics(), isEmpty);
    });

    test('a device with no lock at all is never bricked', () async {
      final auth = _FakeAuth()..supported = false;
      expect(await AppLockService(auth).authenticate(biometricOnly: true),
          AuthOutcome.success);
      expect(auth.asked, isEmpty);
    });

    test('labels: Face ID and Touch ID on Apple, generic elsewhere', () {
      expect(biometricLabel([BiometricType.face], TargetPlatform.iOS), 'Face ID');
      expect(biometricLabel([BiometricType.fingerprint], TargetPlatform.iOS), 'Touch ID');
      expect(biometricLabel([BiometricType.strong], TargetPlatform.android), 'biometrics');
      expect(biometricLabel([BiometricType.face], TargetPlatform.android), 'biometrics');
    });
  });

  group('unlock attempts', () {
    test('biometric first, and again after a failure: nothing sticks',
        () async {
      final lock = ScriptedLock();
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);

      await notifier.unlock();
      expect(c.read(appLockProvider), LockState.failed);
      // The very next attempt is the biometric again, not the passcode.
      await notifier.unlock();
      await notifier.unlock();
      expect(lock.prompts, [true, true, true]);

      lock.outcomes
        ..clear()
        ..add(AuthOutcome.success);
      await notifier.unlock();
      expect(lock.prompts.last, isTrue);
      expect(c.read(appLockProvider), LockState.unlocked);
    });

    test('choosing the passcode once does not choose it for the next attempt',
        () async {
      final lock = ScriptedLock();
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      await notifier.unlock(method: UnlockMethod.deviceCredential);
      // Locked again later (app backgrounded): back to the biometric.
      notifier.lock();
      await notifier.unlock();
      expect(lock.prompts, [true, false, true]);
    });

    test('"Use passcode" on the sheet goes to the passcode in that attempt',
        () async {
      final lock = ScriptedLock()
        ..outcomes.clear()
        ..outcomes.addAll([AuthOutcome.fallbackRequested, AuthOutcome.success]);
      final c = _container(lock);
      await c.read(appLockProvider.notifier).unlock();
      expect(lock.prompts, [true, false]);
      expect(c.read(appLockProvider), LockState.unlocked);
    });

    test('a biometric lockout falls through to the passcode, then recovers',
        () async {
      final lock = ScriptedLock()
        ..outcomes.clear()
        ..outcomes.addAll([
          AuthOutcome.biometricUnavailable,
          AuthOutcome.success,
          AuthOutcome.success,
        ]);
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      expect(lock.prompts, [true, false]);
      expect(c.read(appLockProvider), LockState.unlocked);
      // The passcode cleared the lockout; the next unlock is biometric.
      notifier.lock();
      await notifier.unlock();
      expect(lock.prompts, [true, false, true]);
    });

    test('nothing enrolled: the passcode prompt, even when asked for Face ID',
        () async {
      final lock = ScriptedLock(enrolled: const []);
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      await notifier.unlock(method: UnlockMethod.biometric);
      expect(lock.prompts, [false, false]);
      expect(c.read(enrolledBiometricsProvider), isEmpty);
    });

    test('enrollment is read on every attempt', () async {
      final lock = ScriptedLock(enrolled: const []);
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      lock.enrolled = const [BiometricType.fingerprint];
      await notifier.unlock();
      expect(c.read(enrolledBiometricsProvider), [BiometricType.fingerprint]);
      lock.enrolled = const [];
      await notifier.unlock();
      expect(lock.prompts, [false, true, false]);
    });

    test('setting off: the OS prompt decides, Face ID still one tap away',
        () async {
      final lock = ScriptedLock();
      final c = _container(lock, prefer: false);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      await notifier.unlock(method: UnlockMethod.biometric);
      expect(lock.prompts, [false, true]);
    });

    test('a store that never answers does not hold the prompt back', () async {
      final lock = ScriptedLock();
      final c = ProviderContainer(
        retry: noProviderRetry,
        overrides: [
          secureCredStoreProvider.overrideWithValue(_StuckStore()),
          appLockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      c.listen(appLockProvider, (_, _) {});
      await c.read(appLockProvider.notifier).unlock();
      // Fell back to the default (biometric first) after the short wait.
      expect(lock.prompts, [true]);
    });

    test('the setting is on by default and remembered when changed', () async {
      final store = MemoryCredStore();
      final c = ProviderContainer(
        retry: noProviderRetry,
        overrides: [secureCredStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      expect(await c.read(preferBiometricProvider.future), isTrue);
      await c.read(preferBiometricProvider.notifier).set(false);
      expect(store.preferBiometric, isFalse);
      expect(c.read(preferBiometricProvider).value, isFalse);
      // A wipe puts it back to the default.
      await store.wipeAll();
      expect(await store.readPreferBiometric(), isTrue);
    });

    test('two unlock calls share one prompt', () async {
      final lock = GatedLock()..enrolled = const [BiometricType.face];
      final c = ProviderContainer(
        retry: noProviderRetry,
        overrides: [
          secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
          appLockServiceProvider.overrideWithValue(lock),
        ],
      );
      addTearDown(c.dispose);
      c.listen(appLockProvider, (_, _) {});
      final notifier = c.read(appLockProvider.notifier);
      final first = notifier.unlock();
      await Future<void>.delayed(Duration.zero);
      // Backgrounded and resumed while the prompt is still up.
      notifier.lock();
      final second = notifier.unlock();
      await Future<void>.delayed(Duration.zero);
      expect(lock.gates, hasLength(1));
      expect(c.read(appLockProvider), LockState.unlocking);
      lock.gates.single.complete(true);
      await Future.wait([first, second]);
      expect(c.read(appLockProvider), LockState.unlocked);
    });
  });

  group('lock screen', () {
    testWidgets('after a failed Face ID: try again, or the passcode',
        (tester) async {
      final lock = GatedLock()..enrolled = const [BiometricType.face];
      await tester.pumpWidget(_app(lock));
      await tester.pump();
      await tester.pump();
      expect(lock.biometricOnly, [true]);

      lock.gates.last.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Unlock failed'), findsOneWidget);
      // Android in tests, so the generic word; iOS says "Face ID" (below).
      expect(find.text('Try biometrics again'), findsOneWidget);
      expect(find.text('Use device passcode'), findsOneWidget);
      expect(find.text('Emergency wipe'), findsOneWidget);

      // Back to the biometric prompt, as often as it takes.
      await tester.tap(find.text('Try biometrics again'));
      await tester.pump();
      await tester.pump();
      expect(lock.biometricOnly, [true, true]);
      lock.gates.last.complete(false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use device passcode'));
      await tester.pump();
      await tester.pump();
      expect(lock.biometricOnly, [true, true, false]);
      lock.gates.last.complete(false);
      await tester.pumpAndSettle();
      // Cancelled the passcode sheet: Face ID is still offered.
      expect(find.text('Try biometrics again'), findsOneWidget);

      await tester.tap(find.text('Try biometrics again'));
      await tester.pump();
      await tester.pump();
      expect(lock.biometricOnly.last, isTrue);
      lock.gates.last.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyShield), findsNothing);
      expect(find.text('No servers yet'), findsOneWidget);
    });

    testWidgets('nothing enrolled: the single Unlock button, as before',
        (tester) async {
      final lock = GatedLock();
      await tester.pumpWidget(_app(lock));
      await tester.pump();
      await tester.pump();
      expect(lock.biometricOnly, [false]);
      lock.gates.last.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Use device passcode'), findsNothing);
      expect(find.textContaining('again'), findsNothing);
    });

    testWidgets('names the sensor on iOS and keeps the wipe reachable',
        (tester) async {
      final asked = <UnlockMethod?>[];
      Widget shield(LockState state, List<BiometricType> enrolled) => MaterialApp(
            theme: moavDarkTheme().copyWith(platform: TargetPlatform.iOS),
            home: PrivacyShield(
              lock: state,
              biometrics: enrolled,
              onUnlock: asked.add,
              onWipe: () {},
            ),
          );

      await tester.pumpWidget(shield(LockState.locked, const [BiometricType.face]));
      expect(find.text('Use Face ID'), findsOneWidget);
      await tester.pumpWidget(shield(LockState.failed, const [BiometricType.face]));
      expect(find.text('Try Face ID again'), findsOneWidget);
      expect(find.text('Emergency wipe'), findsOneWidget);
      await tester.tap(find.text('Try Face ID again'));
      await tester.tap(find.text('Use device passcode'));
      expect(asked, [UnlockMethod.biometric, UnlockMethod.deviceCredential]);

      await tester.pumpWidget(shield(LockState.failed, const [BiometricType.fingerprint]));
      expect(find.text('Try Touch ID again'), findsOneWidget);
      // While the prompt is up there is nothing to tap.
      await tester.pumpWidget(shield(LockState.unlocking, const [BiometricType.face]));
      expect(find.textContaining('Face ID'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('App lock setting', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
    }

    testWidgets('on by default, and switching it off is remembered',
        (tester) async {
      final store = MemoryCredStore();
      final lock = ScriptedLock(enrolled: const [BiometricType.fingerprint]);
      await tester.pumpWidget(_app(lock, store: store, lockEnabled: false));
      await tester.pumpAndSettle();
      await open(tester);

      expect(find.byType(AppLockSheet), findsOneWidget);
      final tile = find.widgetWithText(SwitchListTile, 'Prefer biometric unlock');
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      expect(find.textContaining('Always try biometrics first'), findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(store.preferBiometric, isFalse);
    });

    testWidgets('disabled, with the reason, when nothing is enrolled',
        (tester) async {
      final store = MemoryCredStore();
      final lock = ScriptedLock(enrolled: const []);
      await tester.pumpWidget(_app(lock, store: store, lockEnabled: false));
      await tester.pumpAndSettle();
      await open(tester);

      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Prefer biometric unlock'));
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
      expect(find.textContaining('No Face ID or fingerprint is set up'), findsOneWidget);
      // The stored choice is untouched: it applies again once one is set up.
      expect(store.preferBiometric, isTrue);
    });
  });
}
