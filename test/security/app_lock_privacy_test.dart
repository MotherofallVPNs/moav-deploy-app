import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/memory_cred_store.dart';

/// Device feedback: on resume the previous screen was visible behind the
/// biometric prompt. The gate now covers the UI with the branded shield as
/// soon as the app leaves the foreground and reveals it only after unlock.

/// Each authenticate() call waits for the test to complete the gate.
class _GatedLock extends AppLockService {
  final gates = <Completer<bool>>[];

  @override
  Future<bool> canLock() async => true;

  @override
  Future<bool> authenticate({bool disguised = false}) {
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

Widget _app(_GatedLock lock) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
        onboardingStoreProvider.overrideWithValue(_Onboarded()),
        appLockServiceProvider.overrideWithValue(lock),
      ],
      child: const MoavDeployApp(),
    );

const _home = 'No servers yet';

void _expectCovered(WidgetTester tester) {
  expect(find.text(_home), findsNothing);
  expect(find.byType(PrivacyShield), findsOneWidget);
  expect(find.byType(MoavMark), findsOneWidget);
}

void _expectRevealed(WidgetTester tester) {
  expect(find.text(_home), findsOneWidget);
  expect(find.byType(PrivacyShield), findsNothing);
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState s) async {
  tester.binding.handleAppLifecycleStateChanged(s);
  await tester.pump();
}

void main() {
  testWidgets('content is hidden until the launch unlock succeeds',
      (tester) async {
    final lock = _GatedLock();
    await tester.pumpWidget(_app(lock));
    await tester.pump();
    await tester.pump();
    _expectCovered(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(lock.gates, hasLength(1));

    lock.gates.single.complete(true);
    await tester.pumpAndSettle();
    _expectRevealed(tester);
  });

  testWidgets('going inactive covers the UI at once; resuming reveals it',
      (tester) async {
    final lock = _GatedLock();
    await tester.pumpWidget(_app(lock));
    await tester.pump();
    await tester.pump();
    lock.gates.single.complete(true);
    await tester.pumpAndSettle();
    _expectRevealed(tester);

    // The task-switcher snapshot is taken here, before `paused` arrives.
    await _lifecycle(tester, AppLifecycleState.inactive);
    _expectCovered(tester);
    // Plain shield: no unlock button, no wipe, no re-auth prompt yet.
    expect(find.text('Unlock'), findsNothing);
    expect(find.text('Emergency wipe'), findsNothing);
    expect(lock.gates, hasLength(1));

    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    _expectRevealed(tester);
  });

  testWidgets('background then resume re-authenticates before revealing',
      (tester) async {
    final lock = _GatedLock();
    await tester.pumpWidget(_app(lock));
    await tester.pump();
    await tester.pump();
    lock.gates.single.complete(true);
    await tester.pumpAndSettle();
    _expectRevealed(tester);

    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.paused);
    _expectCovered(tester);

    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    // Resumed, but still locked: the shield stays and the prompt is up.
    _expectCovered(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(lock.gates, hasLength(2));

    lock.gates.last.complete(false);
    await tester.pumpAndSettle();
    _expectCovered(tester);
    expect(find.text('Unlock failed'), findsOneWidget);
    expect(find.text('Emergency wipe'), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(lock.gates, hasLength(3));
    lock.gates.last.complete(true);
    await tester.pumpAndSettle();
    _expectRevealed(tester);
  });
}
