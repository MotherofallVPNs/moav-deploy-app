import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/operate/apply_view.dart';
import 'package:moav_deploy/features/operate/operate_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';

/// The rebuild job on screen: launched from the Services tab (all services
/// and one service, with the force option), offered on the Server tab after
/// an update that was not applied, and read again when the app comes back
/// to the foreground.
class _Controller extends StubMoavController {
  /// What the server's job files say right now.
  ApplyStatus apply = const ApplyStatus();
  int applyStatusCalls = 0;
  final started = <ApplySpec>[];
  int ackCalls = 0;
  final serviceLog = <String>[];
  final updateStarts = <bool>[];

  @override
  Future<ApplyStatus> applyStatus() async {
    applyStatusCalls++;
    return apply;
  }

  @override
  Future<void> startApply(ApplySpec spec) async {
    started.add(spec);
    apply = ApplyStatus(
      job: const InstallStatus(
        phase: InstallPhase.running,
        logTail: ['[moav-deploy] step 2/4: Build images', '#3 building'],
        message: 'Build images',
        step: 2,
        totalSteps: 4,
      ),
      jobId: 'job-${started.length}',
      spec: spec,
    );
  }

  @override
  Future<void> acknowledgeApply() async => ackCalls++;

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async =>
      serviceLog.add('${action.kind.name} ${action.service}');

  @override
  Future<ServiceStatusReport> status() async => ServiceStatusReport(
        collectedAt: DateTime(2026),
        version: '2.4.0',
        defaultProfiles: const ['proxy', 'admin'],
        services: const [
          ServiceStatus(name: 'sing-box', state: ServiceState.running, uptime: '7 days'),
          ServiceStatus(name: 'admin', state: ServiceState.running, uptime: '7 days'),
        ],
      );

  @override
  Future<ServiceFlags> serviceFlags() async =>
      ServiceFlags(values: const {}, collectedAt: DateTime(2026));

  @override
  Future<ServerInfo> serverInfo() async => ServerInfo(
        host: const HostMetrics(cpuCount: 2, load1: 0.2),
        version: const VersionInfo(moavVersion: '2.4.0'),
        collectedAt: DateTime(2026),
      );

  @override
  Future<InstallStatus?> updateStatus() async => null;

  @override
  Future<void> startUpdate({bool applyAfter = true}) async =>
      updateStarts.add(applyAfter);

  @override
  Future<UpdateCheck> checkForUpdates() async => UpdateCheck(
        updateAvailable: true,
        checkedAt: DateTime(2026),
        currentVersion: '2.4.0',
        latestVersion: '2.5.0',
        message: 'Update available: v2.5.0',
      );
}

Future<_Controller> _pump(
  WidgetTester tester, {
  ApplyStatus apply = const ApplyStatus(),
  OperateTab tab = OperateTab.services,
}) async {
  final c = _Controller()..apply = apply;
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [moavControllerProvider(demoProfile.id).overrideWithValue(c)],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: OperateScreen(profile: demoProfile, initialTab: tab),
    ),
  ));
  // Bounded: a running job animates its progress bar forever.
  await _pumpFor(tester);
  return c;
}

/// Bounded pumps: a running job animates its progress bar forever.
Future<void> _pumpFor(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the tab's own list: the first vertical scrollable (the tab bar
/// and the pager are horizontal, the log box comes later in the tree).
Future<void> _scrollTo(WidgetTester tester, Finder finder, {double delta = 120}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first,
  );
  await tester.pump();
}

const _finishedFailed = ApplyStatus(
  job: InstallStatus(
    phase: InstallPhase.failed,
    logTail: ['build error', '[moav-deploy] exit=17'],
    message: 'Rebuild failed (exit 17)',
    step: 2,
    totalSteps: 4,
  ),
  jobId: 'old-1',
  spec: ApplySpec.afterUpdate,
  exitCode: 17,
  updatePending: true,
);

void main() {
  testWidgets('Services: rebuild everything, forced, as a detached job',
      (tester) async {
    final c = await _pump(tester);
    expect(find.byType(ApplyJobCard), findsNothing);

    await tester.tap(find.text('Rebuild & restart'));
    await tester.pumpAndSettle();
    expect(find.text('Rebuild and restart all services?'), findsOneWidget);
    expect(find.text('Regenerate user bundles'), findsOneWidget);
    await tester.tap(find.text('Force rebuild'));
    await tester.pump();
    await tester.tap(find.text('Rebuild'));
    await _pumpFor(tester);

    final spec = c.started.single;
    expect(spec.allServices, isTrue);
    expect(spec.noCache, isTrue);
    expect(spec.regenerateUsers, isFalse);

    // The job is on screen with its step, log tail and the reassurance.
    expect(find.byType(ApplyJobCard), findsOneWidget);
    expect(find.text('Rebuild all services (no cache)'), findsOneWidget);
    expect(find.text('Step 2 of 4: Build images'), findsOneWidget);
    expect(find.textContaining('Safe to leave the app'), findsOneWidget);
    expect(find.textContaining('#3 building'), findsOneWidget);
    // One thing at a time: the quick actions wait for the job.
    await _scrollTo(tester, find.text('Start all'));
    final startAll = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Start all'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(startAll.onPressed, isNull);
    expect(c.serviceLog, isEmpty);
  });

  testWidgets('Services: rebuild one service from its row menu',
      (tester) async {
    final c = await _pump(tester);
    final menu = find.byTooltip('Actions for sing-box');
    await _scrollTo(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rebuild and restart…'));
    await tester.pumpAndSettle();
    expect(find.text('Rebuild and restart sing-box?'), findsOneWidget);
    // Users are regenerated for the whole box, not for one service.
    expect(find.text('Regenerate user bundles'), findsNothing);
    await tester.tap(find.text('Rebuild'));
    await _pumpFor(tester);

    final spec = c.started.single;
    expect(spec.services, ['sing-box']);
    expect(spec.noCache, isFalse);
    expect(c.serviceLog, isEmpty, reason: 'a build is never run on the SSH channel');
  });

  testWidgets('Services: cancelling the dialog starts nothing', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Rebuild & restart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.started, isEmpty);
  });

  testWidgets('coming back to the app reads the job again and shows the result',
      (tester) async {
    final c = await _pump(
      tester,
      apply: const ApplyStatus(
        job: InstallStatus(
          phase: InstallPhase.running,
          logTail: ['[moav-deploy] step 2/4: Build images'],
          message: 'Build images',
          step: 2,
          totalSteps: 4,
        ),
        jobId: 'j1',
        spec: ApplySpec.afterUpdate,
      ),
    );
    await _pumpFor(tester);
    expect(find.text('RUNNING'), findsOneWidget);

    // Locked phone: the job ends on the server meanwhile.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    c.apply = const ApplyStatus(
      job: InstallStatus(
        phase: InstallPhase.succeeded,
        logTail: ['Applied: services are running on the rebuilt images.', '[moav-deploy] exit=0'],
        message: 'Rebuild finished',
        progress: 1,
      ),
      jobId: 'j1',
      spec: ApplySpec.afterUpdate,
      exitCode: 0,
    );
    final before = c.applyStatusCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(c.applyStatusCalls, greaterThan(before));
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Rebuild finished'), findsOneWidget);
    expect(find.text('Exit code 0'), findsOneWidget);
    expect(find.textContaining('Safe to leave the app'), findsNothing);

    await _scrollTo(tester, find.text('Dismiss'));
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(c.ackCalls, 1);
    expect(find.byType(ApplyJobCard), findsNothing);
  });

  testWidgets('Server: a failed apply found on launch, then Apply now',
      (tester) async {
    final c = await _pump(tester, apply: _finishedFailed, tab: OperateTab.server);
    // The result of the job that ended while the app was away.
    await _scrollTo(tester, find.text('Rebuild failed (exit 17)'));
    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('Exit code 17'), findsOneWidget);
    // And, above it, the one prominent way forward.
    await _scrollTo(tester, find.text('Update not applied yet'), delta: -120);
    await _scrollTo(tester, find.text(ApplyPendingCard.applyLabel));
    await tester.tap(find.text(ApplyPendingCard.applyLabel));
    await _pumpFor(tester);

    final spec = c.started.single;
    expect(spec.allServices, isTrue);
    expect(spec.regenerateUsers, isTrue);
    expect(spec.noCache, isFalse);
    // Being applied now: the offer is gone, the running job is shown.
    expect(find.text('Update not applied yet'), findsNothing);
    expect(find.text('RUNNING'), findsOneWidget);
  });

  testWidgets('Server: nothing pending, nothing offered', (tester) async {
    await _pump(tester, tab: OperateTab.server);
    expect(find.text('Update not applied yet'), findsNothing);
    expect(find.byType(ApplyJobCard), findsNothing);
  });

  testWidgets('Server: Update applies by default and can be told not to',
      (tester) async {
    final c = await _pump(tester, tab: OperateTab.server);
    await _scrollTo(tester, find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update to v2.5.0'));
    await tester.pumpAndSettle();
    expect(find.text('Update and apply'), findsOneWidget);
    await tester.tap(find.text('Apply when done'));
    await tester.pump();
    expect(find.text('Update and apply'), findsNothing);
    await tester.tap(find.text('Update only'));
    await _pumpFor(tester);
    expect(c.updateStarts, [false]);
  });
}
