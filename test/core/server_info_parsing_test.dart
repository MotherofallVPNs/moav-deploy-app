import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/operate/server_info_view.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseHostInfo', () {
    final info = MoavCli.parseHostInfo(
      fixture('host_info.txt'),
      now: DateTime(2026, 10, 27),
    );

    test('cpu, load, ram, swap, disk and uptime from /proc and df', () {
      final h = info.host;
      expect(h.cpuCount, 2);
      // Deltas: total 198, idle 57 + iowait 20 = 77, busy 121.
      expect(h.cpuUsage, closeTo(121 / 198, 1e-9));
      expect(h.load1, 2.30);
      expect(h.load5, 1.89);
      expect(h.load15, 1.74);
      expect(h.memTotalBytes, 2009612 * 1024);
      expect(h.memAvailableBytes, 681944 * 1024);
      expect(h.swapTotalBytes, 2097148 * 1024);
      expect(h.swapFreeBytes, 1012344 * 1024);
      expect(h.diskTotalBytes, 59819384 * 1024);
      expect(h.diskAvailableBytes, 42763584 * 1024);
      expect(h.uptime, const Duration(seconds: 6924555));
      expect(h.memUsage, closeTo(1 - 681944 / 2009612, 1e-9));
      expect(h.diskUsage, closeTo(1 - 42763584 / 59819384, 1e-9));
      expect(h.isEmpty, isFalse);
    });

    test('moav version, git branch/commit and the component table', () {
      final v = info.version;
      expect(v.moavVersion, '2.3.0');
      expect(v.branch, 'dev');
      expect(v.commit, 'e218483');
      expect(v.components.map((c) => c.name),
          ['sing-box', 'wstunnel', 'trusttunnel', 'xray-core', 'wireguard']);
      expect(v.components.first.version, '1.14.3');
      expect(v.components.first.source, 'github.com/SagerNet/sing-box');
      expect(v.components.last.version, 'alpine');
      expect(info.collectedAt, DateTime(2026, 10, 27));
    });

    test('text before the first marker is ignored', () {
      final s = MoavCli.sections(
        'motd banner\n__LOAD__\n1 2 3\n__END__\n',
        MoavCli.hostMarkers,
      );
      expect(s.keys, ['__LOAD__', '__END__']);
      expect(s['__LOAD__'], '1 2 3\n');
    });

    test('an empty box gives empty metrics, not a crash', () {
      final empty = MoavCli.parseHostInfo('');
      expect(empty.host.isEmpty, isTrue);
      expect(empty.host.memUsage, isNull);
      expect(empty.version.moavVersion, isNull);
      expect(empty.version.components, isEmpty);
    });
  });

  group('cpuUsageBetween', () {
    test('busy fraction over the sample', () {
      expect(
        MoavCli.cpuUsageBetween('cpu 100 0 100 700 100 0 0 0', 'cpu 150 0 150 750 150 0 0 0'),
        closeTo(0.5, 1e-9),
      );
    });

    test('identical samples or garbage give null', () {
      expect(MoavCli.cpuUsageBetween('cpu 1 2 3 4 5', 'cpu 1 2 3 4 5'), isNull);
      expect(MoavCli.cpuUsageBetween('', 'cpu 1 2 3 4 5'), isNull);
      expect(MoavCli.cpuUsageBetween('cpu a b c d e', 'cpu 1 2 3 4 5'), isNull);
    });
  });

  group('parseVersionInfo', () {
    test('2.2.x banner without a component table', () {
      final v = MoavCli.parseVersionInfo('\x1B[0;36mMoaV\x1B[0m v2.2.2\n');
      expect(v.moavVersion, '2.2.2');
      expect(v.components, isEmpty);
      expect(v.branch, isNull);
    });
  });

  group('parseUpdateCheck', () {
    final now = DateTime(2026, 10, 27, 9);

    test('json: update available', () {
      final c = MoavCli.parseUpdateCheck(fixture('json/doctor_updates.json'), now: now)!;
      expect(c.updateAvailable, isTrue);
      expect(c.currentVersion, '2.3.0');
      expect(c.latestVersion, '2.3.1');
      expect(c.message, 'Update available: v2.3.1');
      expect(c.checkedAt, now);
    });

    test('text: up to date', () {
      final c = MoavCli.parseUpdateCheck(
        'updates - Check for MoaV updates\n'
        '    Current version: \x1B[1;37mv2.3.1\x1B[0m\n'
        '    \x1B[0;32m✓\x1B[0m Up to date (v2.3.1)\n',
      )!;
      expect(c.updateAvailable, isFalse);
      expect(c.currentVersion, '2.3.1');
      expect(c.latestVersion, '2.3.1');
      expect(c.unknown, isFalse);
      expect(c.message, 'Up to date (v2.3.1)');
    });

    test('text: running ahead of the latest release', () {
      final c = MoavCli.parseUpdateCheck(
        'Current version: v2.4.0-rc.1\n✓ Running v2.4.0-rc.1 (ahead of latest release v2.3.1)\n',
      )!;
      expect(c.updateAvailable, isFalse);
      expect(c.latestVersion, '2.3.1');
      expect(c.message, contains('ahead of the latest release v2.3.1'));
    });

    test('json: lookup failed is unknown, not an update', () {
      final c = MoavCli.parseUpdateCheck(
        '[{"id": "updates", "status": "warn", "detail": "Current version: v2.3.0; ○ Could not check for updates (no internet or GitHub unreachable)"}]',
      )!;
      expect(c.updateAvailable, isFalse);
      expect(c.unknown, isTrue);
      expect(c.currentVersion, '2.3.0');
      expect(c.message, contains('cannot reach GitHub'));
    });

    test('no version anywhere gives null', () {
      expect(MoavCli.parseUpdateCheck('Unknown check: --json\n'), isNull);
      expect(MoavCli.parseUpdateCheck(''), isNull);
    });
  });

  group('hostTiles', () {
    test('one tile per reported metric, thresholds tint the value', () {
      const h = HostMetrics(
        cpuCount: 2,
        cpuUsage: 0.95,
        load1: 2.3,
        load5: 1.9,
        load15: 1.7,
        memTotalBytes: 2000 * 1024 * 1024,
        memAvailableBytes: 300 * 1024 * 1024,
        swapTotalBytes: 2048 * 1024 * 1024,
        swapFreeBytes: 1024 * 1024 * 1024,
        diskTotalBytes: 60 * 1024 * 1024 * 1024,
        diskAvailableBytes: 42 * 1024 * 1024 * 1024,
        uptime: Duration(days: 80, hours: 3),
      );
      final tiles = hostTiles(h);
      expect(tiles.map((t) => t.label), ['CPU', 'Load', 'RAM', 'Disk', 'Swap', 'Uptime']);
      expect(tiles[0].value, '95');
      expect(tiles[0].tone, StatusTone.fail);
      expect(tiles[1].tone, StatusTone.warn); // load 2.3 on 2 vCPU
      expect(tiles[2].value, '85');
      expect(tiles[2].tone, StatusTone.warn);
      expect(tiles[2].sub, '300 MB free of 2.0 GB');
      expect(tiles[3].value, '30');
      expect(tiles[3].tone, isNull);
      expect(tiles[4].value, '50');
      expect(tiles[5].value, '80d 3h');
    });

    test('metrics the box did not report are left out', () {
      expect(hostTiles(const HostMetrics()), isEmpty);
      expect(hostTiles(const HostMetrics(load1: 0.5)).single.label, 'Load');
      expect(
        hostTiles(const HostMetrics(swapTotalBytes: 0, swapFreeBytes: 0)),
        isEmpty,
      );
    });

    test('formatting helpers', () {
      expect(formatBytes(null), '?');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(43790155776), '40.8 GB');
      expect(formatUptime(const Duration(minutes: 5)), '5m');
      expect(formatUptime(const Duration(hours: 3, minutes: 7)), '3h 7m');
      expect(toneForUsage(0.79), isNull);
      expect(toneForUsage(0.8), StatusTone.warn);
      expect(toneForUsage(0.9), StatusTone.fail);
    });
  });

  test('hostInfo snippet carries every marker the parser expects', () {
    for (final m in MoavCli.hostMarkers) {
      expect(MoavCli.hostInfo, contains('echo "$m"'), reason: m);
    }
    expect(MoavCli.hostInfo, contains('sleep 1'));
    expect(MoavCli.hostInfo, contains('df -Pk /'));
  });

  test('prometheus snippet queries in parallel and prints in a fixed order', () {
    expect(MoavCli.prometheus, contains('2>/dev/null & }'));
    expect(MoavCli.prometheus, contains('wait'));
    expect(MoavCli.prometheus, contains('for n in targets_up load1'));
    expect(MoavCli.monitoring, isNot(contains('docker exec')));
  });

  test('update commands', () {
    expect(MoavCli.doctorUpdatesJson, endsWith('doctor updates --json'));
    expect(MoavCli.doctorUpdates, endsWith('doctor updates 2>&1'));
  });

  testWidgets('MetricTile renders value and unit', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: hostTiles(const HostMetrics(cpuUsage: 0.42)).single),
    ));
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
  });
}
