@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// M4 live checks against a real MoaV box. Read-only except for one
/// throwaway `zzmoavdeploytest<pid>` user that is created, connectivity
/// tested with `moav test --json`, and revoked. Services are never
/// started/stopped/restarted and users are never regenerated here.
///
///   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root \
///     flutter test test/live/live_operate_test.dart
void main() {
  final env = Platform.environment;
  final host = env['MOAV_TEST_HOST'];
  final user = env['MOAV_TEST_USER'];
  var keyPath = env['MOAV_TEST_SSH_KEY'];
  final enabled = host != null && user != null && keyPath != null;
  if (keyPath != null && keyPath.startsWith('~/')) {
    keyPath = '${env['HOME']}/${keyPath.substring(2)}';
  }
  final port = int.tryParse(env['MOAV_TEST_PORT'] ?? '') ?? 22;
  final skip = enabled ? null : 'MOAV_TEST_* env not set';

  final testUser = 'zzmoavdeploytest${pid % 100000}';
  late final SshMoavController controller;
  var created = false;

  setUpAll(() {
    if (!enabled) return;
    final keyPem = File(keyPath!).readAsStringSync();
    controller = SshMoavController(
      profile: ServerProfile(
        id: 'live',
        label: host,
        host: host,
        port: port,
        username: user,
        authMethod: SshAuthMethod.importedKey,
      ),
      secretResolver: (_) async => keyPem,
    );
  });

  tearDownAll(() async {
    if (!enabled) return;
    try {
      if (created) {
        final now = await controller.listUsers();
        if (now.any((u) => u.name == testUser)) {
          await controller.removeUser(testUser);
        }
      }
    } finally {
      controller.dispose();
    }
  });

  test('doctor reports per-check health', () async {
    final r = await controller.doctor();
    // ignore: avoid_print
    print(r.checks.map((c) => '${c.name}=${c.result.name}').join(' '));
    expect(r.checks.length, greaterThanOrEqualTo(8));
    final names = r.checks.map((c) => c.name).toSet();
    expect(names, containsAll(['docker', 'services', 'ports', 'config']));
    for (final c in r.checks) {
      expect(c.detail, isNotEmpty, reason: c.name);
    }
    expect(r.checks.firstWhere((c) => c.name == 'docker').result, CheckResult.pass);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('status parses the service table and dashboard URLs', () async {
    final s = await controller.status();
    // ignore: avoid_print
    print('v${s.version} running=${s.runningCount}/${s.services.length} '
        'grafana=${s.grafanaUrl} admin=${s.adminUrl}');
    expect(s.version, matches(RegExp(r'^\d+\.\d+')));
    expect(s.services.length, greaterThan(5));
    expect(s.runningCount, greaterThan(0));
    expect(s.services.map((x) => x.name), contains('sing-box'));
    expect(s.grafanaUrl, isNotNull);
    expect(s.grafanaUrl!.scheme, 'https');
    expect(s.adminUrl, isNotNull);
    expect(s.defaultProfiles, isNotEmpty);
    final running = s.services.firstWhere((x) => x.state == ServiceState.running);
    expect(running.uptime, isNotNull);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('monitoring: grafana health + headline metrics', () async {
    final m = await controller.monitoring();
    // ignore: avoid_print
    print('grafana=${m.grafanaUrl} healthy=${m.grafanaHealthy} '
        'v=${m.grafanaVersion} metrics=${m.metrics.map((x) => '${x.name}: ${x.value}${x.unit ?? ''}').join(', ')}');
    expect(m.grafanaUrl, isNotNull);
    expect(m.grafanaUrl!.port, 9444);
    expect(m.adminUrl, isNotNull);
    expect(m.grafanaHealthy, isTrue);
    expect(m.grafanaVersion, isNotNull);
    expect(m.metrics.map((x) => x.name),
        containsAll(['Exporters up', 'Load (1m)', 'RAM available']));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('moav test --json on a throwaway user gives a protocol matrix',
      () async {
    await controller.addUser(testUser);
    created = true;
    final t = await controller.testUser(testUser);
    // ignore: avoid_print
    print('overall=${t.overall?.name} '
        '${t.results.map((r) => '${r.protocol}=${r.result.name}').join(' ')}');
    expect(t.user, testUser);
    expect(t.results.length, greaterThanOrEqualTo(8));
    expect(t.overall, isNotNull);
    expect(t.results.map((r) => r.protocol), contains('reality'));
    expect(t.count(CheckResult.pass), greaterThan(0));
    for (final r in t.results) {
      expect(r.detail, isNotNull, reason: r.protocol);
    }
    await controller.removeUser(testUser);
    created = false;
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));
}
