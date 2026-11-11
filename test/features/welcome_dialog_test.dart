import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/features/welcome/welcome_dialog.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

/// The welcome dialog: shown on every launch until "Don't show this again"
/// is ticked; closing it any other way brings it back next time.

class _FakeWelcomeStore implements WelcomeStore {
  _FakeWelcomeStore(this.dismissed);
  bool dismissed;
  @override
  Future<bool> isDismissed() async => dismissed;
  @override
  Future<void> markDismissed() async => dismissed = true;
}

Widget _app(_FakeWelcomeStore store) => ProviderScope(
      overrides: [welcomeStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: moavDarkTheme(),
        home: const WelcomeGate(requireUnlock: false, child: Text('home')),
      ),
    );

void main() {
  testWidgets('first launch shows the welcome over the home screen',
      (tester) async {
    await tester.pumpWidget(_app(_FakeWelcomeStore(false)));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text(WelcomeDialog.title), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text("Don't show this again"), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('welcome-dont-show')),
    );
    expect(box.value, isFalse, reason: 'shown every launch by default');
  });

  testWidgets('Get started without the box: back on the next launch',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(store.dismissed, isFalse);
    // Not again in this session, though.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(WelcomeDialog.title), findsNothing);

    // Next launch: the welcome is back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Get started with the box ticked persists and suppresses next launch',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-dont-show')));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(store.dismissed, isTrue);

    // Next launch: nothing.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('tapping outside without the box does not persist', (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(store.dismissed, isFalse);
  });

  testWidgets('tapping outside with the box ticked still persists',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-dont-show')));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(store.dismissed, isTrue);
  });

  testWidgets('already dismissed: no dialog', (tester) async {
    await tester.pumpWidget(_app(_FakeWelcomeStore(true)));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
  });
}
