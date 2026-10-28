import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';

import '../support/fixtures.dart';

void main() {
  jsonMain();

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
      expect(MoavCli.classifyBundleFile('moav-demo-wg.conf'),
          (protocol: 'wireguard', qr: true));
      expect(MoavCli.classifyBundleFile('moav-demo-wgws.conf'),
          (protocol: 'wireguard-wstunnel', qr: true));
      expect(MoavCli.classifyBundleFile('moav-demo-awg.conf'),
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

  group('parseAdminPanel', () {
    test('reads port, flag and a quoted password', () {
      final a = MoavCli.parseAdminPanel(
        '__ADMIN__\nport=9443\nenabled=true\npassword="s3cret=pw"\n__END__\n',
      );
      expect(a, isNotNull);
      expect(a!.port, 9443);
      expect(a.enabled, isTrue);
      expect(a.password, 's3cret=pw');
      expect(a.toString(), isNot(contains('s3cret')));
    });

    test('defaults when values are empty, null without markers', () {
      final a = MoavCli.parseAdminPanel(
        '__ADMIN__\nport=\nenabled=\npassword=\n__END__\n',
      )!;
      expect(a.port, MoavCli.defaultAdminPort);
      expect(a.enabled, isTrue);
      expect(a.password, isNull);
      expect(MoavCli.parseAdminPanel(''), isNull);
      final off = MoavCli.parseAdminPanel(
        '__ADMIN__\nenabled=false\npassword=\'plain\'\n__END__',
      )!;
      expect(off.enabled, isFalse);
      expect(off.password, 'plain');
    });

    test('snippet reads the documented .env keys and never fails', () {
      expect(MoavCli.adminPanel, contains("grep -m1 '^ADMIN_PASSWORD='"));
      expect(MoavCli.adminPanel, contains('ev PORT_ADMIN'));
      expect(MoavCli.adminPanel, contains('ev ENABLE_ADMIN_UI'));
      expect(MoavCli.adminPanel, isNot(contains('exit 1')));
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

void jsonMain() {
  group('decodeJsonDocument', () {
    test('decodes 2.3.x documents', () {
      expect(MoavCli.decodeJsonDocument(jsonFixture('status.json')), isA<Map>());
      expect(MoavCli.decodeJsonDocument(jsonFixture('user_list.json')),
          isA<List>());
      expect(MoavCli.decodeJsonDocument('\x1b[0m\n{"ok": true}\n'),
          {'ok': true});
    });

    test('returns null for 2.2.x text output', () {
      for (final f in ['status.txt', 'doctor.txt', 'user_list.txt']) {
        expect(MoavCli.decodeJsonDocument(fixture(f)), isNull, reason: f);
      }
      expect(
        MoavCli.decodeJsonDocument(jsonFixture('doctor_json_rejected_2_2.txt')),
        isNull,
      );
      expect(MoavCli.decodeJsonDocument(''), isNull);
      expect(MoavCli.decodeJsonDocument('{not json'), isNull);
    });
  });

  group('parseStatusJson', () {
    test('parses the 2.3.1 document', () {
      final s = MoavCli.parseStatusJson(jsonFixture('status.json'))!;
      expect(s.version, '2.3.1');
      expect(s.services.map((x) => x.name),
          ['sing-box', 'admin', 'certbot', 'grafana', 'gooserelay', 'wireguard']);
      expect(s.services[0].state, ServiceState.running);
      expect(s.services[0].uptime, '7 days');
      expect(s.services[0].ports, ['443', '8443']);
      expect(s.services[1].uptime, '~1 hour');
      expect(s.services[2].state, ServiceState.exited);
      expect(s.services[2].uptime, isNull);
      expect(s.services[2].ports, isEmpty);
      expect(s.services[3].state, ServiceState.unhealthy);
      expect(s.services[4].state, ServiceState.never);
      expect(s.runningCount, 3); // running + running + unhealthy
      expect(s.adminUrl.toString(), 'https://vpn.example.com:9443');
      expect(s.grafanaUrl.toString(), 'https://vpn.example.com:9444');
      expect(s.grafanaCdnUrl, isNull);
      expect(s.defaultProfiles, ['proxy', 'wireguard', 'admin', 'monitoring']);
    });

    test('null URLs on a domainless box and raw compose states', () {
      final s = MoavCli.parseStatusJson(
        '{"version":"2.3.1","admin_url":null,"grafana_url":null,'
        '"admin_port":9443,"grafana_port":9444,"default_profiles":[],'
        '"services":[{"name":"a","state":"starting","uptime":"","ports":[]},'
        '{"name":"b","state":"created","uptime":"","ports":[]},'
        '{"name":"c","state":"paused","uptime":"","ports":[]}]}',
      )!;
      expect(s.adminUrl, isNull);
      expect(s.grafanaUrl, isNull);
      expect(s.services.map((x) => x.state),
          [ServiceState.starting, ServiceState.stopped, ServiceState.unknown]);
      expect(s.runningCount, 1);
    });

    test('parseStatusAny picks json or text', () {
      final j = MoavCli.parseStatusAny(jsonFixture('status.json'));
      expect(j.format, CliFormat.json);
      expect(j.report.version, '2.3.1');
      final t = MoavCli.parseStatusAny(fixture('status.txt'));
      expect(t.format, CliFormat.text);
      expect(t.report.version, '2.2.2');
      expect(t.report.services.length, 5);
      expect(MoavCli.parseStatusJson('{"version":"x"}'), isNull);
      expect(MoavCli.parseStatusJson(fixture('status.txt')), isNull);
    });
  });

  group('parseDoctorJson', () {
    test('parses the 2.3.1 document with a description line', () {
      final r = MoavCli.parseDoctorJson(jsonFixture('doctor_env.json'))!;
      expect(r.checks.single.name, 'env');
      expect(r.checks.single.result, CheckResult.pass);
      final lines = r.checks.single.detail!.split('\n');
      expect(lines.first, MoavCli.doctorDescriptions['env']);
      expect(lines[1], startsWith('○ 129 of 136 variables'));
      expect(r.healthy, isTrue);
    });

    test('pass/warn/fail statuses and unknown ids', () {
      final r = MoavCli.parseDoctorJson(
        '[\n'
        '  {"id": "docker", "status": "pass", "detail": "✓ Docker running; ✓ Compose v2"},\n'
        '  {"id": "host", "status": "warn", "detail": "○ swap in use"},\n'
        '  {"id": "services", "status": "fail", "detail": "✗ grafana down"},\n'
        '  {"id": "newcheck", "status": "pass", "detail": ""}\n'
        ']\n',
      )!;
      final byName = {for (final c in r.checks) c.name: c};
      expect(byName['docker']!.result, CheckResult.pass);
      expect(byName['docker']!.detail!.split('\n'),
          [MoavCli.doctorDescriptions['docker'], '✓ Docker running', '✓ Compose v2']);
      expect(byName['host']!.result, CheckResult.warn);
      expect(byName['services']!.result, CheckResult.fail);
      expect(byName['newcheck']!.detail, 'newcheck');
      expect(r.healthy, isFalse);
    });

    test('2.2.x rejection text and plain doctor text are not documents', () {
      expect(MoavCli.parseDoctorJson(jsonFixture('doctor_json_rejected_2_2.txt')),
          isNull);
      expect(MoavCli.parseDoctorJson(fixture('doctor.txt')), isNull);
      expect(MoavCli.parseDoctor(fixture('doctor.txt')).checks, isNotEmpty);
    });
  });

  group('parseUserListJson', () {
    test('parses the 2.3.1 document and aliases telemt', () {
      final users = MoavCli.parseUserListJson(jsonFixture('user_list.json'))!;
      expect(users.map((u) => u.name), ['alice', 'bob', 'carol']);
      expect(users[0].bundleReady, isTrue);
      expect(users[0].protocols,
          ['amneziawg', 'sing-box', 'telegram', 'wireguard', 'xray']);
      expect(users[1].bundleReady, isFalse);
      expect(users[1].protocols, ['sing-box', 'trusttunnel', 'xray']);
      expect(users[2].protocols, ['wireguard']);
    });

    test('empty document and text fallback', () {
      expect(MoavCli.parseUserListJson('[\n]\n'), isEmpty);
      expect(MoavCli.parseUserListJson(fixture('user_list.txt')), isNull);
      final any = MoavCli.parseUserListAny(fixture('user_list.txt'));
      expect(any.format, CliFormat.text);
      expect(any.users.map((u) => u.name), ['alice', 'bob', 'carol']);
      expect(MoavCli.parseUserListAny(jsonFixture('user_list.json')).format,
          CliFormat.json);
      expect(MoavCli.looksLikeUserListText(fixture('user_list.txt')), isTrue);
      expect(MoavCli.looksLikeUserListText('Unknown option: --json'), isFalse);
    });
  });

  group('parseUserAction', () {
    test('add: success, duplicate, failure, invalid name', () {
      final ok = MoavCli.parseUserAction(jsonFixture('user_add.json'), user: 'dave')!;
      expect(ok.ok, isTrue);
      expect(ok.action, 'add');
      expect(ok.bundleDir, 'outputs/bundles/dave');
      expect(ok.error, isNull);

      final dup = MoavCli.parseUserAction(jsonFixture('user_add_dup.json'), user: 'dave')!;
      expect(dup.ok, isFalse);
      expect(dup.alreadyExists, isTrue);

      final failed = MoavCli.parseUserAction(jsonFixture('user_add_failed.json'), user: 'badguy')!;
      expect(failed.ok, isFalse);
      expect(failed.error, 'user-add.sh exited 1');
      expect(failed.alreadyExists, isFalse);

      final invalid = MoavCli.parseUserAction(jsonFixture('user_add_invalid.json'), user: 'bad name!')!;
      expect(invalid.ok, isFalse);
      expect(invalid.error, startsWith('Invalid username'));
    });

    test('remove: success and unknown user', () {
      final ok = MoavCli.parseUserAction(jsonFixture('user_remove.json'), user: 'dave')!;
      expect(ok.ok, isTrue);
      expect(ok.action, 'remove');
      final unknown = MoavCli.parseUserAction(jsonFixture('user_remove_unknown.json'), user: 'nobody')!;
      expect(unknown.ok, isFalse);
      expect(unknown.error, contains('not found'));
    });

    test('text output is not a result; a missing entry is an error', () {
      expect(MoavCli.parseUserAction('Unknown option: --json\n', user: 'x'), isNull);
      expect(MoavCli.parseUserAction("[INFO] Adding user 'x'\n", user: 'x'), isNull);
      final other = MoavCli.parseUserAction(jsonFixture('user_add.json'), user: 'erin')!;
      expect(other.ok, isTrue); // document ok, no per-user entry
      expect(other.error, isNull);
    });
  });

  test('json command strings', () {
    expect(MoavCli.statusJson, endsWith('status --json'));
    expect(MoavCli.doctorJson, endsWith('doctor --json'));
    expect(MoavCli.userListJson, endsWith('user list --json'));
    expect(MoavCli.userAddJson("a'b"), endsWith("user add 'a'\\''b' --json"));
    expect(MoavCli.userRemoveJson('x'), endsWith("user remove 'x' --json"));
    // JSON commands must not merge stderr into the document.
    for (final c in [MoavCli.statusJson, MoavCli.doctorJson, MoavCli.userListJson]) {
      expect(c, isNot(contains('2>&1')));
    }
  });
}
