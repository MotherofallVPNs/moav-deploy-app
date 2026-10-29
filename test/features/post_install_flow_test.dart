import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/deploy/deploy_screen.dart';
import 'package:moav_deploy/features/server/server_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// Onboarding flow: opening a server checks the connection and, when MoaV
/// is missing, lands on the install view; a finished install refreshes the
/// hub once and "Go to the server" returns to it.

const _running1 = InstallStatus(
  phase: InstallPhase.running,
  progress: 1 / 4,
  message: 'Preflight',
  step: 1,
  totalSteps: 4,
  logTail: ['[moav-deploy] step 1/4: Preflight'],
);

const _running3 = InstallStatus(
  phase: InstallPhase.running,
  progress: 3 / 4,
  message: 'Bootstrap MoaV',
  step: 3,
  totalSteps: 4,
  logTail: [
    '[moav-deploy] step 1/4: Preflight',
    '[moav-deploy] step 2/4: Run MoaV installer (non-interactive .env setup)',
    '[moav-deploy] step 3/4: Bootstrap MoaV',
  ],
);

const _done = InstallStatus(
  phase: InstallPhase.succeeded,
  progress: 1,
  message: 'Install finished',
  step: 4,
  totalSteps: 4,
  logTail: [
    '[moav-deploy] step 4/4: Start services',
    '[moav-deploy] exit=0',
  ],
);

class _Controller extends StubMoavController {
  _Controller({required this.installed});

  /// What [ping] reports; flipped by the test when the fake install ends.
  bool installed;
  int pingCalls = 0;

  /// Holds [ping] open until completed, to look at the checking state.
  Completer<void>? pingGate;
  InstallStatus current = _running1;
  InstallSpec? installedSpec;

  @override
  Future<ConnectionCheck> ping() async {
    pingCalls++;
    await (pingGate?.future ?? Future<void>.value());
    return ConnectionCheck(
      reachable: true,
      moavInstalled: installed,
      moavVersion: installed ? '2.3.1' : null,
    );
  }

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    installedSpec = spec;
    return const InstallHandle(jobId: '7', logPath: '.moav-deploy/deploy.log');
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async => current;
}

Widget _app(MemoryCredStore store, _Controller c) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        moavControllerFactoryProvider.overrideWithValue(FakeControllerFactory(c)),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

Future<_Controller> _open(WidgetTester tester, {required bool installed}) async {
  final c = _Controller(installed: installed);
  await tester.pumpWidget(_app(MemoryCredStore()..profiles = [demoProfile], c));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Demo'));
  await tester.pumpAndSettle();
  return c;
}

/// Starts the install from the form and lets the first poll land.
Future<void> _startInstall(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'Admin dashboard password'), 'secret-but-long');
  await tester.pump();
  await tester.tap(find.text('Start install'));
  await tester.pump();
  await tester.pump();
}

String _percent(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining(RegExp(r'^\d+%$')))
    .map((t) => t.data!)
    .single;

void main() {
  testWidgets('a server without MoaV: check shown, then the install view opens',
      (tester) async {
    final c = _Controller(installed: false)..pingGate = Completer<void>();
    await tester.pumpWidget(_app(MemoryCredStore()..profiles = [demoProfile], c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    // The spinner never settles while the check is held open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.byType(DeployScreen), findsNothing);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(c.pingCalls, 1);
    c.pingGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(DeployScreen), findsOneWidget);
    expect(find.text('Deploy · Demo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Domain'), findsOneWidget);
    // The hub underneath keeps the result and an inline install button.
    expect(find.text('Connected. MoaV is not installed yet.', skipOffstage: false),
        findsOneWidget);
    expect(find.text('Install MoaV', skipOffstage: false), findsOneWidget);

    // Backing out returns to the hub; the auto-open does not fire again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DeployScreen), findsNothing);
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.text('Install MoaV'), findsOneWidget);
    await tester.tap(find.text('Install MoaV'));
    await tester.pumpAndSettle();
    expect(find.byType(DeployScreen), findsOneWidget);
  });

  testWidgets('an installed server opens the hub and stays there', (tester) async {
    final c = await _open(tester, installed: true);
    await tester.pumpAndSettle();
    expect(c.pingCalls, 1);
    expect(find.byType(DeployScreen), findsNothing);
    expect(find.text('Connected. MoaV 2.3.1 is installed.'), findsOneWidget);
    expect(find.text('Install MoaV'), findsNothing);
    expect(find.text('Users'), findsOneWidget);
  });

  testWidgets('progress eases through bootstrap, waits quietly, hits 100% at exit',
      (tester) async {
    final c = await _open(tester, installed: false);
    await tester.pumpAndSettle();
    await _startInstall(tester);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('Preflight'), findsOneWidget);
    expect(_percent(tester), '0%');

    c.current = _running3;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final atStart = int.parse(_percent(tester).replaceAll('%', ''));
    expect(atStart, inInclusiveRange(20, 25));
    expect(find.textContaining('longest step'), findsOneWidget);
    expect(find.text('Waiting for the server…'), findsNothing);

    // Same log for a while: the bar keeps creeping and the quiet notice shows.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    final later = int.parse(_percent(tester).replaceAll('%', ''));
    expect(later, greaterThan(atStart));
    expect(find.text('Waiting for the server…'), findsOneWidget);

    await tester.pump(const Duration(minutes: 7));
    await tester.pump();
    final muchLater = int.parse(_percent(tester).replaceAll('%', ''));
    expect(muchLater, greaterThan(later));
    expect(muchLater, lessThan(92));
    expect(find.text('DONE'), findsNothing);

    c.current = _done;
    c.installed = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('DONE'), findsOneWidget);
    expect(_percent(tester), '100%');
    expect(find.text('Go to the server'), findsOneWidget);
    expect(find.text('Waiting for the server…'), findsNothing);
  });

  testWidgets('after the install the hub is refreshed once and shows it installed',
      (tester) async {
    final c = await _open(tester, installed: false);
    await tester.pumpAndSettle();
    expect(c.pingCalls, 1);
    await _startInstall(tester);

    c.current = _done;
    c.installed = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Go to the server'), findsOneWidget);
    expect(c.pingCalls, 2);

    await tester.tap(find.text('Go to the server'));
    await tester.pumpAndSettle();
    expect(find.byType(DeployScreen), findsNothing);
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.text('Connected. MoaV 2.3.1 is installed.'), findsOneWidget);
    expect(find.text('Connected. MoaV is not installed yet.'), findsNothing);
    expect(find.text('Install MoaV'), findsNothing);
    // No further polling once the hub is back.
    await tester.pump(const Duration(seconds: 10));
    expect(c.pingCalls, 2);
  });

  testWidgets('from the home card menu, "Go to the server" opens the hub',
      (tester) async {
    final c = _Controller(installed: false);
    await tester.pumpWidget(_app(MemoryCredStore()..profiles = [demoProfile], c));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deploy MoaV'));
    await tester.pumpAndSettle();
    expect(find.byType(DeployScreen), findsOneWidget);
    expect(find.byType(ServerScreen), findsNothing);
    expect(c.pingCalls, 0);

    await _startInstall(tester);
    c.current = _done;
    c.installed = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to the server'));
    await tester.pumpAndSettle();

    expect(find.byType(DeployScreen), findsNothing);
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.text('Connected. MoaV 2.3.1 is installed.'), findsOneWidget);
    expect(c.pingCalls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Demo'), findsOneWidget);
    expect(find.byType(ServerScreen), findsNothing);
  });
}
