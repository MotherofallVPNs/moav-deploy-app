import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/demo_moav_controller.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/features/operate/chart_panels.dart';

/// The demo server: every operation emulated in memory, deterministic, and
/// never touching SSH, the secure store or the network.

class _Clock {
  var now = DateTime(2026, 11, 10, 9);
  void advance(Duration d) => now = now.add(d);
}

DemoMoavController _demo(_Clock clock) =>
    DemoMoavController(now: () => clock.now, delay: (_) async {});

ServiceState _state(ServiceStatusReport r, String name) =>
    r.services.firstWhere((s) => s.name == name).state;

void main() {
  test('factory hands the demo profile a DemoMoavController, no secret read',
      () {
    var resolved = 0;
    final factory = MoavControllerFactory(secretResolver: (_) async {
      resolved++;
      return 'never';
    });
    expect(factory.forServer(ServerProfile.demo), isA<DemoMoavController>());
    expect(
      factory.forServer(const ServerProfile(
        id: 'r',
        label: 'Real',
        host: 'h',
        port: 22,
        username: 'root',
        authMethod: SshAuthMethod.password,
      )),
      isA<SshMoavController>(),
    );
    expect(resolved, 0);
  });

  test('profile isDemo survives JSON and copyWith; old JSON reads as real', () {
    final json = ServerProfile.demo.toJson();
    expect(json['isDemo'], isTrue);
    expect(ServerProfile.fromJson(json).isDemo, isTrue);
    expect(ServerProfile.demo.copyWith(label: 'x').isDemo, isTrue);
    final legacy = Map<String, Object?>.from(json)..remove('isDemo');
    expect(ServerProfile.fromJson(legacy).isDemo, isFalse);
  });

  test('ping: reachable, not installed until the emulated install finishes',
      () async {
    final clock = _Clock();
    final c = _demo(clock);
    final before = await c.ping();
    expect(before.reachable, isTrue);
    expect(before.moavInstalled, isFalse);
    expect(before.moavVersion, isNull);
  });

  test('install: phased progress on a compressed timeline, exit=0 at the end',
      () async {
    final clock = _Clock();
    final c = _demo(clock);
    final handle = await c.install(const InstallSpec(
      domain: DemoMoavController.installDomain,
      email: 'info@demo.example.org',
      adminPassword: DemoMoavController.installPassword,
    ));
    expect(handle.jobId, 'demo-install');

    final s0 = await c.installStatus(handle);
    expect(s0.phase, InstallPhase.running);
    expect(s0.step, 1);
    expect(s0.totalSteps, 4);
    expect(s0.progressIsExact, isTrue);
    expect(s0.progress, closeTo(0, 0.001));
    expect(s0.logTail.first, '[moav-deploy] step 1/4: Preflight');

    clock.advance(const Duration(seconds: 3));
    final s2 = await c.installStatus(handle);
    expect(s2.step, 2);
    expect(s2.message, contains('installer'));
    expect(s2.progress, inExclusiveRange(0.02, 0.22));
    expect(s2.logTail, contains("Domain: demo.example.org (Let's Encrypt email set)"));

    clock.advance(const Duration(seconds: 7));
    final s3 = await c.installStatus(handle);
    expect(s3.step, 3);
    expect(s3.progress, inExclusiveRange(0.22, 0.92));
    expect(s3.phase, InstallPhase.running);
    expect((await c.ping()).moavInstalled, isFalse);

    clock.advance(const Duration(seconds: 7));
    final s4 = await c.installStatus(handle);
    expect(s4.step, 4);
    expect(s4.progress, inExclusiveRange(0.92, 0.99));

    clock.advance(const Duration(seconds: 5));
    final done = await c.installStatus(handle);
    expect(done.phase, InstallPhase.succeeded);
    expect(done.isTerminal, isTrue);
    expect(done.progress, 1.0);
    expect(done.message, 'Install finished');
    expect(done.logTail.last, '[moav-deploy] exit=0');
    // Monotonic: every poll moved the bar forward.
    expect(s2.progress!, greaterThan(s0.progress!));
    expect(s3.progress!, greaterThan(s2.progress!));
    expect(s4.progress!, greaterThan(s3.progress!));

    final after = await c.ping();
    expect(after.moavInstalled, isTrue);
    expect(after.moavVersion, DemoMoavController.installedVersion);
  });

  test('install: domainless spec logs domainless mode', () async {
    final clock = _Clock();
    final c = _demo(clock);
    final h = await c.install(const InstallSpec(
      domain: '',
      email: '',
      adminPassword: 'twelve-chars-long',
    ));
    clock.advance(const Duration(seconds: 30));
    final done = await c.installStatus(h);
    expect(done.logTail.join('\n'), contains('domainless mode'));
    expect(done.logTail.join('\n'), isNot(contains("Let's Encrypt")));
  });

  test('installStatus without an install reports unknown', () async {
    final c = _demo(_Clock());
    final s = await c.installStatus(
      const InstallHandle(jobId: 'x', logPath: 'y'),
    );
    expect(s.phase, InstallPhase.unknown);
  });

  test('users: list, add (sorted), duplicate and invalid rejected, remove',
      () async {
    final c = _demo(_Clock());
    final users = await c.listUsers();
    expect(users.map((u) => u.name), ['alice', 'bob', 'family-tablet', 'office-laptop']);
    expect(users.every((u) => u.bundleReady), isTrue);
    expect(users.first.protocols, contains('sing-box'));

    final dave = await c.addUser('dave');
    expect(dave.name, 'dave');
    expect(dave.bundleReady, isTrue);
    expect((await c.listUsers()).map((u) => u.name), contains('dave'));
    expect(
      (await c.listUsers()).map((u) => u.name).toList(),
      ['alice', 'bob', 'dave', 'family-tablet', 'office-laptop'],
    );

    expect(() => c.addUser('dave'), throwsA(isA<AppError>()));
    expect(() => c.addUser('bad name!'), throwsA(isA<AppError>()));

    await c.removeUser('dave');
    expect((await c.listUsers()).map((u) => u.name), isNot(contains('dave')));
    expect(() => c.removeUser('nobody'), throwsA(isA<AppError>()));
  });

  test('bundle: upstream file names, QR payloads in the app formats', () async {
    final c = _demo(_Clock());
    final b = await c.getBundle('alice');
    expect(b.user, 'alice');
    expect(b.path, '/opt/moav/outputs/bundles/alice');
    expect(b.entries, isNotEmpty);
    // Images and the HTML guide are not surfaced, like the real bundle.
    expect(b.entries.map((e) => e.fileName), isNot(contains('README.html')));
    expect(b.entries.map((e) => e.fileName), isNot(contains('reality.png')));
    // Phone-friendly links first, as the bundle screen sorts them.
    expect(b.entries.first.protocol, 'subscription');
    final qr = b.withQr.toList();
    expect(qr.length, greaterThanOrEqualTo(8));
    for (final e in qr) {
      expect(e.qrPayload, isNotEmpty);
      // Links are one line; WireGuard confs are whole files, like upstream.
      if (!e.fileName.endsWith('.conf')) {
        expect(e.qrPayload, isNot(contains('\n')), reason: e.fileName);
      }
    }
    final sub = b.entries.firstWhere((e) => e.protocol == 'subscription');
    final links = utf8.decode(base64.decode(sub.qrPayload!)).split('\n');
    expect(links.first, startsWith('vless://'));
    expect(links, contains(startsWith('hysteria2://')));
    expect(links, contains(startsWith('trojan://')));
    expect(links, contains(startsWith('ss://')));
    final reality = b.entries.firstWhere((e) => e.protocol == 'reality');
    expect(reality.qrPayload, contains('security=reality'));
    expect(reality.qrPayload, contains('@203.0.113.10:443'));
    final wg = b.entries.firstWhere((e) => e.protocol == 'wireguard');
    expect(wg.fileName, 'alice-wg.conf');
    expect(wg.content, contains('[Interface]'));
    expect(wg.content, contains('[Peer]'));
    expect(wg.content, contains('synthetic keys'));
    expect(wg.qrPayload, isNotNull);
    final tg = b.entries.firstWhere((e) => e.protocol == 'telegram');
    expect(tg.qrPayload, startsWith('tg://proxy?server=demo.example.org'));
    final tt = b.entries.firstWhere((e) => e.protocol == 'trusttunnel');
    expect(tt.qrPayload, isNull);
    expect(jsonDecode(tt.content), isA<Map<String, Object?>>());
    expect(await c.getBundleArchive('alice'), isNull);
    expect(() => c.getBundle('nobody'), throwsA(isA<AppError>()));
  });

  test('bundle material is deterministic per user and differs between users',
      () {
    final a1 = DemoMoavController.demoBundleFiles('alice');
    final a2 = DemoMoavController.demoBundleFiles('alice');
    final b = DemoMoavController.demoBundleFiles('bob');
    expect(a1, a2);
    expect(a1.map((f) => f.$1), b.map((f) => f.$1.replaceAll('bob', 'alice')));
    expect(a1.firstWhere((f) => f.$1 == 'reality.txt').$2,
        isNot(b.firstWhere((f) => f.$1 == 'reality.txt').$2));
  });

  test('service: stop -> stopped, start -> starting -> running, with output',
      () async {
    final clock = _Clock();
    late DemoMoavController c;
    final seen = <ServiceState>[];
    var probing = false;
    // Each emulated wait peeks at the table, so the intermediate state the
    // UI would see mid-action is recorded.
    Future<void> probe(Duration _) async {
      if (probing) return;
      probing = true;
      seen.add(_state(await c.status(), 'sing-box'));
      probing = false;
    }

    c = DemoMoavController(now: () => clock.now, delay: probe);
    expect(_state(await c.status(), 'sing-box'), ServiceState.running);

    final out = <String>[];
    await c.service(
      const ServiceAction(ServiceActionKind.stop, service: 'sing-box'),
      onOutput: out.add,
    );
    expect(_state(await c.status(), 'sing-box'), ServiceState.stopped);
    expect(out.join(), contains('Stopping moav-sing-box'));
    expect(out.join(), contains('Container moav-sing-box  Stopped'));
    expect(out.every((l) => l.endsWith('\n')), isTrue);

    seen.clear();
    out.clear();
    await c.service(
      const ServiceAction(ServiceActionKind.start, service: 'sing-box'),
      onOutput: out.add,
    );
    expect(seen, contains(ServiceState.starting));
    expect(_state(await c.status(), 'sing-box'), ServiceState.running);
    expect(out.join(), contains('Container moav-sing-box  Started'));

    final report = await c.status();
    expect(report.runningCount, greaterThan(10));
    expect(report.version, '2.3.1');
    expect(report.services.map((s) => s.state).toSet().length, greaterThan(2),
        reason: 'mixed states in the table');
  });

  test('service: restart, stop all, start all, unknown service', () async {
    final c = _demo(_Clock());
    await c.service(const ServiceAction(ServiceActionKind.restart, service: 'xray'));
    expect(_state(await c.status(), 'xray'), ServiceState.running);

    await c.service(ServiceAction.stop);
    final stopped = await c.status();
    expect(stopped.runningCount, 0);
    expect(_state(stopped, 'gooserelay'), ServiceState.never);

    await c.service(ServiceAction.start);
    final started = await c.status();
    expect(_state(started, 'sing-box'), ServiceState.running);
    expect(_state(started, 'grafana'), ServiceState.running);
    expect(_state(started, 'gooserelay'), ServiceState.never);
    expect(_state(started, 'certbot'), ServiceState.exited);

    expect(
      () => c.service(const ServiceAction(ServiceActionKind.stop, service: 'nope')),
      throwsA(isA<AppError>()),
    );
  });

  test('service: enable/disable flip .env flags and move the row', () async {
    final c = _demo(_Clock());
    expect((await c.serviceFlags()).isOn('ENABLE_GOOSERELAY'), isFalse);
    final out = <String>[];
    await c.service(
      const ServiceAction(ServiceActionKind.enable, service: 'gooserelay'),
      onOutput: out.add,
    );
    expect(out.join(), contains('ENABLE_GOOSERELAY=true'));
    expect((await c.serviceFlags()).isOn('ENABLE_GOOSERELAY'), isTrue);
    expect(_state(await c.status(), 'gooserelay'), ServiceState.running);

    await c.service(const ServiceAction(ServiceActionKind.disable, service: 'gooserelay'));
    expect((await c.serviceFlags()).isOn('ENABLE_GOOSERELAY'), isFalse);
    expect(_state(await c.status(), 'gooserelay'), ServiceState.stopped);
  });

  test('regenerate users names every user in the output', () async {
    final c = _demo(_Clock());
    final out = <String>[];
    await c.service(ServiceAction.regenerateUsers, onOutput: out.add);
    final text = out.join();
    for (final u in await c.listUsers()) {
      expect(text, contains(u.name));
    }
  });

  test('doctor, monitoring, metrics, charts and server info are realistic',
      () async {
    final c = _demo(_Clock());
    final doctor = await c.doctor();
    expect(doctor.checks.length, 15);
    expect(doctor.healthy, isTrue);
    expect(
      doctor.checks.firstWhere((x) => x.name == 'updates').result,
      CheckResult.warn,
    );
    expect(doctor.checks.first.detail, startsWith('Check Docker'));

    final mon = await c.monitoring();
    expect(mon.grafanaHealthy, isTrue);
    expect(mon.grafanaVersion, isNotNull);
    expect(mon.grafanaUrl, isNull, reason: 'nothing to open in a browser');
    expect(mon.adminUrl, isNotNull);

    final metrics = await c.metrics();
    expect(metrics.metrics.map((m) => m.name), containsAll([
      'Exporters up',
      'Load (1m)',
      'RAM available',
      'RAM total',
      'Inbound',
      'Outbound',
      'Disk free',
    ]));

    final charts = await c.metricSeries();
    final cpu = charts.named('cpu_percent').single;
    expect(cpu.points.length, 61);
    expect(cpu.points.every((p) => p.value >= 0 && p.value <= 100), isTrue);
    expect(cpu.points.first.time.isBefore(cpu.points.last.time), isTrue);
    expect(charts.named('exporters_up').length, 7);
    expect(charts.named('exporters_up').every((s) => s.label != null), isTrue);
    expect(chartPanels(charts).map((p) => p.key), ['cpu', 'mem', 'net', 'users']);
    expect(exporterHealth(charts).every((e) => e.up), isTrue);

    final info = await c.serverInfo();
    expect(info.host.cpuCount, 2);
    expect(info.host.memUsage, inExclusiveRange(0.2, 0.4));
    expect(info.host.diskUsage, inExclusiveRange(0.1, 0.3));
    expect(info.version.moavVersion, '2.3.1');
    expect(info.version.components, isNotEmpty);
  });

  test('update: available, detached job finishes, then up to date', () async {
    final clock = _Clock();
    final c = _demo(clock);
    expect(await c.updateStatus(), isNull);
    final check = await c.checkForUpdates();
    expect(check.updateAvailable, isTrue);
    expect(check.latestVersion, '2.3.2');
    expect(check.message, 'Update available: v2.3.2');

    await c.startUpdate();
    final running = await c.updateStatus();
    expect(running!.phase, InstallPhase.running);
    expect(running.step, 1);
    expect(running.totalSteps, 3);

    clock.advance(const Duration(seconds: 3));
    expect((await c.updateStatus())!.step, 2);
    // Starting again re-attaches instead of restarting the timeline.
    await c.startUpdate();
    expect((await c.updateStatus())!.step, 2);

    clock.advance(const Duration(seconds: 6));
    final done = await c.updateStatus();
    expect(done!.phase, InstallPhase.succeeded);
    expect(done.logTail.last, '[moav-deploy] exit=0');
    expect((await c.checkForUpdates()).updateAvailable, isFalse);
    expect((await c.serverInfo()).version.moavVersion, '2.3.2');
    expect((await c.status()).version, '2.3.2');
  });

  test('web UIs: access is readable, the tunnel is refused with a demo note',
      () async {
    final c = _demo(_Clock());
    expect((await c.adminPanelAccess()).port, 9443);
    expect((await c.grafanaAccess()).port, 9444);
    await expectLater(
      c.openTunnel(9444),
      throwsA(isA<AppError>()
          .having((e) => e.kind, 'kind', AppErrorKind.unreachable)
          .having((e) => e.message, 'message', contains('Grafana'))
          .having((e) => e.hint, 'hint', contains('demo'))),
    );
    await expectLater(
      c.openTunnel(9443),
      throwsA(isA<AppError>()
          .having((e) => e.message, 'message', contains('admin dashboard'))),
    );
  });

  test('dns and public ip use documentation values and pass', () async {
    final c = _demo(_Clock());
    expect(await c.publicIp(), '203.0.113.10');
    final r = await c.checkDns(domain: 'demo.example.org', serverIp: '203.0.113.10');
    expect(r.checks.length, 6);
    expect(r.ready, isTrue);
    expect(r.tool, 'dig');
  });

  test('donate: key presence, validation, submit creates users and configs',
      () async {
    final c = _demo(_Clock());
    expect((await c.donateEnv()).mahsaNetKeyPresent, isFalse);
    final status = await c.donateStatus();
    expect(status.mahsaNet.configured, isFalse);
    expect(status.conduit.running, isTrue);
    expect(status.snowflake.served, isNotNull);
    expect(await c.donateList(), isEmpty);
    expect(() => c.donateConfigs(count: 1), throwsA(isA<AppError>()));

    expect(() => c.saveMahsaNetKey('short'), throwsA(isA<AppError>()));
    final out = <String>[];
    await c.saveMahsaNetKey('demo-key-12345', onOutput: out.add);
    expect(out.join(), contains('accepted'));
    expect((await c.donateEnv()).mahsaNetKeyPresent, isTrue);

    final result = await c.donateConfigs(count: 2, onOutput: out.add);
    expect(result.usersCreated, 2);
    expect(result.donated, 6);
    expect((await c.donateList()).length, 6);
    expect((await c.listUsers()).map((u) => u.name), contains('mahsa-1'));
    expect((await c.donateStatus()).mahsaNet.total, 6);
  });

  test('reset returns every mutable thing to the baseline', () async {
    final clock = _Clock();
    final c = _demo(clock);
    final h = await c.install(const InstallSpec(
      domain: 'demo.example.org',
      email: 'info@demo.example.org',
      adminPassword: DemoMoavController.installPassword,
    ));
    clock.advance(const Duration(seconds: 30));
    await c.installStatus(h);
    await c.addUser('dave');
    await c.service(const ServiceAction(ServiceActionKind.stop, service: 'xray'));
    expect((await c.ping()).moavInstalled, isTrue);

    c.reset();
    expect((await c.ping()).moavInstalled, isFalse);
    expect((await c.listUsers()).length, 4);
    expect(_state(await c.status(), 'xray'), ServiceState.running);
    expect((await c.installStatus(h)).phase, InstallPhase.unknown);
  });
}
