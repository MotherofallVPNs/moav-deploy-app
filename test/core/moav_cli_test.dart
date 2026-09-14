import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseUserList', () {
    test('merges sections into distinct users with bundle flag', () {
      final users = MoavCli.parseUserList(fixture('user_list.txt'));
      expect(users.map((u) => u.name), ['alice', 'bob', 'carol']);
      final t = users.firstWhere((u) => u.name == 'carol');
      expect(t.bundleReady, isTrue);
      expect(t.protocols,
          ['sing-box', 'telegram', 'trusttunnel', 'wireguard', 'xray']);
      final g = users.firstWhere((u) => u.name == 'bob');
      expect(g.bundleReady, isFalse);
      expect(g.protocols, ['sing-box']);
    });

    test('ignores placeholders and ANSI', () {
      final users = MoavCli.parseUserList(
        '\x1b[1m=== AmneziaWG Peers ===\x1b[0m\n  (no peers)\n'
        '=== User Bundles ===\n  • \x1b[32mbob\x1b[0m (3 files)\n',
      );
      expect(users.single.name, 'bob');
      expect(users.single.bundleReady, isTrue);
    });

    test('empty output yields no users', () {
      expect(MoavCli.parseUserList(''), isEmpty);
    });
  });

  group('bundle files', () {
    test('classification and QR payloads', () {
      expect(MoavCli.classifyBundleFile('reality-qr.png'), isNull);
      expect(MoavCli.classifyBundleFile('README.html'), isNull);
      expect(MoavCli.classifyBundleFile('reality.txt'),
          (protocol: 'reality', qr: true));
      expect(MoavCli.classifyBundleFile('moav-yorks-wg.conf'),
          (protocol: 'wireguard', qr: true));
      expect(MoavCli.classifyBundleFile('moav-yorks-wgws.conf'),
          (protocol: 'wireguard-wstunnel', qr: true));
      expect(MoavCli.classifyBundleFile('moav-yorks-awg.conf'),
          (protocol: 'amneziawg', qr: true));
      expect(MoavCli.classifyBundleFile('trusttunnel.toml'),
          (protocol: 'trusttunnel', qr: false));
      expect(MoavCli.classifyBundleFile('xdns-config.json'),
          (protocol: 'xdns', qr: false));
      expect(MoavCli.classifyBundleFile('shadowsocks-singbox.json'),
          (protocol: 'shadowsocks', qr: false));

      final e = MoavCli.bundleEntry('hysteria2.txt', 'hy2://x@h:443\n')!;
      expect(e.qrPayload, 'hy2://x@h:443');
      expect(e.title, 'Hysteria2');
      expect(MoavCli.bundleEntry('dnstt-server.pub', 'abc')!.qrPayload, isNull);
      expect(MoavCli.bundleEntry('wireguard-qr.png', ''), isNull);
    });

    test('sort puts phone links first', () {
      final list = [
        MoavCli.bundleEntry('trusttunnel.toml', 'x')!,
        MoavCli.bundleEntry('moav-wg.conf', 'x')!,
        MoavCli.bundleEntry('subscription.txt', 'x')!,
      ]..sort(MoavCli.compareEntries);
      expect(list.map((e) => e.protocol),
          ['subscription', 'wireguard', 'trusttunnel']);
    });
  });

  group('parseTest', () {
    test('extracts trailing JSON after docker noise', () {
      final m = MoavCli.parseTest('carol', fixture('test_json.txt'));
      expect(m.user, 'carol');
      expect(m.overall, CheckResult.fail);
      expect(m.results.length, 4);
      expect(m.results.first.protocol, 'reality');
      expect(m.results.first.result, CheckResult.pass);
      expect(m.count(CheckResult.warn), 1);
      expect(m.count(CheckResult.skip), 1);
      expect(m.allPass, isFalse);
      expect(
        m.results.firstWhere((r) => r.protocol == 'telemt').detail,
        contains('port blocked'),
      );
    });

    test('allPass ignores skips', () {
      final m = MoavCli.parseTest(
        'u',
        '{"overall_status":"pass","tests":{"a":{"status":"pass"},'
        '"b":{"status":"skip","detail":"none"}}}',
      );
      expect(m.allPass, isTrue);
    });

    test('no JSON throws FormatException', () {
      expect(() => MoavCli.parseTest('u', 'nothing here {'),
          throwsFormatException);
    });
  });

  group('parseDoctor', () {
    test('groups checks and derives pass/warn/fail', () {
      final r = MoavCli.parseDoctor(fixture('doctor.txt'));
      final byName = {for (final c in r.checks) c.name: c};
      expect(byName.keys,
          ['docker', 'memory', 'dns', 'services', 'ports', 'host', 'updates']);
      expect(byName['docker']!.result, CheckResult.pass);
      expect(byName['dns']!.result, CheckResult.pass);
      expect(byName['services']!.result, CheckResult.fail);
      expect(byName['host']!.result, CheckResult.warn);
      expect(byName['updates']!.result, CheckResult.warn);
      expect(byName['updates']!.detail, contains('v2.2.4'));
      expect(r.healthy, isFalse);
      // Summary section never becomes a check.
      expect(byName.containsKey('Doctor'), isFalse);
    });
  });

  group('parseStatus', () {
    test('parses the box table, URLs and version', () {
      final s = MoavCli.parseStatus(fixture('status.txt'));
      expect(s.version, '2.2.2');
      expect(s.services.map((x) => x.name),
          ['admin', 'grafana', 'sing-box', 'certbot', 'gooserelay']);
      expect(s.runningCount, 3);
      final sb = s.services[2];
      expect(sb.state, ServiceState.running);
      expect(sb.ports, ['2082', '443', '8388', '8443', '8445']);
      expect(sb.uptime, '7 days');
      expect(s.services[3].state, ServiceState.exited);
      expect(s.services[3].uptime, isNull);
      expect(s.services[4].state, ServiceState.never);
      expect(s.adminUrl.toString(), 'https://example.org:9443');
      expect(s.grafanaUrl.toString(), 'https://example.org:9444');
      expect(s.grafanaCdnUrl.toString(), 'https://grafana.example.org:2083');
      expect(s.defaultProfiles, ['proxy', 'wireguard', 'admin', 'monitoring']);
    });
  });

  group('parseMonitoring', () {
    const raw = '''
__URLS__
grafana=https://example.org:9444
admin=https://example.org:9443
__HEALTH__
{
  "database": "ok",
  "version": "13.1.3",
  "commit": "abc"
}
__PROM__
__Q__ targets_up
{"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1789365942.210,"11"]}]}}
__Q__ load1
{"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1789365942.210,"1.18"]}]}}
__Q__ mem_available_bytes
{"status":"success","data":{"resultType":"vector","result":[{"metric":{},"value":[1,"829440000"]}]}}
__Q__ rx_bytes_per_s
{"status":"success","data":{"resultType":"vector","result":[]}}
__Q__ tx_bytes_per_s
wget: can't connect
__END__
''';

    test('urls, health and metrics', () {
      final m = MoavCli.parseMonitoring(raw);
      expect(m.grafanaUrl.toString(), 'https://example.org:9444');
      expect(m.grafanaCdnUrl, isNull);
      expect(m.adminUrl.toString(), 'https://example.org:9443');
      expect(m.grafanaHealthy, isTrue);
      expect(m.grafanaVersion, '13.1.3');
      expect(m.metrics.map((x) => x.name),
          ['Exporters up', 'Load (1m)', 'RAM available']);
      expect(m.metrics[0].value, '11');
      expect(m.metrics[2].value, '791 MB');
    });

    test('grafana down and no prometheus', () {
      final m = MoavCli.parseMonitoring(
        '__URLS__\ngrafana=https://h:9444\n__HEALTH__\n\n__PROM__\n__END__\n',
      );
      expect(m.grafanaHealthy, isNull);
      expect(m.metrics, isEmpty);
      final bad = MoavCli.parseMonitoring(
        '__URLS__\n__HEALTH__\n<html>502</html>\n__PROM__\n__END__\n',
      );
      expect(bad.grafanaHealthy, isFalse);
      expect(bad.grafanaUrl, isNull);
    });
  });

  test('service commands', () {
    expect(MoavCli.service(ServiceAction.restart), endsWith('restart 2>&1'));
    expect(
      MoavCli.service(
        const ServiceAction(ServiceActionKind.stop, service: 'grafana'),
      ),
      endsWith("stop 'grafana' 2>&1"),
    );
    expect(MoavCli.service(ServiceAction.regenerateUsers),
        endsWith('regenerate-users 2>&1'));
    expect(MoavCli.userAdd("a'b"), contains("'a'\\''b'"));
  });
}
