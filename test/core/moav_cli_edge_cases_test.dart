import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

import '../support/fixtures.dart';

/// Parsers on the output a real box produces when things are not tidy: a
/// session dropped mid-document, warnings printed before the JSON, 2.2.x
/// 2.2.x usage text, Alpine `df`, missing sections and wrong types.
/// None of these may throw; each degrades to "unknown" or skips the entry.
void main() {
  group('decodeJsonDocument', () {
    test('a document cut off mid-row is not a document', () {
      expect(MoavCli.decodeJsonDocument(jsonFixture('status_truncated.txt')), isNull);
    });

    test('compose warnings and coloured info lines before the JSON are skipped',
        () {
      final doc = MoavCli.decodeJsonDocument(jsonFixture('status_noisy.txt'));
      expect(doc, isA<Map>());
      expect((doc as Map)['version'], '2.3.1');
    });

    test('scalars, empty output and bare words are never documents', () {
      expect(MoavCli.decodeJsonDocument(''), isNull);
      expect(MoavCli.decodeJsonDocument('   \n'), isNull);
      expect(MoavCli.decodeJsonDocument('42'), isNull);
      expect(MoavCli.decodeJsonDocument('"json string"'), isNull);
      expect(MoavCli.decodeJsonDocument('true'), isNull);
      // `[` inside a line is not a document start (usage text).
      expect(MoavCli.decodeJsonDocument('Usage: moav doctor [check]'), isNull);
    });

    test('text after the closing brace is ignored', () {
      final doc = MoavCli.decodeJsonDocument('{"ok": true}\nDone in 2s\n');
      expect(doc, {'ok': true});
    });
  });

  group('parseStatus (json)', () {
    test('services must be a list, rows need a name, states fall back', () {
      expect(MoavCli.parseStatusJson('{"services": "none"}'), isNull);
      expect(MoavCli.parseStatusJson('{"version": "2.3.1"}'), isNull);
      final r = MoavCli.parseStatusJson('''
{"services": [
  {"state": "running"},
  {"name": "", "state": "running"},
  {"name": "xray", "state": "paused", "ports": [443, "8443/udp"]},
  {"name": "admin", "state": "Up 3 hours (healthy)", "uptime": ""}
], "admin_url": "", "grafana_url": "not a url at all"}
''')!;
      expect(r.services.map((s) => s.name), ['xray', 'admin']);
      expect(r.services[0].state, ServiceState.unknown);
      expect(r.services[0].ports, ['443', '8443/udp']);
      expect(r.services[1].state, ServiceState.unknown);
      expect(r.services[1].uptime, isNull);
      expect(r.version, isNull);
      expect(r.adminUrl, isNull);
      expect(r.defaultProfiles, isEmpty);
      expect(r.runningCount, 0);
    });

    test('the noisy capture parses as json; the truncated one falls to text',
        () {
      final noisy = MoavCli.parseStatusAny(jsonFixture('status_noisy.txt'));
      expect(noisy.format, CliFormat.json);
      expect(noisy.report.services, hasLength(6));

      final cut = MoavCli.parseStatusAny(jsonFixture('status_truncated.txt'));
      expect(cut.format, CliFormat.text);
      // The controller treats "text with no rows" as a reason to re-run.
      expect(cut.report.services, isEmpty);
    });
  });

  group('parseStatus (2.2.x text)', () {
    test('no URL lines, unhealthy and created rows, no last-run column', () {
      final raw = [
        'MoaV v2.2.0',
        '  │ Service   │ Status       │ Last Run │ Uptime  │ Ports │',
        '  │ sing-box  │ ● unhealthy  │ -        │ 2 hours │ 443   │',
        '  │ wireguard │ ○ created    │ -        │ -       │ -     │',
        '  Default profiles: proxy wireguard',
        '',
      ].join('\n');
      final r = MoavCli.parseStatus(raw);
      expect(r.version, '2.2.0');
      expect(r.services.map((s) => s.name), ['sing-box', 'wireguard']);
      expect(r.services[0].state, ServiceState.unhealthy);
      expect(r.services[0].state.isUp, isTrue);
      expect(r.services[0].lastRun, isNull);
      expect(r.services[1].state, ServiceState.stopped);
      expect(r.services[1].ports, isEmpty);
      expect(r.adminUrl, isNull);
      expect(r.grafanaUrl, isNull);
      expect(r.defaultProfiles, ['proxy', 'wireguard']);
      expect(r.runningCount, 1);
    });

    test('a 2.2.x usage error yields an empty report, not an exception', () {
      final r = MoavCli.parseStatusAny(jsonFixture('doctor_json_rejected_2_2.txt'));
      expect(r.format, CliFormat.text);
      expect(r.report.services, isEmpty);
      expect(r.report.version, isNull);
    });
  });

  group('parseDoctor', () {
    test('json: non-list, missing ids, odd statuses and empty detail', () {
      expect(MoavCli.parseDoctorJson('{"id": "docker"}'), isNull);
      final r = MoavCli.parseDoctorJson('''
[
  {"status": "pass", "detail": "no id"},
  {"id": "docker", "status": "ok", "detail": ""},
  {"id": "memory", "status": "warning", "detail": "RAM: 1.9 GB; ! low"},
  {"id": "ports", "status": "error"},
  {"id": "custom", "status": "whatever", "detail": "x"}
]
''')!;
      expect(r.checks.map((c) => c.name), ['docker', 'memory', 'ports', 'custom']);
      expect(r.checks[0].result, CheckResult.pass);
      expect(r.checks[0].detail, 'Check Docker and prerequisites');
      expect(r.checks[1].result, CheckResult.warn);
      expect(r.checks[1].detail, 'Check available RAM\nRAM: 1.9 GB\n! low');
      expect(r.checks[2].result, CheckResult.fail);
      expect(r.checks[3].result, CheckResult.skip);
      expect(r.checks[3].detail, 'custom\nx');
      expect(r.healthy, isFalse);
    });

    test('text: lines before the first header, and the summary stop', () {
      final r = MoavCli.parseDoctor(fixture('doctor_short.txt'));
      expect(r.checks.map((c) => c.name), ['docker', 'services']);
      expect(r.checks[0].result, CheckResult.pass);
      expect(r.checks[1].result, CheckResult.warn);
      expect(r.checks[1].detail, contains('not started yet'));

      final full = MoavCli.parseDoctor(fixture('doctor.txt'));
      // The summary's own ✓/✗ counters never become a check.
      expect(full.checks.map((c) => c.name), isNot(contains('summary')));
      expect(full.checks.last.name, 'updates');
      expect(full.checks.last.result, CheckResult.warn);
    });

    test('text: a check with both ! and ✗ lines fails, not warns', () {
      final r = MoavCli.parseDoctor('''
host - Check CPU load
    ! 929 MiB swapped out
    ✗ load 9.5 on 2 vCPU
    ✓ no zombies
''');
      expect(r.checks.single.result, CheckResult.fail);
      expect(r.checks.single.detail!.split('\n'), hasLength(4));
    });

    test('checkResultFrom accepts the upstream spellings only', () {
      expect(MoavCli.checkResultFrom('PASS'), CheckResult.pass);
      expect(MoavCli.checkResultFrom('success'), CheckResult.pass);
      expect(MoavCli.checkResultFrom('failed'), CheckResult.fail);
      expect(MoavCli.checkResultFrom(null), CheckResult.skip);
      expect(MoavCli.checkResultFrom('skipped'), CheckResult.skip);
    });
  });

  group('parseUserList', () {
    test('json: duplicates, aliases, missing or mistyped fields', () {
      final users = MoavCli.parseUserListJson(jsonFixture('user_list_odd.json'))!;
      expect(users.map((u) => u.name), ['amy', 'zed']);
      final zed = users.last;
      expect(zed.protocols, ['sing-box', 'telegram']);
      expect(zed.bundleReady, isTrue);
      final amy = users.first;
      expect(amy.protocols, isEmpty, reason: 'services must be a list');
      expect(amy.bundleReady, isFalse, reason: 'bundle must be a bool');
    });

    test('2.2.x usage text is neither json nor the sectioned list', () {
      final raw = jsonFixture('doctor_json_rejected_2_2.txt');
      final any = MoavCli.parseUserListAny(raw);
      expect(any.format, CliFormat.text);
      expect(any.users, isEmpty);
      expect(MoavCli.looksLikeUserListText(raw), isFalse);
      expect(MoavCli.looksLikeUserListText(fixture('user_list.txt')), isTrue);
    });

    test('text: a user listed under bundles only has no protocols', () {
      final raw = '=== sing-box Users ===\n  • alice\n\n'
          '=== User Bundles ===\n  • alice (3 files)\n  • ghost (1 file)\n';
      final users = MoavCli.parseUserList(raw);
      expect(users.map((u) => u.name), ['alice', 'ghost']);
      expect(users[0].bundleReady, isTrue);
      expect(users[0].protocols, ['sing-box']);
      expect(users[1].protocols, isEmpty);
    });
  });

  group('parseUserAction', () {
    test('ok must be a bool', () {
      expect(MoavCli.parseUserAction('{"ok": "yes"}', user: 'a'), isNull);
      expect(MoavCli.parseUserAction('{"action": "add"}', user: 'a'), isNull);
    });

    test('a per-user list that lacks the user falls back to the top level', () {
      final other = MoavCli.parseUserAction(
        '{"ok": true, "action": "add", "users": [{"user": "bob", "ok": true}]}',
        user: 'alice',
      )!;
      expect(other.ok, isTrue);
      expect(other.error, isNull);

      final none = MoavCli.parseUserAction(
        '{"ok": false, "action": "remove", "users": []}',
        user: 'alice',
      )!;
      expect(none.ok, isFalse);
      expect(none.error, 'no result for alice');
      expect(none.alreadyExists, isFalse);
    });
  });

  group('parseServiceFlags', () {
    test('ignores export prefixes and comments; lowercases values', () {
      final f = MoavCli.parseServiceFlags(
        'export ENABLE_XHTTP=true\n'
        '#ENABLE_TELEMT=true\n'
        'ENABLE_REALITY=TRUE\n'
        'ENABLE_SS=yes\n'
        'ENABLE_TROJAN=true # legacy clients\n'
        "DEFAULT_PROFILES='proxy  admin'\n"
        'not a flag line\n',
        now: DateTime(2026),
      );
      expect(f.values.keys, ['ENABLE_REALITY', 'ENABLE_SS', 'ENABLE_TROJAN']);
      expect(f.isOn('ENABLE_REALITY'), isTrue);
      expect(f.isOn('ENABLE_SS'), isFalse, reason: 'only "true" counts');
      expect(f.isOn('ENABLE_TROJAN'), isTrue);
      expect(f.isOn('ENABLE_XHTTP'), isTrue, reason: 'unknown: upstream default');
      expect(f.isOn('ENABLE_GOOSERELAY'), isFalse, reason: 'opt-in default');
      expect(f.defaultProfiles, ['proxy', 'admin']);
    });
  });

  group('parseMonitoring', () {
    test('a gateway error page or a non-object health body is unhealthy', () {
      final html = MoavCli.parseMonitoring(
        '__URLS__\ngrafana=https://example.org:9444\n__HEALTH__\n'
        '<html>502 Bad Gateway</html>\n__PROM__\n__END__\n',
      );
      expect(html.grafanaHealthy, isFalse);
      expect(html.grafanaVersion, isNull);
      expect(html.grafanaUrl, Uri.parse('https://example.org:9444'));

      final list = MoavCli.parseMonitoring(
        '__URLS__\n__HEALTH__\n[1, 2]\n__PROM__\n__END__\n',
      );
      expect(list.grafanaHealthy, isFalse);
    });

    test('a missing health section is unknown, not unhealthy', () {
      final m = MoavCli.parseMonitoring('__URLS__\nadmin=https://a:9443\n__END__\n');
      expect(m.grafanaHealthy, isNull);
      expect(m.adminUrl, Uri.parse('https://a:9443'));
      expect(m.metrics, isEmpty);
    });

    test('metric blocks with empty results or garbage are skipped', () {
      final m = MoavCli.parseMonitoring(
        '__URLS__\n__HEALTH__\n\n__PROM__\n'
        '__Q__ load1\n{"data": {"result": []}}\n'
        '__Q__ targets_up\nnot json\n'
        '__Q__ mem_total_bytes\n{"data": {"result": [{"value": [1, "2147483648"]}]}}\n'
        '__END__\n',
      );
      expect(m.metrics.map((x) => x.name), ['RAM total']);
      expect(m.metrics.single.value, '2.0 GB');
    });

    test('formatMetric rejects non-numbers and formats byte scales', () {
      expect(MoavCli.formatMetric('load1', 'NaN?'), isNull);
      expect(MoavCli.formatMetric('disk_free_bytes', '1023')!.value, '1023 B');
      expect(MoavCli.formatMetric('disk_free_bytes', '1536')!.value, '1.5 KB');
      expect(MoavCli.formatMetric('rx_bytes_per_s', '104857600')!.value, '100 MB');
      expect(MoavCli.formatMetric('rx_bytes_per_s', '1')!.unit, '/s');
      expect(MoavCli.formatMetric('custom_metric', '7')!.name, 'custom_metric');
    });
  });

  group('parseUpdateCheck', () {
    test('2.2.x offline box: current version known, latest unknown', () {
      final c = MoavCli.parseUpdateCheck(fixture('doctor_updates_2_2_offline.txt'))!;
      expect(c.updateAvailable, isFalse);
      expect(c.currentVersion, '2.2.2');
      expect(c.latestVersion, isNull);
      expect(c.unknown, isTrue);
      expect(c.message, contains('cannot reach GitHub'));
    });

    test('a json document without the updates check carries no version', () {
      expect(MoavCli.parseUpdateCheck(jsonFixture('doctor_env.json')), isNull);
    });

    test('"Up to date" alone supplies both versions', () {
      final c = MoavCli.parseUpdateCheck('✓ Up to date (v2.3.1)')!;
      expect(c.currentVersion, '2.3.1');
      expect(c.latestVersion, '2.3.1');
      expect(c.updateAvailable, isFalse);
    });

    test('the available version stops at the parenthesis', () {
      final c = MoavCli.parseUpdateCheck(
        '○ Update available: v2.4.0 (current: v2.3.1)',
      )!;
      expect(c.latestVersion, '2.4.0');
      expect(c.updateAvailable, isTrue);
      expect(c.message, 'Update available: v2.4.0');
    });
  });

  group('parseHostInfo', () {
    test('an Alpine box: no nproc, busybox df, no git, 2.2 banner', () {
      final info = MoavCli.parseHostInfo(fixture('host_info_alpine.txt'));
      final h = info.host;
      expect(h.cpuCount, isNull);
      expect(h.cpuUsage, closeTo(15 / 35, 1e-9));
      expect(h.load1, 0.08);
      expect(h.memTotalBytes, 999424 * 1024);
      expect(h.swapTotalBytes, isNull);
      expect(h.swapUsage, isNull);
      expect(h.diskTotalBytes, 10190100 * 1024);
      expect(h.diskAvailableBytes, 6600000 * 1024);
      expect(h.diskUsage, closeTo(1 - 6600000 / 10190100, 1e-9));
      expect(h.uptime, const Duration(seconds: 12346));
      expect(h.isEmpty, isFalse);
      expect(info.version.moavVersion, '2.2.2');
      expect(info.version.branch, isNull);
      expect(info.version.commit, isNull);
      expect(info.version.components, isEmpty);
    });

    test('a missing second CPU sample and garbage uptime', () {
      final raw = '__LOAD__\n1.5 1.0 0.5 2/300 99\n__NPROC__\n4\n'
          '__CPU1__\ncpu 1 2 3 4 5 6 7 8 0 0\n'
          '__MEM__\nMemTotal: 2048 kB\nMemAvailable: 1024 kB\n'
          '__UPTIME__\ngarbage\n__END__\n';
      final h = MoavCli.parseHostInfo(raw).host;
      expect(h.cpuCount, 4);
      expect(h.cpuUsage, isNull);
      expect(h.load1, 1.5);
      expect(h.memUsage, 0.5);
      expect(h.uptime, isNull);
      expect(h.diskTotalBytes, isNull);
    });

    test('an empty answer is empty, and the controller refuses it', () async {
      final info = MoavCli.parseHostInfo('');
      expect(info.host.isEmpty, isTrue);
      expect(info.version.moavVersion, isNull);
    });
  });

  group('parseBundleDump', () {
    test('names with spaces, an empty file, bad base64 and a cut tail', () {
      final files = MoavCli.parseBundleDump(
        '__FILE__ my config.txt\n${_b64('hello')}\n'
        '__FILE__ empty.txt\n\n'
        '__FILE__ broken.txt\n!!!not-base64!!!\n'
        '__FILE__ reality.txt\n${_b64('vless://x@h:443')}\n'
        '__FILE__ cut.txt\n__END__\n',
      )!;
      expect(files.map((f) => f.name), ['my config.txt', 'empty.txt', 'reality.txt']);
      expect(files[0].content, 'hello');
      expect(files[1].content, '');
      expect(files[2].content, 'vless://x@h:443');
    });

    test('a __NOBUNDLE__ anywhere wins over stray file frames', () {
      expect(MoavCli.parseBundleDump('__NOBUNDLE__\n__END__\n'), isNull);
      expect(MoavCli.parseBundleDump('   __NOBUNDLE__   \n'), isNull);
    });

    test('images and the guide are dropped even if the shell printed them', () {
      expect(MoavCli.bundleEntry('reality.png', 'x'), isNull);
      expect(MoavCli.bundleEntry('guide.HTML', 'x'), isNull);
      expect(MoavCli.bundleEntry('bundle.zip', 'x'), isNull);
      final odd = MoavCli.bundleEntry('notes.readme', 'plain')!;
      expect(odd.protocol, 'notes');
      expect(odd.qrPayload, isNull);
      expect(odd.title, 'notes');
      // A QR-capable file with blank content gets no payload.
      expect(MoavCli.bundleEntry('reality.txt', '  \n')!.qrPayload, isNull);
    });
  });

  group('parsePing', () {
    test('coloured banner, missing version and an empty shell', () {
      final ok = SshMoavController.parsePing(
        '__ok__\n\x1b[0;36mMoaV\x1b[0m v2.3.1\nmore\n',
      );
      expect(ok.moavInstalled, isTrue);
      expect(ok.moavVersion, '2.3.1');

      final noVersion = SshMoavController.parsePing(
        '__ok__\nbash: moav: Permission denied\n',
      );
      expect(noVersion.moavInstalled, isTrue);
      expect(noVersion.moavVersion, isNull);

      final empty = SshMoavController.parsePing('');
      expect(empty.reachable, isTrue);
      expect(empty.moavInstalled, isNull);
      expect(empty.error, isNotNull);
    });
  });

  group('parseInstallStatus', () {
    test('a finished job: the exit marker wins over liveness', () {
      final s = SshMoavController.parseInstallStatus(
        'ALIVE\n__LOG__\n[moav-deploy] step 2/5: Bootstrap\n'
        'done\n[moav-deploy] exit=0\n',
      );
      expect(s.phase, InstallPhase.succeeded);
      expect(s.progress, 1.0);
      expect(s.logTail.last, '[moav-deploy] exit=0');
    });

    test('a garbled exit marker on a dead job reads as failed', () {
      final s = SshMoavController.parseInstallStatus(
        'DEAD\n__LOG__\n[moav-deploy] step 1/5: Preflight\n[moav-deploy] exit=abc\n',
      );
      expect(s.phase, InstallPhase.failed);
      expect(s.progress, 0.2);
      expect(s.message, contains('without reporting'));
    });

    test('the update job counts its steps out of three', () {
      final s = SshMoavController.parseInstallStatus(
        'ALIVE\n__LOG__\n[moav-deploy] step 2/3: Run moav update\n',
        totalSteps: 3,
      );
      expect(s.phase, InstallPhase.running);
      expect(s.progress, closeTo(2 / 3, 1e-9));
      expect(s.message, 'Run moav update');
    });
  });
}

String _b64(String s) => base64Encode(utf8.encode(s));
