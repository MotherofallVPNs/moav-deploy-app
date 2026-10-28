import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/features/operate/chart_panels.dart';

import '../support/fake_box.dart';
import '../support/fixtures.dart';

SshMoavController controllerAnswering(Map<String, String> stdoutByCommand) =>
    FakeBox({for (final e in stdoutByCommand.entries) e.key: ok(e.value)})
        .controller;

void main() {
  group('Grafana access from .env', () {
    test('the snippet reads the upstream keys and probes the scheme', () {
      expect(MoavCli.grafanaPortKey, 'PORT_GRAFANA');
      expect(MoavCli.grafanaEnabledKey, 'ENABLE_MONITORING');
      // docker-compose.yml: GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}.
      expect(MoavCli.grafanaPasswordKey, 'ADMIN_PASSWORD');
      expect(MoavCli.grafanaAdminUser, 'admin');
      expect(MoavCli.defaultGrafanaPort, 9444);
      expect(MoavCli.grafanaPanel, contains('ev PORT_GRAFANA'));
      expect(MoavCli.grafanaPanel, contains('PG:-9444'));
      expect(MoavCli.grafanaPanel, contains("'^ADMIN_PASSWORD='"));
      expect(MoavCli.grafanaPanel, contains('https://127.0.0.1:\$PG/api/health'));
      expect(MoavCli.grafanaPanel, contains('http://127.0.0.1:\$PG/api/health'));
      // Only the loopback side is probed: the public port is never used.
      expect(MoavCli.grafanaPanel, isNot(contains('DOMAIN')));
    });

    test('parses port, flag, scheme and an unquoted password', () {
      final a = MoavCli.parseGrafanaPanel(
        'junk\n__GRAFANA__\nport=9555\nenabled=true\nscheme=http\n'
        'password=s3cret=with=equals\n__END__\n',
      )!;
      expect(a.port, 9555);
      expect(a.enabled, isTrue);
      expect(a.scheme, 'http');
      expect(a.password, 's3cret=with=equals');
      expect(a.toString(), isNot(contains('s3cret')));
      expect(a.toString(), contains('password: present'));
    });

    test('defaults: https, enabled, 9444, no password; strips quotes', () {
      final a = MoavCli.parseGrafanaPanel(
        '__GRAFANA__\nport=\nenabled=\npassword=\n__END__\n',
      )!;
      expect(a.port, 9444);
      expect(a.enabled, isTrue);
      expect(a.scheme, 'https');
      expect(a.password, isNull);
      final q = MoavCli.parseGrafanaPanel(
        '__GRAFANA__\nport=9444\nenabled=false\nscheme=https\n'
        'password="quoted pw"\n__END__\n',
      )!;
      expect(q.enabled, isFalse);
      expect(q.password, 'quoted pw');
      expect(MoavCli.parseGrafanaPanel('no markers'), isNull);
    });

    test('controller runs the snippet and surfaces the access', () async {
      final c = controllerAnswering({
        MoavCli.grafanaPanel:
            '__GRAFANA__\nport=9444\nenabled=true\nscheme=https\npassword=pw\n__END__\n',
      });
      final a = await c.grafanaAccess();
      expect(a.port, 9444);
      expect(a.password, 'pw');
      final broken = controllerAnswering({MoavCli.grafanaPanel: 'bash: nope'});
      await expectLater(broken.grafanaAccess(), throwsStateError);
    });
  });

  group('Prometheus range snippet', () {
    test('queries every chart series and the exporter vector, encoded', () {
      final s = MoavCli.prometheusRange;
      expect(s, contains('api/v1/query_range?query=\$2&start=\$START&end=\$NOW&step=\$STEP'));
      expect(s, contains('START=\$((NOW-3600)); STEP=60'));
      for (final key in MoavCli.chartQueries.keys) {
        expect(s, contains('  r $key '));
      }
      expect(s, contains("  q exporters_up '${Uri.encodeComponent('sum by (job)(up)')}'"));
      // The PromQL is percent-encoded: no raw quotes or braces reach wget.
      expect(s, contains('node_cpu_seconds_total%7Bmode%3D%22idle%22%7D'));
      expect(s, contains('for n in cpu_percent mem_percent rx_bytes_per_s'));
      expect(s, contains('docker exec moav-prometheus'));
    });

    test('parses matrices, skips NaN, bad blocks and empty results', () {
      final snap = MoavCli.parseMetricSeries(jsonFixture('prometheus_range.txt'),
          now: DateTime(2026));
      expect(snap.window, const Duration(hours: 1));
      final cpu = snap.named('cpu_percent').single;
      expect(cpu.points.map((p) => p.value), [12.5, 40.25, 33]);
      expect(cpu.points.first.time,
          DateTime.fromMillisecondsSinceEpoch(1761580800000, isUtc: true));
      expect(cpu.label, isNull);
      expect(snap.named('tx_bytes_per_s'), isEmpty);
      expect(snap.named('users_wireguard'), isEmpty);
      expect(snap.named('users_amneziawg'), isEmpty);
      expect(snap.named('users_conduit'), isEmpty);
      final up = snap.named('exporters_up');
      expect(up.map((s) => s.label), ['node', 'telemt-api', 'cadvisor']);
      expect(up.map((s) => s.last), [1, 0, 1]);
    });

    test('no prometheus container: markers only, no series', () {
      final snap = MoavCli.parseMetricSeries('__RANGE__\n__END__\n');
      expect(snap.series, isEmpty);
    });

    test('controller maps the snippet into a ChartsSnapshot', () async {
      final c = controllerAnswering(
          {MoavCli.prometheusRange: jsonFixture('prometheus_range.txt')});
      final snap = await c.metricSeries();
      expect(snap.named('mem_percent').single.last, 62.8);
    });
  });

  group('chart panels', () {
    final snap = MoavCli.parseMetricSeries(jsonFixture('prometheus_range.txt'));

    test('builds the four panels, dropping series without data', () {
      final panels = chartPanels(snap);
      expect(panels.map((p) => p.key), ['cpu', 'mem', 'net', 'users']);
      final cpu = panels[0];
      expect(cpu.unit, ChartUnit.percent);
      expect(cpu.fixedMax, 100);
      expect(chartMax(cpu), 100);
      final net = panels[2];
      // Outbound returned no samples, so only Inbound is drawn.
      expect(net.series.map((s) => s.label), ['Inbound']);
      expect(net.unit, ChartUnit.bytesPerSecond);
      expect(chartMax(net), closeTo(2097152 * 1.15, 1));
      final users = panels[3];
      expect(users.series.map((s) => s.label), ['sing-box', 'xray']);
      // Colour follows the protocol, not the position in the list.
      expect(users.series[1].color, ChartPalette.orange);
      expect(users.series.map((s) => s.last), [15, 2]);
    });

    test('an empty snapshot yields no panels', () {
      expect(chartPanels(ChartsSnapshot(series: const [], collectedAt: DateTime(2026))),
          isEmpty);
      expect(chartMax(const ChartPanel(
        key: 'x', title: 'x', unit: ChartUnit.count, series: [],
      )), 1);
    });

    test('exporter health is one row per job, sorted', () {
      final rows = exporterHealth(snap);
      expect(rows.map((r) => '${r.job}:${r.up}'),
          ['cadvisor:true', 'node:true', 'telemt-api:false']);
    });

    test('values format per unit', () {
      expect(formatChartValue(42.4, ChartUnit.percent), '42%');
      expect(formatChartValue(3.26, ChartUnit.percent), '3.3%');
      expect(formatChartValue(2097152, ChartUnit.bytesPerSecond), '2.0 MB/s');
      expect(formatChartValue(14, ChartUnit.count), '14');
    });
  });
}
