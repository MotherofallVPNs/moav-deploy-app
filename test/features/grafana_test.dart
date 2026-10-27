import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/grafana_login.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/operate/charts_view.dart';
import 'package:moav_deploy/features/operate/grafana_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/widgets/moav_app_bar.dart';

import '../support/memory_cred_store.dart';

/// In-app Grafana (tunnel + .env sign-in) and the native charts.

const _secret = 'grafana-pw-never-shown';

class _Tunnel implements ServerTunnel {
  _Tunnel(this.remotePort);

  final int remotePort;
  var closed = false;

  @override
  int get localPort => 45001;

  @override
  Uri uri({String scheme = 'https', String path = '/'}) =>
      Uri(scheme: scheme, host: '127.0.0.1', port: localPort, path: path);

  @override
  bool get isOpen => !closed;

  @override
  Future<void> close() async => closed = true;
}

class _Controller implements MoavController {
  final log = <String>[];
  GrafanaAccess access = const GrafanaAccess(port: 9444, password: _secret);
  _Tunnel? tunnel;

  @override
  Future<ConnectionCheck> ping() async => const ConnectionCheck(
        reachable: true,
        moavInstalled: true,
        moavVersion: '2.3.1',
      );

  @override
  Future<GrafanaAccess> grafanaAccess() async {
    log.add('grafana access');
    return access;
  }

  @override
  Future<ServerTunnel> openTunnel(int remotePort) async {
    log.add('tunnel $remotePort');
    return tunnel = _Tunnel(remotePort);
  }

  @override
  Future<Monitoring> monitoring() async => Monitoring(
        grafanaUrl: Uri.parse('https://demo.example.org:9444'),
        grafanaHealthy: true,
        grafanaVersion: '13.2.4',
        collectedAt: DateTime(2026),
      );

  @override
  Future<MetricsSnapshot> metrics() async =>
      MetricsSnapshot(metrics: const [], collectedAt: DateTime(2026));

  @override
  Future<ChartsSnapshot> metricSeries() async {
    log.add('metric series');
    return MoavCli.parseMetricSeries(
      File('test/fixtures/json/prometheus_range.txt').readAsStringSync(),
      now: DateTime(2026),
    );
  }

  @override
  Future<ServiceStatusReport> status() async => ServiceStatusReport(
        collectedAt: DateTime(2026),
        services: const [
          ServiceStatus(name: 'sing-box', state: ServiceState.running),
        ],
      );

  @override
  Future<ServiceFlags> serviceFlags() async =>
      ServiceFlags(values: const {}, collectedAt: DateTime(2026));

  @override
  Future<InstallStatus?> updateStatus() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Factory extends MoavControllerFactory {
  _Factory(this.controller) : super(secretResolver: (_) async => null);

  final MoavController controller;

  @override
  MoavController forServer(ServerProfile profile) => controller;
}

const _profile = ServerProfile(
  id: 's1',
  label: 'Demo',
  host: 'demo.example.org',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.generatedKey,
);

/// Records what the screen posts to Grafana; answers like the real helper.
class _SignIn {
  final calls = <(Uri, String, String)>[];
  var reject = false;

  Future<List<Cookie>> call(Uri origin,
      {required String user, required String password}) async {
    calls.add((origin, user, password));
    if (reject) throw const GrafanaLoginRejected();
    return [Cookie('grafana_session', 'abc')];
  }
}

Widget _app(MemoryCredStore store, _Controller controller, _SignIn signIn) =>
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        moavControllerFactoryProvider.overrideWithValue(_Factory(controller)),
        grafanaSignInProvider.overrideWithValue(signIn.call),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

Future<void> _openHubTile(WidgetTester tester, String title) async {
  await tester.tap(find.text('Demo'));
  await tester.pumpAndSettle();
  final tile = find.text(title);
  await tester.scrollUntilVisible(tile, 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void _expectNoSecretOnScreen(WidgetTester tester) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    expect(t.data ?? '', isNot(contains(_secret)));
  }
}

void main() {
  group('Grafana over the tunnel', () {
    testWidgets('menu entry, tunnel to PORT_GRAFANA, sign-in with .env password',
        (tester) async {
      final store = MemoryCredStore()..profiles = [_profile];
      final controller = _Controller();
      final signIn = _SignIn();
      await tester.pumpWidget(_app(store, controller, signIn));
      await tester.pumpAndSettle();

      // Reachable from the server card menu on the home screen.
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      expect(find.text('Grafana'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await _openHubTile(tester, 'Grafana');

      expect(controller.log, ['grafana access', 'tunnel 9444']);
      expect(signIn.calls.single.$1, Uri.parse('https://127.0.0.1:45001/'));
      expect(signIn.calls.single.$2, 'admin');
      expect(signIn.calls.single.$3, _secret);
      expect(find.text('Grafana preview is not available here'), findsOneWidget);
      expect(
        find.text('https://127.0.0.1:45001/ forwards to server port 9444 (signed in)'),
        findsOneWidget,
      );
      expect(find.byTooltip('Open in browser'), findsOneWidget);
      _expectNoSecretOnScreen(tester);

      final element = tester.element(find.byType(MoavAppBar).last);
      final ops = ProviderScope.containerOf(element).read(activityProvider);
      expect(ops.current!.label, 'Grafana · Demo');
      expect(ops.current!.phase, OperationPhase.done);
      expect(ops.current!.lines.join('\n'), isNot(contains(_secret)));
      expect(ops.current!.lines.join('\n'), contains('password read'));
      expect(controller.access.toString(), isNot(contains(_secret)));

      // Leaving the screen closes the tunnel.
      expect(controller.tunnel!.closed, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.tunnel!.closed, isTrue);
    });

    testWidgets('honours the probed scheme (plain http, no certificate)',
        (tester) async {
      final store = MemoryCredStore()..profiles = [_profile];
      final controller = _Controller()
        ..access = const GrafanaAccess(port: 9555, scheme: 'http', password: _secret);
      final signIn = _SignIn();
      await tester.pumpWidget(_app(store, controller, signIn));
      await tester.pumpAndSettle();
      await _openHubTile(tester, 'Grafana');
      expect(controller.log, ['grafana access', 'tunnel 9555']);
      expect(signIn.calls.single.$1, Uri.parse('http://127.0.0.1:45001/'));
    });

    testWidgets('disabled monitoring is reported without a tunnel',
        (tester) async {
      final store = MemoryCredStore()..profiles = [_profile];
      final controller = _Controller()
        ..access = const GrafanaAccess(port: 9444, enabled: false);
      final signIn = _SignIn();
      await tester.pumpWidget(_app(store, controller, signIn));
      await tester.pumpAndSettle();
      await _openHubTile(tester, 'Grafana');
      expect(find.text('Monitoring is disabled on this server.'), findsOneWidget);
      expect(controller.log, ['grafana access']);
      expect(controller.tunnel, isNull);
      expect(signIn.calls, isEmpty);
    });

    testWidgets('a rejected password shows a notice and drops it',
        (tester) async {
      final store = MemoryCredStore()..profiles = [_profile];
      final controller = _Controller();
      final signIn = _SignIn()..reject = true;
      await tester.pumpWidget(_app(store, controller, signIn));
      await tester.pumpAndSettle();
      await _openHubTile(tester, 'Grafana');
      expect(signIn.calls.length, 1);
      expect(find.textContaining('Grafana rejected the password'), findsOneWidget);
      expect(find.textContaining('(signed in)'), findsNothing);
      _expectNoSecretOnScreen(tester);
    });
  });

  group('native charts on the Analytics tab', () {
    testWidgets('draws the panels from the Prometheus series and links to Grafana',
        (tester) async {
      final store = MemoryCredStore()..profiles = [_profile];
      final controller = _Controller();
      final signIn = _SignIn();
      await tester.pumpWidget(_app(store, controller, signIn));
      await tester.pumpAndSettle();
      await _openHubTile(tester, 'Analytics');

      expect(controller.log, contains('metric series'));
      expect(find.text('LAST HOUR'), findsOneWidget);
      expect(find.byType(MetricChartCard), findsNWidgets(4));
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('RAM used'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Active users'), findsOneWidget);
      // Headline value of the single-series CPU panel: last sample, 33%.
      expect(find.text('33%'), findsOneWidget);
      // Multi-series legend names the protocols with their latest values.
      expect(find.text('sing-box'), findsWidgets);
      expect(find.text('xray'), findsOneWidget);
      // Exporter row from the `up` vector.
      await tester.scrollUntilVisible(find.byType(ExporterRow), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 up'), findsOneWidget);
      expect(find.text('TELEMT-API'), findsOneWidget);

      // The full dashboards open through the tunnel, not the public URL.
      // Back to the top: the lazy list has let go of the Grafana card.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Grafana'));
      await tester.pumpAndSettle();
      expect(find.byType(GrafanaScreen), findsOneWidget);
      expect(controller.log, contains('tunnel 9444'));
      expect(signIn.calls.single.$3, _secret);
    });
  });
}
