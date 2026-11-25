import 'package:flutter/material.dart' hide LockState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/lock/app_lock_sheet.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_lock.dart';
import '../support/memory_cred_store.dart';

/// Device feedback (iOS, TestFlight 0.2.17 build 22): with Face ID enrolled
/// the app asked for the passcode and the App lock setting sat disabled
/// under "No Face ID or fingerprint is set up on this device".
///
/// On iOS `getAvailableBiometrics()` is empty whenever the app cannot use
/// the biometric right now, which includes "Face ID is off for this app".
/// An empty list there is no longer read as "this device has none".

/// A [LocalAuthentication] answering from fields.
class _FakeAuth implements LocalAuthentication {
  bool supported = true;
  List<BiometricType> enrolled = const [];

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ScriptedLock _ios({List<BiometricType> enrolled = const []}) =>
    ScriptedLock(enrolled: enrolled, platform: TargetPlatform.iOS);

ProviderContainer _container(ScriptedLock lock, {MemoryCredStore? store}) {
  final c = ProviderContainer(
    retry: noProviderRetry,
    overrides: [
      secureCredStoreProvider.overrideWithValue(store ?? MemoryCredStore()),
      appLockServiceProvider.overrideWithValue(lock),
    ],
  );
  addTearDown(c.dispose);
  c.listen(appLockProvider, (_, _) {});
  c.listen(biometricStatusProvider, (_, _) {});
  return c;
}

void main() {
  group('what an empty list means', () {
    Future<BiometricStatus> status(_FakeAuth auth, TargetPlatform platform) async {
      final service = AppLockService(auth, platform);
      return service.biometricStatus(await service.enrolledBiometrics());
    }

    test('iOS and macOS: not "none" while the device can lock', () async {
      final auth = _FakeAuth();
      expect(await status(auth, TargetPlatform.iOS), BiometricStatus.unconfirmed);
      expect(await status(auth, TargetPlatform.macOS), BiometricStatus.unconfirmed);
      expect(BiometricStatus.unconfirmed.offered, isTrue);
    });

    test('iOS without any device lock: nothing to offer', () async {
      final auth = _FakeAuth()..supported = false;
      expect(await status(auth, TargetPlatform.iOS), BiometricStatus.unavailable);
    });

    test('Android: the list is the whole answer, as before', () async {
      final auth = _FakeAuth();
      expect(await status(auth, TargetPlatform.android), BiometricStatus.unavailable);
      auth.enrolled = const [BiometricType.strong];
      expect(await status(auth, TargetPlatform.android), BiometricStatus.ready);
    });

    test('a named biometric is ready on every platform', () async {
      final auth = _FakeAuth()..enrolled = const [BiometricType.face];
      expect(await status(auth, TargetPlatform.iOS), BiometricStatus.ready);
      for (final s in [
        BiometricStatus.denied,
        BiometricStatus.notEnrolled,
        BiometricStatus.unavailable,
      ]) {
        expect(s.offered, isFalse, reason: s.name);
      }
    });
  });

  group('unlocking on iOS with nothing named', () {
    test('asks for the biometric, and the OS names it once allowed', () async {
      final lock = _ios()
        ..enrolledOnceAllowed = const [BiometricType.face]
        ..outcomes.clear()
        ..outcomes.add(AuthOutcome.success);
      final c = _container(lock);
      await c.read(appLockProvider.notifier).unlock();
      expect(lock.prompts, [true]);
      expect(c.read(appLockProvider), LockState.unlocked);
      expect(c.read(biometricStatusProvider), BiometricStatus.ready);
      expect(c.read(enrolledBiometricsProvider), [BiometricType.face]);
    });

    test('off for this app: the passcode, and it is remembered as denied',
        () async {
      final lock = _ios()
        ..outcomes.clear()
        ..outcomes.addAll([AuthOutcome.biometricRefused, AuthOutcome.success]);
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      expect(lock.prompts, [true, false]);
      expect(c.read(appLockProvider), LockState.unlocked);
      expect(c.read(biometricStatusProvider), BiometricStatus.denied);

      // Known now: no pointless biometric attempt on the next unlock, not
      // even when asked for by name.
      notifier.lock();
      await notifier.unlock();
      await notifier.unlock(method: UnlockMethod.biometric);
      expect(lock.prompts, [true, false, false, false]);
      expect(c.read(biometricStatusProvider), BiometricStatus.denied);

      // Allowed in Settings: the OS names it and it is offered again.
      lock.enrolled = const [BiometricType.face];
      await c.read(biometricStatusProvider.notifier).refresh();
      expect(c.read(biometricStatusProvider), BiometricStatus.ready);
      notifier.lock();
      await notifier.unlock();
      expect(lock.prompts.last, isTrue);
    });

    test('none enrolled, and no sensor at all, are told apart from denied',
        () async {
      final lock = _ios()
        ..outcomes.clear()
        ..outcomes.addAll([AuthOutcome.biometricNotEnrolled, AuthOutcome.success]);
      final c = _container(lock);
      await c.read(appLockProvider.notifier).unlock();
      expect(lock.prompts, [true, false]);
      expect(c.read(biometricStatusProvider), BiometricStatus.notEnrolled);

      final bare = _ios()
        ..sensor = false
        ..outcomes.clear()
        ..outcomes.addAll([AuthOutcome.biometricRefused, AuthOutcome.success]);
      final c2 = _container(bare);
      await c2.read(appLockProvider.notifier).unlock();
      expect(c2.read(appLockProvider), LockState.unlocked);
      expect(c2.read(biometricStatusProvider), BiometricStatus.unavailable);
    });

    test('a lockout settles nothing: the passcode clears it', () async {
      final lock = _ios()
        ..enrolledOnceAllowed = const [BiometricType.face]
        ..outcomes.clear()
        ..outcomes.addAll([AuthOutcome.biometricUnavailable, AuthOutcome.success]);
      final c = _container(lock);
      await c.read(appLockProvider.notifier).unlock();
      expect(lock.prompts, [true, false]);
      expect(c.read(biometricStatusProvider), BiometricStatus.ready);
    });

    test('a cancelled prompt leaves it offered', () async {
      final lock = _ios();
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      await notifier.unlock();
      expect(lock.prompts, [true, true]);
      expect(c.read(appLockProvider), LockState.failed);
      expect(c.read(biometricStatusProvider), BiometricStatus.unconfirmed);
    });

    test('"Prefer biometric unlock" off: the OS prompt, nothing forced',
        () async {
      final lock = _ios();
      final c = _container(lock, store: MemoryCredStore()..preferBiometric = false);
      await c.read(appLockProvider.notifier).unlock();
      expect(lock.prompts, [false]);
    });

    test('Android with nothing enrolled never gets a biometric-only prompt',
        () async {
      final lock = ScriptedLock(
        enrolled: const [],
        platform: TargetPlatform.android,
      );
      final c = _container(lock);
      final notifier = c.read(appLockProvider.notifier);
      await notifier.unlock();
      await notifier.unlock(method: UnlockMethod.biometric);
      expect(lock.prompts, [false, false]);
      expect(c.read(biometricStatusProvider), BiometricStatus.unavailable);
    });
  });

  group('lock screen on iOS', () {
    testWidgets('offers the biometric before the OS has named one',
        (tester) async {
      final asked = <UnlockMethod?>[];
      Widget shield({required bool offer}) => MaterialApp(
            theme: moavDarkTheme().copyWith(platform: TargetPlatform.iOS),
            home: PrivacyShield(
              lock: LockState.failed,
              offerBiometric: offer,
              onUnlock: asked.add,
              onWipe: () {},
            ),
          );

      await tester.pumpWidget(shield(offer: true));
      expect(find.text('Try Face ID or Touch ID again'), findsOneWidget);
      await tester.tap(find.text('Try Face ID or Touch ID again'));
      await tester.tap(find.text('Use device passcode'));
      expect(asked, [UnlockMethod.biometric, UnlockMethod.deviceCredential]);

      // Known to be off or not enrolled: the single button.
      await tester.pumpWidget(shield(offer: false));
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Use device passcode'), findsNothing);
    });
  });

  group('App lock setting on iOS', () {
    late int settingsOpened;

    Future<ProviderContainer> open(
      WidgetTester tester,
      ScriptedLock lock, {
      MemoryCredStore? store,
    }) async {
      settingsOpened = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            secureCredStoreProvider.overrideWithValue(store ?? MemoryCredStore()),
            appLockServiceProvider.overrideWithValue(lock),
          ],
          child: MaterialApp(
            theme: moavDarkTheme().copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: AppLockSheet(openSettings: () async => settingsOpened++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(AppLockSheet)));
    }

    SwitchListTile tile(WidgetTester tester) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Prefer biometric unlock'));

    testWidgets('nothing named yet: usable, and setting it up asks for Face ID',
        (tester) async {
      final lock = _ios()
        ..enrolledOnceAllowed = const [BiometricType.face]
        ..outcomes.clear()
        ..outcomes.add(AuthOutcome.success);
      await open(tester, lock);

      expect(tile(tester).onChanged, isNotNull);
      expect(tile(tester).value, isTrue);
      expect(find.textContaining('No Face ID or fingerprint'), findsNothing);
      expect(lock.prompts, isEmpty);

      await tester.tap(find.text('Set up Face ID or Touch ID'));
      await tester.pumpAndSettle();
      expect(lock.prompts, [true]);
      expect(find.textContaining('Always try Face ID first'), findsOneWidget);
      expect(find.textContaining('Set up'), findsNothing);
    });

    testWidgets('switching it on asks for the biometric and is remembered',
        (tester) async {
      final store = MemoryCredStore()..preferBiometric = false;
      final lock = _ios()
        ..enrolledOnceAllowed = const [BiometricType.face]
        ..outcomes.clear()
        ..outcomes.add(AuthOutcome.success);
      await open(tester, lock, store: store);
      expect(tile(tester).value, isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(store.preferBiometric, isTrue);
      expect(lock.prompts, [true]);
      expect(tile(tester).value, isTrue);
      expect(find.textContaining('Always try Face ID first'), findsOneWidget);
    });

    testWidgets('off for this app: says so and opens Settings', (tester) async {
      final store = MemoryCredStore();
      final lock = _ios()
        ..outcomes.clear()
        ..outcomes.add(AuthOutcome.biometricRefused);
      await open(tester, lock, store: store);
      await tester.tap(find.text('Set up Face ID or Touch ID'));
      await tester.pumpAndSettle();

      expect(find.textContaining('switched off for this app'), findsOneWidget);
      expect(find.textContaining('No Face ID or fingerprint'), findsNothing);
      expect(tile(tester).onChanged, isNull);
      expect(tile(tester).value, isFalse);
      // The stored choice is untouched: it applies again once allowed.
      expect(store.preferBiometric, isTrue);

      await tester.tap(find.text('Open Settings'));
      expect(settingsOpened, 1);

      // Back from Settings with Face ID allowed.
      lock.enrolled = const [BiometricType.face];
      final c = ProviderScope.containerOf(tester.element(find.byType(AppLockSheet)));
      await c.read(biometricStatusProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('Always try Face ID first'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(tile(tester).value, isTrue);
    });

    testWidgets('none enrolled: the "not set up on this device" copy',
        (tester) async {
      final lock = _ios()
        ..outcomes.clear()
        ..outcomes.add(AuthOutcome.biometricNotEnrolled);
      await open(tester, lock);
      await tester.tap(find.text('Set up Face ID or Touch ID'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No Face ID or fingerprint is set up'), findsOneWidget);
      expect(tile(tester).onChanged, isNull);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.textContaining('Set up Face ID'), findsNothing);
    });
  });
}
