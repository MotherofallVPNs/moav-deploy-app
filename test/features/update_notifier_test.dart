import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_box.dart';
import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// [UpdateNotifier]: re-attaching to a job the server is still running,
/// the check and start calls, polling to a terminal phase, and what the
/// activity entry says at each step. Timers are never waited on: `poll()`
/// is driven by hand and the `polling` flag is asserted instead.
class _Controller extends StubMoavController {
  /// Queue for [updateStatus]; the last entry repeats.
  final statuses = <InstallStatus?>[];
  int updateStatusCalls = 0;
  int startCalls = 0;
  int serverInfoCalls = 0;
  int statusCalls = 0;
  Object? checkError;
  Object? startError;
  Object? pollError;

  @override
  Future<InstallStatus?> updateStatus() async {
    updateStatusCalls++;
    final e = pollError;
    if (e != null) throw e;
    if (statuses.isEmpty) return null;
    return statuses.length == 1 ? statuses.first : statuses.removeAt(0);
  }

  @override
  Future<void> startUpdate() async {
    final e = startError;
    if (e != null) throw e;
    startCalls++;
  }

  @override
  Future<UpdateCheck> checkForUpdates() async {
    final e = checkError;
    if (e != null) throw e;
    return UpdateCheck(
      updateAvailable: true,
      checkedAt: DateTime(2026),
      currentVersion: '2.3.0',
      latestVersion: '2.3.1',
    );
  }

  @override
  Future<ServerInfo> serverInfo() async {
    serverInfoCalls++;
    return ServerInfo(
      host: const HostMetrics(cpuCount: 1),
      version: const VersionInfo(moavVersion: '2.3.1'),
      collectedAt: DateTime(2026),
    );
  }

  @override
  Future<ServiceStatusReport> status() async {
    statusCalls++;
    return ServiceStatusReport(collectedAt: DateTime(2026), services: const []);
  }
}

const _running = InstallStatus(
  phase: InstallPhase.running,
  progress: 1 / 3,
  logTail: ['[moav-deploy] step 1/3: Preflight', 'Host: box'],
  message: 'Preflight',
);
const _done = InstallStatus(
  phase: InstallPhase.succeeded,
  progress: 1,
  logTail: ['[moav-deploy] step 3/3: Report', '[moav-deploy] exit=0'],
  message: 'Install finished',
);
const _failed = InstallStatus(
  phase: InstallPhase.failed,
  logTail: ['moav update failed (exit 1)', '[moav-deploy] exit=1'],
  message: 'Install failed (exit 1)',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const id = 's1';
  late _Controller c;
  late ProviderContainer container;
  UpdateState state() => container.read(updateProvider(id));
  UpdateNotifier notifier() => container.read(updateProvider(id).notifier);
  /// The update job's entry; a success also starts refresh operations.
  Operation? current() => container
      .read(activityProvider)
      .operations
      .where((o) => o.label.startsWith('Update MoaV · '))
      .firstOrNull;

  /// Builds the container and lets the attach-on-build microtask run.
  Future<void> boot(List<InstallStatus?> statuses) async {
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
    container.listen(updateProvider(id), (_, _) {});
    await _settle();
  }

  test('nothing to attach to when the server has no update job', () async {
    await boot([null]);
    expect(c.updateStatusCalls, 1);
    expect(state().job, isNull);
    expect(state().polling, isFalse);
    expect(state().jobRunning, isFalse);
    expect(current(), isNull);
  });

  test('re-attaches to a running job and polls it to success', () async {
    await boot([_running, _done]);
    expect(state().job!.phase, InstallPhase.running);
    expect(state().jobRunning, isTrue);
    expect(state().polling, isTrue);
    final op = current()!;
    expect(op.label, startsWith('Update MoaV · '));
    expect(op.phase, OperationPhase.running);
    expect(op.lines, _running.logTail);

    await notifier().poll();
    expect(state().job!.phase, InstallPhase.succeeded);
    expect(state().jobRunning, isFalse);
    expect(state().polling, isFalse);
    expect(current()!.phase, OperationPhase.done);
    expect(current()!.lines, _done.logTail);
    // Success drops the stale check and re-reads version and status.
    expect(state().check, isNull);
    await _settle();
    expect(c.serverInfoCalls, 1);
    expect(c.statusCalls, 1);
  });

  test('a failed job fails the entry with its own message', () async {
    await boot([_running, _failed]);
    await notifier().poll();
    expect(state().job!.phase, InstallPhase.failed);
    expect(state().polling, isFalse);
    expect(current()!.phase, OperationPhase.failed);
    expect(current()!.error, 'Install failed (exit 1)');
    await _settle();
    expect(c.serverInfoCalls, 0);
  });

  test('a vanished log ends the job as unknown', () async {
    await boot([_running]);
    c.statuses.clear();
    await notifier().poll();
    expect(state().job!.phase, InstallPhase.unknown);
    expect(state().job!.message, 'No update log found on the server');
    expect(state().polling, isFalse);
    expect(current()!.phase, OperationPhase.failed);
    expect(current()!.error, 'No update log found on the server');
  });

  test('a poll error is shown but keeps the job and the polling', () async {
    await boot([_running]);
    c.pollError = TimeoutException('ssh dropped');
    await notifier().poll();
    expect(state().jobError!.kind, AppErrorKind.timeout);
    expect(state().job!.phase, InstallPhase.running);
    expect(state().polling, isTrue);
    expect(current()!.phase, OperationPhase.running);

    c.pollError = null;
    await notifier().poll();
    expect(state().jobError, isNull);
  });

  test('check: result lands, a second check waits, errors are kept apart',
      () async {
    await boot([null]);
    await notifier().check();
    expect(state().check!.latestVersion, '2.3.1');
    expect(state().checking, isFalse);
    expect(state().checkError, isNull);

    c.checkError = TimeoutException('github');
    await notifier().check();
    expect(state().checkError!.kind, AppErrorKind.timeout);
    expect(state().check!.latestVersion, '2.3.1', reason: 'last good check stays');
    expect(state().jobError, isNull);
  });

  test('start launches once, polls, and refuses a second start', () async {
    await boot([null, _running]);
    await notifier().start();
    expect(c.startCalls, 1);
    expect(state().starting, isFalse);
    expect(state().job!.phase, InstallPhase.running);
    expect(state().polling, isTrue);
    expect(current()!.label, startsWith('Update MoaV · '));
    expect(current()!.phase, OperationPhase.running);

    await notifier().start();
    expect(c.startCalls, 1);
  });

  test('a failed launch reports the cause and fails the entry', () async {
    await boot([null]);
    c.startError = SshCommandException('launch', failed('bash: setsid: not found'));
    await notifier().start();
    expect(c.startCalls, 0);
    expect(state().starting, isFalse);
    expect(state().job, isNull);
    expect(state().jobError!.kind, AppErrorKind.commandFailed);
    expect(state().jobError!.detail, contains('setsid'));
    expect(current()!.phase, OperationPhase.failed);
    expect(state().polling, isFalse);
  });

  test('dismiss forgets the job and detaches the entry', () async {
    await boot([_running]);
    notifier().dismiss();
    expect(state().job, isNull);
    expect(state().jobError, isNull);
    expect(state().polling, isFalse);
    expect(current()!.phase, OperationPhase.detached);
  });

  test('UpdateState flags and copyWith clears', () {
    const idle = UpdateState();
    expect(idle.jobRunning, isFalse);
    expect(const UpdateState(job: _running).jobRunning, isTrue);
    expect(const UpdateState(job: _done).jobRunning, isFalse);
    const unknown = InstallStatus(phase: InstallPhase.unknown);
    expect(const UpdateState(job: unknown).jobRunning, isFalse);
    const err = AppError(AppErrorKind.unknown, 'x');
    final s = const UpdateState(job: _running, jobError: err, checkError: err)
        .copyWith(clearJob: true, clearJobError: true, clearCheckError: true);
    expect(s.job, isNull);
    expect(s.jobError, isNull);
    expect(s.checkError, isNull);
  });
}
