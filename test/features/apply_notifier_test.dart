import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// [ApplyNotifier]: the job lives on the server, so everything here is
/// "what does the next read of its files say". Covers the launch, the
/// re-attach after the app was away (running, finished unseen, finished and
/// dismissed), a dropped connection mid-job, and the dismiss round trip.
/// Timers are never waited on: `poll()` is driven by hand.
class _Controller extends StubMoavController {
  /// Queue for [applyStatus]; the last entry repeats.
  final statuses = <ApplyStatus>[];
  int applyStatusCalls = 0;
  final started = <ApplySpec>[];
  int ackCalls = 0;
  int statusCalls = 0;
  int serverInfoCalls = 0;
  Object? startError;
  Object? pollError;
  Object? ackError;

  @override
  Future<ApplyStatus> applyStatus() async {
    applyStatusCalls++;
    final e = pollError;
    if (e != null) throw e;
    if (statuses.isEmpty) return const ApplyStatus();
    return statuses.length == 1 ? statuses.first : statuses.removeAt(0);
  }

  @override
  Future<void> startApply(ApplySpec spec) async {
    final e = startError;
    if (e != null) throw e;
    started.add(spec);
  }

  @override
  Future<void> acknowledgeApply() async {
    ackCalls++;
    final e = ackError;
    if (e != null) throw e;
  }

  @override
  Future<ServiceStatusReport> status() async {
    statusCalls++;
    return ServiceStatusReport(collectedAt: DateTime(2026), services: const []);
  }

  @override
  Future<ServerInfo> serverInfo() async {
    serverInfoCalls++;
    return ServerInfo(
      host: const HostMetrics(cpuCount: 1),
      version: const VersionInfo(moavVersion: '2.4.0'),
      collectedAt: DateTime(2026),
    );
  }
}

const _spec = ApplySpec(services: ['sing-box'], noCache: true);

const _running = ApplyStatus(
  job: InstallStatus(
    phase: InstallPhase.running,
    logTail: ['[moav-deploy] step 2/4: Build images', '#7 building'],
    message: 'Build images',
    step: 2,
    totalSteps: 4,
  ),
  jobId: '100-1',
  spec: _spec,
);
const _done = ApplyStatus(
  job: InstallStatus(
    phase: InstallPhase.succeeded,
    progress: 1,
    logTail: ['Applied.', '[moav-deploy] exit=0'],
    message: 'Rebuild finished',
  ),
  jobId: '100-1',
  spec: _spec,
  exitCode: 0,
);
const _failed = ApplyStatus(
  job: InstallStatus(
    phase: InstallPhase.failed,
    logTail: ['build error', '[moav-deploy] exit=17'],
    message: 'Rebuild failed (exit 17)',
  ),
  jobId: '100-1',
  spec: _spec,
  exitCode: 17,
);
const _doneAcked = ApplyStatus(
  job: InstallStatus(phase: InstallPhase.succeeded, message: 'Rebuild finished'),
  jobId: '100-1',
  spec: _spec,
  exitCode: 0,
  acknowledged: true,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const id = 's1';
  late _Controller c;
  late ProviderContainer container;
  ApplyState state() => container.read(applyProvider(id));
  ApplyNotifier notifier() => container.read(applyProvider(id).notifier);
  Operation? current() => container
      .read(activityProvider)
      .operations
      .where((o) => o.label.startsWith('Rebuild'))
      .firstOrNull;

  /// Builds the container and lets the attach-on-build microtask run.
  Future<void> boot(List<ApplyStatus> statuses) async {
    c = _Controller()..statuses.addAll(statuses);
    container = ProviderContainer(
      retry: noProviderRetry,
      overrides: [
        moavControllerProvider(id).overrideWithValue(c),
        secureCredStoreProvider.overrideWithValue(
            MemoryCredStore()..profiles = [demoProfile]),
      ],
    );
    addTearDown(container.dispose);
    container.listen(applyProvider(id), (_, _) {});
    await _settle();
  }

  test('no job on the server: nothing shown, nothing polled', () async {
    await boot([const ApplyStatus()]);
    expect(c.applyStatusCalls, 1);
    expect(state().job, isNull);
    expect(state().busy, isFalse);
    expect(state().polling, isFalse);
    expect(state().updatePending, isFalse);
    expect(current(), isNull);
  });

  test('re-attaches to a job that kept running while the app was away',
      () async {
    await boot([_running, _done]);
    expect(state().running, isTrue);
    expect(state().polling, isTrue);
    expect(state().job!.step, 2);
    expect(state().spec!.label, 'Rebuild sing-box (no cache)');
    final op = current()!;
    expect(op.label, startsWith('Rebuild sing-box (no cache) · '));
    expect(op.phase, OperationPhase.running);
    expect(op.lines, _running.job!.logTail);

    await notifier().poll();
    expect(state().running, isFalse);
    expect(state().polling, isFalse);
    expect(state().job!.phase, InstallPhase.succeeded);
    expect(state().status!.exitCode, 0);
    expect(current()!.phase, OperationPhase.done);
    await _settle();
    expect(c.statusCalls, 1, reason: 'containers were recreated');
    expect(c.serverInfoCalls, 1);
  });

  test('a job that finished while the app was closed shows its result',
      () async {
    await boot([_failed]);
    expect(state().running, isFalse);
    expect(state().polling, isFalse);
    expect(state().job!.phase, InstallPhase.failed);
    expect(state().job!.message, 'Rebuild failed (exit 17)');
    expect(state().status!.exitCode, 17);
    // Nothing was being watched, so no activity entry is invented for it.
    expect(current(), isNull);
  });

  test('a result already dismissed (on any device) stays hidden', () async {
    await boot([_doneAcked]);
    expect(state().job, isNull);
    expect(state().busy, isFalse);
  });

  test('a failed job fails the entry and still re-reads the services',
      () async {
    await boot([_running, _failed]);
    await notifier().poll();
    expect(state().job!.phase, InstallPhase.failed);
    expect(current()!.phase, OperationPhase.failed);
    expect(current()!.error, 'Rebuild failed (exit 17)');
    await _settle();
    expect(c.statusCalls, 1);
    expect(c.serverInfoCalls, 0);
  });

  test('a dropped connection keeps the job on screen and the polling on',
      () async {
    await boot([_running, _done]);
    c.pollError = TimeoutException('ssh dropped while the phone was locked');
    await notifier().poll();
    expect(state().error!.kind, AppErrorKind.timeout);
    expect(state().running, isTrue);
    expect(state().polling, isTrue);
    expect(current()!.phase, OperationPhase.running);

    // Back in the foreground: the next read finds the finished job.
    c.pollError = null;
    await notifier().poll();
    expect(state().error, isNull);
    expect(state().job!.phase, InstallPhase.succeeded);
    expect(state().polling, isFalse);
  });

  test('a failed read with no job on screen stays silent', () async {
    await boot([const ApplyStatus()]);
    c.pollError = TimeoutException('offline');
    await notifier().poll();
    expect(state().error, isNull);
    expect(state().job, isNull);
  });

  test('start launches once, follows the job, refuses a second start',
      () async {
    await boot([const ApplyStatus(), _running]);
    await notifier().start(_spec);
    expect(c.started, [_spec]);
    expect(state().starting, isFalse);
    expect(state().running, isTrue);
    expect(state().polling, isTrue);
    expect(current()!.phase, OperationPhase.running);

    await notifier().start(const ApplySpec());
    expect(c.started, hasLength(1));
  });

  test('a failed launch reports the cause and fails the entry', () async {
    await boot([const ApplyStatus()]);
    c.startError = StateError('An update is still running on the server.');
    await notifier().start(_spec);
    expect(c.started, isEmpty);
    expect(state().starting, isFalse);
    expect(state().job, isNull);
    expect(state().error, isNotNull);
    expect(current()!.phase, OperationPhase.failed);
    expect(state().polling, isFalse);
  });

  test('dismiss hides the result and acknowledges it on the server',
      () async {
    await boot([_done]);
    expect(state().job, isNotNull);
    await notifier().dismiss();
    expect(c.ackCalls, 1);
    expect(state().job, isNull);
    // The next read still says "not acknowledged" if the ack was lost.
    await notifier().poll();
    expect(state().job, isNull);
  });

  test('dismiss still hides it here when the server cannot be told',
      () async {
    await boot([_failed]);
    c.ackError = TimeoutException('offline');
    await notifier().dismiss();
    expect(state().job, isNull);
    expect(state().error, isNull);
  });

  test('a new job is shown again after an older one was dismissed', () async {
    await boot([_done]);
    await notifier().dismiss();
    c.statuses
      ..clear()
      ..add(const ApplyStatus(
        job: InstallStatus(phase: InstallPhase.failed, message: 'Rebuild failed (exit 1)'),
        jobId: '200-9',
        exitCode: 1,
      ));
    await notifier().poll();
    expect(state().job!.message, 'Rebuild failed (exit 1)');
  });

  test('dismiss does nothing while the job is running', () async {
    await boot([_running]);
    await notifier().dismiss();
    expect(c.ackCalls, 0);
    expect(state().job, isNotNull);
  });

  test('a pulled update is pending until something is applying it', () async {
    await boot([const ApplyStatus(updatePending: true)]);
    expect(state().updatePending, isTrue);
    expect(state().job, isNull);

    c.statuses
      ..clear()
      ..add(const ApplyStatus(
        job: InstallStatus(phase: InstallPhase.running, message: 'Build images'),
        jobId: '300-1',
        spec: ApplySpec.afterUpdate,
        updatePending: true,
      ));
    await notifier().start(ApplySpec.afterUpdate);
    expect(state().running, isTrue);
    expect(state().updatePending, isFalse);
  });
}
