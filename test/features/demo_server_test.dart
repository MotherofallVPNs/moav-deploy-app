import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/demo_moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/demo/demo_widgets.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// The demo server from the user's side: the hint on Add Server, the
/// empty-state button, the pre-filled emulated install, the hub with its
/// badge, and the reset when the demo is left.

Widget _app(MemoryCredStore store) => ProviderScope(
      retry: noProviderRetry,
      overrides: [secureCredStoreProvider.overrideWithValue(store)],
      child: const MoavDeployApp(lockEnabled: false),
    );

/// Runs the emulated install from the pre-filled form to "Go to the server".
Future<void> _runInstall(WidgetTester tester) async {
  await tester.tap(find.text('Start install'));
  await tester.pump();
  for (var i = 0; i < 26; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(find.text('Go to the server'), findsOneWidget);
  expect(find.text('100%'), findsOneWidget);
  expect(find.text('[moav-deploy] exit=0'), findsOneWidget);
}

void main() {
  testWidgets('Add Server shows the hint; the button replaces it with the demo',
      (tester) async {
    final store = MemoryCredStore()..profiles = [demoProfile];
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('demo-hint')), findsOneWidget);
    expect(find.text(demoHintTitle), findsOneWidget);
    expect(find.text(demoHintBody), findsOneWidget);
    expect(find.text(tryDemoLabel), findsOneWidget);
    // The hint is above the form, where a newcomer looks first.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('demo-hint'))).dy,
      lessThan(tester.getTopLeft(find.text('CONNECTION')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('try-demo')));
    await tester.pumpAndSettle();

    // The hub replaced the form and, finding no MoaV, opened the install
    // view; the entry is saved without any secret.
    expect(find.text('Save server'), findsNothing);
    expect(find.text('Deploy · Demo server'), findsOneWidget);
    expect(find.text('Set up the demo server'), findsOneWidget);
    expect(store.profiles.where((p) => p.isDemo).length, 1);
    expect(store.secrets, isEmpty);
    // The controller behind it is the demo, never SSH.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MoavDeployApp)),
    );
    expect(
      container.read(moavControllerProvider(ServerProfile.demoId)),
      isA<DemoMoavController>(),
    );
  });

  testWidgets('empty state offers the demo; it runs the install then manages',
      (tester) async {
    final store = MemoryCredStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('No servers yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('try-demo-empty')));
    await tester.pumpAndSettle();

    // The hub pinged, found no MoaV and opened the pre-filled install form.
    expect(find.text('Set up the demo server'), findsOneWidget);
    expect(find.text(DemoMoavController.installDomain), findsOneWidget);
    expect(find.text(DemoMoavController.installPassword), findsOneWidget);
    expect(find.byKey(const ValueKey('advanced-toggle')), findsNothing);
    expect(find.text('Start install'), findsOneWidget);

    await _runInstall(tester);
    expect(store.installHandles, isEmpty, reason: 'nothing persisted for the demo');

    await tester.tap(find.text('Go to the server'));
    await tester.pumpAndSettle();
    expect(find.text('Connected. MoaV 2.3.1 is installed.'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('emulated · no ssh, no network'), findsOneWidget);

    // Users: the stock list, add one, it shows up.
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('4 USERS'), findsOneWidget);
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'dave');
    await tester.pump();
    await tester.tap(find.text('Add'));
    // The emulated add takes under a second; let it land.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // The bundle screen opened for the new user with QR codes.
    expect(find.text('SCAN TO IMPORT'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('dave'), findsOneWidget);
    expect(find.text('5 USERS'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Leaving the hub resets the demo: back in, the install runs again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Demo server'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.text('emulated · no SSH, no network'), findsOneWidget);
    await tester.tap(find.text('Demo server'));
    await tester.pumpAndSettle();
    expect(find.text('Set up the demo server'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Demo server'), findsOneWidget);
  });

  testWidgets('demo card menu has no edit, users, Grafana or deploy entries',
      (tester) async {
    final store = MemoryCredStore()..profiles = [ServerProfile.demo];
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Edit server'), findsNothing);
    expect(find.text('Deploy MoaV'), findsNothing);
    expect(find.text('Grafana'), findsNothing);
  });
}
