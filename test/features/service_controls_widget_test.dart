import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/features/operate/operate_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';

/// Answers `status` and `serviceFlags` from fields, records `service` calls.
class _Controller extends StubMoavController {
  final log = <String>[];
  int statusCalls = 0;
  int flagsCalls = 0;
  Map<String, String> flags = const {};

  /// Thrown by every [serviceFlags] call when set.
  Object? flagsError;

  /// Thrown by the next [service] call, then cleared.
  Object? nextServiceError;

  @override
  Future<ServiceStatusReport> status() async {
    statusCalls++;
    return ServiceStatusReport(
      collectedAt: DateTime(2026),
      version: '2.3.1',
      defaultProfiles: const ['proxy', 'wireguard', 'admin'],
      services: const [
        ServiceStatus(name: 'sing-box', state: ServiceState.running, uptime: '7 days'),
        ServiceStatus(name: 'wireguard', state: ServiceState.stopped),
        ServiceStatus(name: 'telemt', state: ServiceState.never),
        ServiceStatus(name: 'certbot', state: ServiceState.exited),
      ],
    );
  }

  @override
  Future<ServiceFlags> serviceFlags() async {
    flagsCalls++;
    final e = flagsError;
    if (e != null) throw e;
    return ServiceFlags(values: flags, collectedAt: DateTime(2026));
  }

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    final e = nextServiceError;
    if (e != null) {
      nextServiceError = null;
      throw e;
    }
    log.add('${action.kind.name} ${action.service}');
  }
}

Future<_Controller> _pump(WidgetTester tester, {Map<String, String> flags = const {}}) async {
  final c = _Controller()..flags = flags;
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [moavControllerProvider(demoProfile.id).overrideWithValue(c)],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: const OperateScreen(profile: demoProfile),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openMenu(WidgetTester tester, String service) async {
  final button = find.byTooltip('Actions for $service');
  await tester.scrollUntilVisible(button, 120, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('start runs at once, then status is re-read', (tester) async {
    final c = await _pump(tester);
    expect(c.statusCalls, 1);
    expect(find.text('wireguard'), findsOneWidget);

    await _openMenu(tester, 'wireguard');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(c.log, ['start wireguard']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(c.statusCalls, 2);
    expect(find.text('Start wireguard done'), findsOneWidget);
  });

  testWidgets('stop and restart are gated by a confirm dialog', (tester) async {
    final c = await _pump(tester);

    await _openMenu(tester, 'sing-box');
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sing-box?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.log, isEmpty);

    await _openMenu(tester, 'sing-box');
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.log, ['stop sing-box']);

    await _openMenu(tester, 'sing-box');
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(find.text('Restart sing-box?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.log, ['stop sing-box', 'restart sing-box']);
  });

  testWidgets('a disabled service shows a pill and offers enable, which re-reads the flags',
      (tester) async {
    final c = await _pump(tester, flags: {'ENABLE_TELEMT': 'false'});
    expect(c.flagsCalls, 1);
    expect(find.text('DISABLED'), findsOneWidget);

    await _openMenu(tester, 'telemt');
    expect(find.text('Enable and start'), findsOneWidget);
    expect(find.text('Disable and stop'), findsNothing);
    await tester.tap(find.text('Enable and start'));
    await tester.pumpAndSettle();

    // Single-flag enable is not disruptive: no dialog.
    expect(find.byType(AlertDialog), findsNothing);
    expect(c.log, ['enable telemt']);
    expect(c.flagsCalls, 2);
    expect(c.statusCalls, 2);
    expect(find.text('Enable telemt done'), findsOneWidget);
  });

  testWidgets('disable asks first and names the flag it flips', (tester) async {
    final c = await _pump(tester);

    await _openMenu(tester, 'wireguard');
    expect(find.text('Disable and stop'), findsOneWidget);
    expect(find.text('Enable and start'), findsNothing);
    await tester.tap(find.text('Disable and stop'));
    await tester.pumpAndSettle();
    expect(find.text('Disable wireguard?'), findsOneWidget);
    expect(find.textContaining('ENABLE_WIREGUARD'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.log, isEmpty);

    await _openMenu(tester, 'wireguard');
    await tester.tap(find.text('Disable and stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.log, ['disable wireguard']);
  });

  testWidgets('enabling a multi-flag service lists every flag first', (tester) async {
    final c = await _pump(tester, flags: {
      'ENABLE_REALITY': 'false',
      'ENABLE_TROJAN': 'false',
      'ENABLE_HYSTERIA2': 'false',
      'ENABLE_SS': 'false',
      'ENABLE_SNELL': 'false',
      'ENABLE_ANYTLS': 'false',
    });
    await _openMenu(tester, 'sing-box');
    await tester.tap(find.text('Enable and start'));
    await tester.pumpAndSettle();
    expect(find.text('Enable sing-box?'), findsOneWidget);
    expect(find.textContaining('ENABLE_REALITY, ENABLE_TROJAN'), findsOneWidget);
    expect(find.textContaining('ENABLE_ANYTLS'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.log, ['enable sing-box']);
  });

  testWidgets('support containers get start/stop/restart only', (tester) async {
    await _pump(tester);
    await _openMenu(tester, 'certbot');
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Enable and start'), findsNothing);
    expect(find.text('Disable and stop'), findsNothing);
  });

  testWidgets('a failed action shows the exit code and the CLI output', (tester) async {
    final c = await _pump(tester);
    c.nextServiceError = SshCommandException(
      'moav start wireguard',
      const SshOutput(
        stdout: "Profile 'wireguard' is disabled in .env.\nNo service selected\n",
        stderr: '',
        exitCode: 1,
      ),
    );
    await _openMenu(tester, 'wireguard');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(c.log, isEmpty);
    expect(find.textContaining('The command failed on the server (exit 1).'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Profile 'wireguard' is disabled in .env."), findsOneWidget);
    // Status was still re-read so the row reflects reality.
    expect(c.statusCalls, 2);
  });

  testWidgets('flags that cannot be read leave both toggles available', (tester) async {
    final c = _Controller()..flagsError = StateError('no .env');
    await tester.pumpWidget(ProviderScope(
      retry: noProviderRetry,
      overrides: [moavControllerProvider(demoProfile.id).overrideWithValue(c)],
      child: MaterialApp(theme: moavDarkTheme(), home: const OperateScreen(profile: demoProfile)),
    ));
    await tester.pumpAndSettle();
    expect(c.flagsCalls, 1);
    // The services tab still renders; nothing is marked disabled.
    expect(find.text('wireguard'), findsOneWidget);
    expect(find.text('DISABLED'), findsNothing);
    await _openMenu(tester, 'wireguard');
    expect(find.text('Enable and start'), findsOneWidget);
    expect(find.text('Disable and stop'), findsOneWidget);
  });
}
