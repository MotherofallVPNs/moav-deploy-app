import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/features/users/users_provider.dart';

import '../support/fake_box.dart';
import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// [ServiceActionsNotifier]: one action at a time per server, output
/// streamed into the activity panel, and the right caches refreshed after.
class _Controller extends StubMoavController {
  int statusCalls = 0;
  int flagsCalls = 0;
  int usersCalls = 0;
  final log = <String>[];

  /// Holds [service] open until completed by the test.
  Completer<void>? gate;

  /// Thrown by the next [service] call, then cleared.
  Object? nextError;

  @override
  Future<ServiceStatusReport> status() async {
    statusCalls++;
    return ServiceStatusReport(
      collectedAt: DateTime(2026),
      services: const [ServiceStatus(name: 'wireguard', state: ServiceState.running)],
    );
  }

  @override
  Future<ServiceFlags> serviceFlags() async {
    flagsCalls++;
    return ServiceFlags(values: const {}, collectedAt: DateTime(2026));
  }

  @override
  Future<List<MoavUser>> listUsers() async {
    usersCalls++;
    return const [];
  }

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    onOutput?.call('${action.kind.name} ${action.service ?? 'all'}: ok\n');
    await (gate?.future ?? Future<void>.value());
    log.add('${action.kind.name} ${action.service}');
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const id = 's1';
  late _Controller c;
  late ProviderContainer container;
  late ServiceActionsNotifier n;
  ServiceActionState state() => container.read(serviceActionsProvider(id));
  /// The action's own entry; the status re-read that follows is a separate,
  /// possibly still running, operation.
  Operation entry(String prefix) => container
      .read(activityProvider)
      .operations
      .firstWhere((o) => o.label.startsWith(prefix));

  setUp(() {
    c = _Controller();
    container = ProviderContainer(
      retry: noProviderRetry,
      overrides: [
        moavControllerProvider(id).overrideWithValue(c),
        secureCredStoreProvider.overrideWithValue(
            MemoryCredStore()..profiles = [demoProfile]),
      ],
    );
    addTearDown(container.dispose);
    container.listen(serviceActionsProvider(id), (_, _) {});
    n = container.read(serviceActionsProvider(id).notifier);
  });

  test('start: issues the action, streams to the panel, re-reads status only',
      () async {
    await n.run(const ServiceAction(ServiceActionKind.start, service: 'wireguard'));
    expect(c.log, ['start wireguard']);
    expect(state().busy, isFalse);
    expect(state().message, 'Start wireguard done');
    expect(state().error, isNull);
    await _settle();
    expect(c.statusCalls, 1);
    expect(c.flagsCalls, 0);
    final op = entry('Start wireguard · ');
    expect(op.phase, OperationPhase.done);
    expect(op.lines, ['start wireguard: ok']);
  });

  test('a second action while one runs is dropped', () async {
    c.gate = Completer<void>();
    final first = n.run(const ServiceAction(ServiceActionKind.stop, service: 'sing-box'));
    await _settle();
    expect(state().busy, isTrue);
    expect(state().isRunningFor('sing-box'), isTrue);
    expect(state().isRunningFor('wireguard'), isFalse);

    await n.run(ServiceAction.restart);
    expect(c.log, isEmpty, reason: 'the restart never reached the controller');

    c.gate!.complete();
    await first;
    expect(c.log, ['stop sing-box']);
    expect(state().message, 'Stop sing-box done');
  });

  test('enable and disable also refresh the .env flags', () async {
    await n.run(const ServiceAction(ServiceActionKind.enable, service: 'wireguard'));
    await _settle();
    expect(c.flagsCalls, 1);
    expect(c.statusCalls, 1);
    await n.run(const ServiceAction(ServiceActionKind.disable, service: 'wireguard'));
    await _settle();
    expect(c.flagsCalls, 2);
    expect(c.statusCalls, 2);
    expect(c.log, ['enable wireguard', 'disable wireguard']);
  });

  test('regenerate users invalidates the users list', () async {
    container.listen(usersProvider(id), (_, _) {});
    await _settle();
    expect(c.usersCalls, 1);
    await n.run(ServiceAction.regenerateUsers);
    await _settle();
    expect(c.usersCalls, 2);
    expect(c.flagsCalls, 0);
    expect(state().message, 'Regenerate users done');
  });

  test('a failed command: scrubbed detail, failed entry, status still re-read',
      () async {
    c.nextError = SshCommandException(
      'moav start nope',
      failed('✗ unknown service: nope\nADMIN_PASSWORD=hunter2\n'),
    );
    await n.run(const ServiceAction(ServiceActionKind.start, service: 'nope'));
    final error = state().error!;
    expect(error.kind, AppErrorKind.commandFailed);
    expect(error.detail, contains('unknown service: nope'));
    expect(error.detail, isNot(contains('hunter2')));
    expect(state().message, isNull);
    expect(state().busy, isFalse);
    final op = entry('Start nope · ');
    expect(op.phase, OperationPhase.failed);
    expect(op.error, startsWith('The command failed on the server (exit 1).'));
    await _settle();
    expect(c.statusCalls, 1);
  });

  test('describe names the verb and the target', () {
    expect(ServiceActionsNotifier.describe(ServiceAction.start), 'Start all services');
    expect(
      ServiceActionsNotifier.describe(
          const ServiceAction(ServiceActionKind.stop, service: 'xray')),
      'Stop xray',
    );
    expect(ServiceActionsNotifier.describe(ServiceAction.regenerateUsers),
        'Regenerate users');
    expect(
      ServiceActionsNotifier.describe(
          const ServiceAction(ServiceActionKind.enable, service: 'telemt')),
      'Enable telemt',
    );
  });
}
