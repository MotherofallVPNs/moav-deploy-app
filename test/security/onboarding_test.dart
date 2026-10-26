import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

class _FakeOnboardingStore implements OnboardingStore {
  _FakeOnboardingStore(this.done);
  bool done;
  @override
  Future<bool> isComplete() async => done;
  @override
  Future<void> markComplete() async => done = true;
}

Widget _app(_FakeOnboardingStore store) => ProviderScope(
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: moavDarkTheme(),
        home: const FirstRunGate(child: Text('home')),
      ),
    );

void main() {
  testWidgets('first run shows onboarding, CTA persists and continues',
      (tester) async {
    final store = _FakeOnboardingStore(false);
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('Turn on app lock'), findsOneWidget);
    expect(find.text('home'), findsNothing);

    await tester.ensureVisible(find.text('Turn on app lock'));
    await tester.tap(find.text('Turn on app lock'));
    await tester.pumpAndSettle();
    expect(store.done, isTrue);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('onboarding is skipped once complete', (tester) async {
    await tester.pumpWidget(_app(_FakeOnboardingStore(true)));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Turn on app lock'), findsNothing);
  });
}
