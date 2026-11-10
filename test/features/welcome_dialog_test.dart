import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/features/welcome/welcome_dialog.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

/// First-launch welcome: shown once, "Don't show this again" persists and
/// suppresses it on the next launch.

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
    expect(box.value, isTrue, reason: 'first launch only by default');
  });

  testWidgets('Get started with the box ticked persists and suppresses next launch',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
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

  testWidgets('unticking the box keeps the welcome for the next launch',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome-dont-show')));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text(WelcomeDialog.title), findsNothing);
    expect(store.dismissed, isFalse);
    // Not again in this session, though.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(WelcomeDialog.title), findsNothing);
  });

  testWidgets('tapping outside dismisses and still honours the ticked box',
      (tester) async {
    final store = _FakeWelcomeStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
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
