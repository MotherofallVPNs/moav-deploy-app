import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/notes/notes_app.dart';
import 'package:moav_deploy/features/notes/notes_store.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/decoy/decoy_config.dart';
import 'package:moav_deploy/security/decoy/decoy_gate.dart';
import 'package:moav_deploy/security/decoy/decoy_identity.dart';
import 'package:moav_deploy/security/decoy/decoy_pin.dart';
import 'package:moav_deploy/security/decoy/decoy_provider.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../../support/fake_decoy_identity.dart';
import '../../support/memory_cred_store.dart';

/// Disguise mode (issue #15): a disguised launch is a Notes app and
/// nothing else; the secret unlock leads to the real lock gate; leaving
/// the app puts the decoy back.

const _fast = 1000;
const _pin = '2580';

class _GatedLock extends AppLockService {
  final gates = <Completer<bool>>[];
  final reasons = <bool>[];

  @override
  Future<bool> canLock() async => true;

  @override
  Future<bool> authenticate({bool disguised = false}) {
    reasons.add(disguised);
    final c = Completer<bool>();
    gates.add(c);
    return c.future;
  }
}

class _Onboarded implements OnboardingStore {
  @override
  Future<bool> isComplete() async => true;
  @override
  Future<void> markComplete() async {}
}

Future<DecoyConfig> _config({
  DecoyGesture gesture = DecoyGesture.longPressTitle,
  int failedAttempts = 0,
}) async {
  final d = await DecoyPin.hash(_pin, iterations: _fast);
  return DecoyConfig(
    enabled: true,
    pinHash: d.hash,
    salt: d.salt,
    iterations: _fast,
    gesture: gesture,
    failedAttempts: failedAttempts,
  );
}

Widget _app(
  DecoyConfig boot, {
  required _GatedLock lock,
  required FakeDecoyIdentity identity,
  required MemoryNotesStore notes,
  MemoryCredStore? store,
}) =>
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store ?? MemoryCredStore()),
        onboardingStoreProvider.overrideWithValue(_Onboarded()),
        appLockServiceProvider.overrideWithValue(lock),
        decoyIdentityProvider.overrideWithValue(identity),
        decoyBootProvider.overrideWithValue(boot),
        decoyPinIterationsProvider.overrideWithValue(_fast),
        notesStoreProvider.overrideWithValue(notes),
      ],
      child: const MoavDeployApp(),
    );

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState s) async {
  tester.binding.handleAppLifecycleStateChanged(s);
  await tester.pump();
}

void _expectNotesOnly(WidgetTester tester) {
  expect(find.byType(NotesApp), findsOneWidget);
  expect(find.text('Notes'), findsOneWidget);
  expect(find.textContaining('MoaV'), findsNothing);
  expect(find.textContaining('Deploy'), findsNothing);
  expect(find.byType(MoavMark), findsNothing);
  expect(find.byType(PrivacyShield), findsNothing);
  expect(find.byType(AppLockGate), findsNothing);
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.title, 'Notes');
}

/// Submits the passcode and pumps through the hash and the sheet
/// animation. Not pumpAndSettle: on success the lock gate's spinner never
/// settles.
Future<void> _enterPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.widgetWithText(TextField, 'Passcode'), pin);
  await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late _GatedLock lock;
  late FakeDecoyIdentity identity;
  late MemoryNotesStore notes;

  setUp(() {
    lock = _GatedLock();
    identity = FakeDecoyIdentity();
    notes = MemoryNotesStore();
  });

  testWidgets('a disguised launch shows only the Notes app', (tester) async {
    final boot = await _config();
    await tester.pumpWidget(
        _app(boot, lock: lock, identity: identity, notes: notes));
    await tester.pumpAndSettle();
    _expectNotesOnly(tester);
    expect(find.text('No notes yet'), findsOneWidget);
    // No biometric prompt until the secret unlock.
    expect(lock.gates, isEmpty);
    // The launcher identity was re-applied on launch.
    expect(identity.applied, [true]);
  });

  testWidgets('with disguise off the gate is transparent', (tester) async {
    await tester.pumpWidget(_app(DecoyConfig.off,
        lock: lock, identity: identity, notes: notes));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NotesApp), findsNothing);
    expect(find.byType(PrivacyShield), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'MoaV Deploy');
    expect(identity.applied, isEmpty);
    expect(lock.reasons, [false]);
  });

  testWidgets('notes can be written, listed and deleted', (tester) async {
    final boot = await _config();
    await tester.pumpWidget(
        _app(boot, lock: lock, identity: identity, notes: notes));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Groceries');
    await tester.enterText(
        find.widgetWithText(TextField, 'Start writing'), 'milk\neggs');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    expect(notes.notes, hasLength(1));
    expect(notes.notes.single.body, 'milk\neggs');
    _expectNotesOnly(tester);

    await tester.drag(find.text('Groceries'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsNothing);
    expect(notes.notes, isEmpty);
  });

  testWidgets('long-press title, passcode, then the real lock gate',
      (tester) async {
    final boot = await _config();
    final store = MemoryCredStore();
    await tester.pumpWidget(_app(boot,
        lock: lock, identity: identity, notes: notes, store: store));
    await tester.pumpAndSettle();

    // A plain tap does nothing in long-press mode.
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Locked notes'), findsNothing);

    await tester.longPress(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Locked notes'), findsOneWidget);

    await _enterPin(tester, '0000');
    expect(find.text('Incorrect passcode'), findsOneWidget);
    _expectNotesOnly(tester);
    expect(store.decoy?['failedAttempts'], 1);

    await _enterPin(tester, _pin);
    // The real app, behind its lock gate; the prompt is up and neutral.
    expect(find.byType(NotesApp), findsNothing);
    expect(find.byType(PrivacyShield), findsOneWidget);
    expect(find.byType(MoavMark), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(lock.gates, hasLength(1));
    expect(lock.reasons, [true]);
    // Task-switcher label stays Notes even while revealed.
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Notes');
    expect(store.decoy?['failedAttempts'], 0);

    lock.gates.single.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('No servers yet'), findsOneWidget);

    // Task switcher snapshot: a plain cover; the real app is offstage
    // (kept alive, but neither painted nor exposed to screen readers).
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(find.byType(DecoyCover), findsOneWidget);
    expect(find.byType(MoavMark), findsNothing);
    expect(find.text('No servers yet'), findsNothing);
    expect(find.text('No servers yet', skipOffstage: false), findsOneWidget);
    expect(tester.getSize(find.byType(DecoyCover)),
        tester.getSize(find.byType(DecoyGate)));
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(DecoyCover), findsNothing);
    expect(find.text('No servers yet'), findsOneWidget);

    // Leaving the app hides the real app again: back to Notes on resume,
    // and no biometric prompt appears over the decoy.
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    _expectNotesOnly(tester);
    expect(lock.gates, hasLength(1));
  });

  testWidgets('five taps on the title is the other gesture', (tester) async {
    final boot = await _config(gesture: DecoyGesture.tapTitleFiveTimes);
    await tester.pumpWidget(
        _app(boot, lock: lock, identity: identity, notes: notes));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Locked notes'), findsNothing);
    // A held press still counts as one tap; let the (wall-clock) tap
    // window lapse before counting.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Notes'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Locked notes'), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Locked notes'), findsOneWidget);

    await _enterPin(tester, _pin);
    expect(find.byType(PrivacyShield), findsOneWidget);
  });

  testWidgets('the lockout is shown on the sheet', (tester) async {
    final boot = await _config(failedAttempts: 4);
    await tester.pumpWidget(
        _app(boot, lock: lock, identity: identity, notes: notes));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Notes'));
    await tester.pumpAndSettle();
    await _enterPin(tester, '0000');
    expect(find.text('Try again in 30 seconds'), findsOneWidget);
    await _enterPin(tester, _pin);
    expect(find.text('Try again in 30 seconds'), findsOneWidget);
    _expectNotesOnly(tester);
  });

  test('formatWait and formatNoteDate read naturally', () {
    expect(formatWait(const Duration(seconds: 30)), '30 seconds');
    expect(formatWait(const Duration(milliseconds: 400)), '1 second');
    expect(formatWait(const Duration(seconds: 61)), '2 minutes');
    expect(formatWait(const Duration(minutes: 60)), '1 hour');
    final now = DateTime(2026, 10, 28, 14, 5);
    expect(formatNoteDate(DateTime(2026, 10, 28, 9, 7), now: now), '09:07');
    expect(formatNoteDate(DateTime(2026, 3, 3), now: now), '3 Mar');
    expect(formatNoteDate(DateTime(2025, 3, 3), now: now), '3 Mar 2025');
  });

  test('the platform identity is a no-op off Android and iOS', () async {
    expect(DecoyIdentity.forPlatform(), isA<MethodChannelDecoyIdentity>());
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final id = DecoyIdentity.forPlatform();
    expect(id, isA<UnsupportedDecoyIdentity>());
    expect((await id.capabilities()).switchIcon, isFalse);
    expect(await id.isNotes(), isFalse);
    expect(await id.closeApp(), isFalse);
    await id.apply(notes: true);
  });
}
