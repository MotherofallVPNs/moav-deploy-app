import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/notes/notes_app.dart';
import 'package:moav_deploy/features/notes/notes_store.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/decoy/decoy_identity.dart';
import 'package:moav_deploy/security/decoy/decoy_provider.dart';

import '../support/fake_decoy_identity.dart';
import '../support/memory_cred_store.dart';

/// Disguise mode (issue #15): the settings screen behind the home menu.

Widget _app(MemoryCredStore store, FakeDecoyIdentity identity) =>
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        decoyIdentityProvider.overrideWithValue(identity),
        decoyPinIterationsProvider.overrideWithValue(1000),
        notesStoreProvider.overrideWithValue(MemoryNotesStore()),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

Future<void> _openScreen(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Disguise mode'));
  await tester.pumpAndSettle();
}

/// The screen is a lazy ListView: scroll the target into view first.
Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String pin, String confirm) async {
  final pinField = find.widgetWithText(TextField, 'Disguise passcode');
  await _show(tester, pinField);
  await tester.enterText(pinField, pin);
  final confirmField = find.widgetWithText(TextField, 'Repeat passcode');
  await _show(tester, confirmField);
  await tester.enterText(confirmField, confirm);
  await _tap(tester, find.text('Turn on disguise'));
}

void main() {
  testWidgets('Android: explains the swap, validates, enables and disables',
      (tester) async {
    final store = MemoryCredStore();
    final identity = FakeDecoyIdentity();
    await tester.pumpWidget(_app(store, identity));
    await tester.pumpAndSettle();
    await _openScreen(tester);

    expect(find.text('Look like a Notes app'), findsOneWidget);
    expect(find.textContaining('shows Notes with a notes icon'),
        findsOneWidget);
    expect(find.textContaining('Settings > Apps still lists MoaV Deploy'),
        findsOneWidget);
    await _show(tester, find.text('Tap the Notes title five times'));
    expect(find.text('Press and hold the Notes title'), findsOneWidget);

    await _fill(tester, '12', '12');
    expect(find.text('Use 4 to 12 digits'), findsOneWidget);
    expect(identity.applied, isEmpty);

    await _fill(tester, '2580', '2581');
    expect(find.text('The two passcodes do not match'), findsOneWidget);
    expect(identity.applied, isEmpty);

    await _tap(tester, find.text('Tap the Notes title five times'));
    await _fill(tester, '2580', '2580');
    expect(find.widgetWithText(AlertDialog, 'Disguise is on'), findsOneWidget);
    expect(find.textContaining('Tap the Notes title five times, then enter'),
        findsOneWidget);
    expect(find.text('Close app'), findsOneWidget);
    expect(identity.applied, [true]);
    expect(store.decoy?['enabled'], true);
    expect(store.decoy?['gesture'], 'tapTitleFiveTimes');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    // Still inside the real app (revealed), now showing the status card.
    expect(find.byType(NotesApp), findsNothing);
    await _show(tester, find.text('Turn off disguise'));
    expect(find.text('Disguise is on'), findsOneWidget);
    expect(find.text('Turn on disguise'), findsNothing);

    await _tap(tester, find.text('Turn off disguise'));
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Disguise is off'), findsOneWidget);
    await tester.tap(find.text('Close app'));
    await tester.pumpAndSettle();
    expect(identity.applied, [true, false]);
    expect(identity.closed, isTrue);
    expect(store.decoy, isNull);
    await _show(tester, find.text('Turn on disguise'));
    expect(find.text('Turn off disguise'), findsNothing);
  });

  testWidgets('a failed launcher switch is reported and leaves disguise off',
      (tester) async {
    final store = MemoryCredStore();
    final identity = FakeDecoyIdentity()..fail = true;
    await tester.pumpWidget(_app(store, identity));
    await tester.pumpAndSettle();
    await _openScreen(tester);
    await _fill(tester, '2580', '2580');
    expect(find.textContaining('Disguise not turned on.'), findsOneWidget);
    expect(find.text('Disguise is on'), findsNothing);
    expect(store.decoy, isNull);
    await _show(tester, find.text('Turn on disguise'));
    expect(find.text('Turn off disguise'), findsNothing);
  });

  testWidgets('iOS: honest about the name and no close button',
      (tester) async {
    final store = MemoryCredStore();
    final identity = FakeDecoyIdentity(renameLauncher: false);
    await tester.pumpWidget(_app(store, identity));
    await tester.pumpAndSettle();
    await _openScreen(tester);
    expect(
      find.textContaining('iOS does not let an app change its name'),
      findsOneWidget,
    );
    await _fill(tester, '2580', '2580');
    expect(find.widgetWithText(AlertDialog, 'Disguise is on'), findsOneWidget);
    expect(find.textContaining('iOS keeps the name MoaV Deploy'),
        findsOneWidget);
    expect(find.text('Close app'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(identity.closed, isFalse);
  });

  test('capabilities carry through the provider', () async {
    final c = ProviderContainer(overrides: [
      decoyIdentityProvider.overrideWithValue(
        FakeDecoyIdentity(renameLauncher: false, switchIcon: true),
      ),
    ]);
    addTearDown(c.dispose);
    final caps = await c.read(decoyIdentityProvider).capabilities();
    expect(caps.renameLauncher, isFalse);
    expect(caps.switchIcon, isTrue);
    expect(DecoyCapabilities.none.switchIcon, isFalse);
  });
}
