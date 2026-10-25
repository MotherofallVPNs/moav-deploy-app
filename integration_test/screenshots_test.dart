// Demo screenshot gallery. Drives the real app (biometric lock bypassed) on a
// simulator and hands PNGs to `test_driver/integration_test.dart`.
//
//   tool/screenshots.sh                       # yorkschool-shaped fake data
//   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=yorkschool.xyz \
//   MOAV_TEST_USER=root tool/screenshots.sh   # real box over SSH
//
// Live mode is read-only apart from one throwaway `zzmoavdeploytest*` user
// created for the bundle/QR shot and revoked at the end. Existing users,
// services and config are never touched.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _host = String.fromEnvironment('MOAV_TEST_HOST');
const _user = String.fromEnvironment('MOAV_TEST_USER', defaultValue: 'root');
const _port = int.fromEnvironment('MOAV_TEST_PORT', defaultValue: 22);
const _keyB64 = String.fromEnvironment('MOAV_TEST_SSH_KEY_B64');
const live = _host != '' && _keyB64 != '';

const yorkschool = ServerProfile(
  id: 'york',
  label: 'yorkschool',
  host: live ? _host : 'yorkschool.xyz',
  port: _port,
  username: _user,
  authMethod: SshAuthMethod.generatedKey,
);

const frankfurt = ServerProfile(
  id: 'fra',
  label: 'Frankfurt',
  host: 'fra1.moav.example',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.password,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'demo gallery',
    (tester) async {
      final store = _MemoryCredStore()
        ..profiles = [yorkschool, frankfurt]
        ..secrets['york'] = live ? utf8.decode(base64Decode(_keyB64)) : 'x'
        ..secrets['fra'] = 'x';
      final fake = _FakeController();
      final MoavController york = live
          ? SshMoavController(
              profile: yorkschool,
              secretResolver: (_) async => store.secrets['york'],
            )
          : fake;
      final throwaway =
          'zzmoavdeploytest${DateTime.now().millisecondsSinceEpoch % 100000}';

      await tester.pumpWidget(ProviderScope(
        retry: noProviderRetry,
        overrides: [
          secureCredStoreProvider.overrideWithValue(store),
          moavControllerFactoryProvider.overrideWithValue(
            _GalleryFactory(york: york, other: fake),
          ),
        ],
        child: const MoavDeployApp(lockEnabled: false),
      ));
      await tester.pumpAndSettle();

      try {
        // 1. Servers list.
        await _wait(tester, find.text('yorkschool'));
        await _shot(binding, tester, '01-servers');

        // 2. Add server + on-device key generation.
        await tester.tap(find.text('Add server'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Label (optional)'), 'Amsterdam');
        await tester.enterText(find.widgetWithText(TextField, 'Host'), 'ams1.example.net');
        await _blur(tester);
        await tester.tap(find.text('Generate ed25519 key'));
        await _wait(tester, find.textContaining('ssh-ed25519 AAAA'));
        await _scrollTo(tester, find.text('Install key on server'));
        await _shot(binding, tester, '02-add-server-keygen');
        await tester.pageBack();
        await tester.pumpAndSettle();

        // 3. Users + bundle with QR codes.
        await tester.tap(find.text('yorkschool'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Users'));
        await _wait(tester, find.byIcon(Icons.person_remove_outlined));
        await _shot(binding, tester, '03-users');

        await tester.tap(find.text('Add user'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Username'), throwaway);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add'));
        await _wait(tester, find.byType(QrImageView), timeout: const Duration(minutes: 8));
        await _blur(tester);
        await _shot(binding, tester, '03b-bundle-qr');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        // 4. Operate: services table, then doctor health.
        await tester.tap(find.text('Services'));
        await _wait(tester, find.text('sing-box'));
        await _shot(binding, tester, '04-services');
        await tester.tap(find.text('Health'));
        await _wait(tester, find.text('CHECKS'), timeout: const Duration(minutes: 3));
        await _shot(binding, tester, '04b-doctor');

        // 5. Analytics: metric tiles, then protocol matrix + embedded Grafana.
        await tester.tap(find.text('Analytics'));
        await _wait(tester, find.text('HEADLINE METRICS'));
        await _wait(tester, find.text('PROTOCOLS'));
        await _settle(tester, const Duration(seconds: 4));
        await _shot(binding, tester, '05-analytics');
        await _scrollTo(tester, find.text('Full screen'));
        await _settle(tester, const Duration(seconds: 6));
        await _shot(binding, tester, '05b-analytics-protocols-grafana');

        // 6. Grafana full screen.
        await tester.tap(find.text('Full screen'));
        await tester.pumpAndSettle();
        await _settle(tester, const Duration(seconds: 10));
        await _shot(binding, tester, '06-grafana');
      } finally {
        // Never leave the throwaway user behind on the real box.
        try {
          final now = await york.listUsers();
          if (now.any((u) => u.name == throwaway)) {
            await york.removeUser(throwaway);
          }
        } on Object catch (_) {}
        if (york is SshMoavController) york.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await _blur(tester);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await binding.takeScreenshot(name);
}

/// Dismisses the software keyboard so it never covers a shot.
Future<void> _blur(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// Pumps real time until [f] matches (network work has no scheduled frames).
Future<void> _wait(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after $timeout waiting for $f');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpAndSettle();
}

/// Lets a webview or animation finish for a fixed wall-clock time.
Future<void> _settle(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    160,
    scrollable: find
        .descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _GalleryFactory extends MoavControllerFactory {
  _GalleryFactory({required this.york, required this.other})
      : super(secretResolver: (_) async => null);

  final MoavController york;
  final MoavController other;

  @override
  MoavController forServer(ServerProfile profile) =>
      profile.id == yorkschool.id ? york : other;
}

class _MemoryCredStore implements SecureCredStore {
  List<ServerProfile> profiles = [];
  List<StoredSshKey> sshKeys = [];
  final Map<String, String> secrets = {};
  final Map<String, String> sshKeySecrets = {};
  final Map<String, Map<String, Object?>> installHandles = {};

  @override
  Future<List<ServerProfile>> loadProfiles() async => profiles;
  @override
  Future<void> saveProfiles(List<ServerProfile> p) async => profiles = p;
  @override
  Future<void> writeSecret(String id, String s) async => secrets[id] = s;
  @override
  Future<String?> readSecret(String id) async => secrets[id];
  @override
  Future<void> deleteSecret(String id) async => secrets.remove(id);
  @override
  Future<List<StoredSshKey>> loadSshKeys() async => sshKeys;
  @override
  Future<void> saveSshKeys(List<StoredSshKey> keys) async => sshKeys = keys;
  @override
  Future<void> writeSshKeySecret(String id, String pem) async => sshKeySecrets[id] = pem;
  @override
  Future<String?> readSshKeySecret(String id) async => sshKeySecrets[id];
  @override
  Future<void> deleteSshKeySecret(String id) async => sshKeySecrets.remove(id);
  @override
  Future<void> writeInstallHandle(String id, Map<String, Object?> json) async =>
      installHandles[id] = json;
  @override
  Future<Map<String, Object?>?> readInstallHandle(String id) async =>
      installHandles[id];
  @override
  Future<void> deleteInstallHandle(String id) async => installHandles.remove(id);
  @override
  Future<List<String>> listKeys() async => [...secrets.keys, ...installHandles.keys, ...sshKeySecrets.keys];
  @override
  Future<int> wipeAll() async {
    final n = profiles.length + secrets.length + installHandles.length;
    profiles = [];
    secrets.clear();
    installHandles.clear();
    sshKeys = [];
    sshKeySecrets.clear();
    return n;
  }
}

/// yorkschool-shaped data: MoaV v2.2.2, 27/29 services, Grafana 13.1.3.
class _FakeController implements MoavController {
  final users = <MoavUser>[
    const MoavUser(name: 'alice', bundleReady: true, protocols: ['sing-box', 'wireguard', 'xray', 'trusttunnel', 'telegram']),
    const MoavUser(name: 'bob', bundleReady: true, protocols: ['sing-box', 'wireguard', 'xray', 'trusttunnel', 'telegram']),
    const MoavUser(name: 'carol', bundleReady: true, protocols: ['sing-box', 'wireguard', 'xray', 'trusttunnel', 'telegram']),
    const MoavUser(name: 'dave', bundleReady: true, protocols: ['sing-box', 'xray', 'trusttunnel']),
    const MoavUser(name: 'erin', protocols: ['sing-box']),
  ];

  Future<T> _lag<T>(T v, [int ms = 350]) =>
      Future.delayed(Duration(milliseconds: ms), () => v);

  @override
  Future<ConnectionCheck> ping() => _lag(const ConnectionCheck(
        reachable: true, moavInstalled: true, moavVersion: '2.2.2'));

  @override
  Future<InstallHandle> install(InstallSpec spec) => _lag(
      const InstallHandle(jobId: '4242', logPath: '.moav-deploy/deploy.log'));

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) => _lag(
        const InstallStatus(
          phase: InstallPhase.running,
          progress: 0.6,
          message: 'Bootstrap',
          logTail: ['[moav-deploy] step 3/5: Bootstrap'],
        ),
      );

  @override
  Future<List<MoavUser>> listUsers() => _lag(List.of(users));

  @override
  Future<MoavUser> addUser(String name) async {
    final u = MoavUser(name: name, bundleReady: true, protocols: const ['sing-box', 'wireguard', 'xray', 'trusttunnel', 'telegram']);
    users.add(u);
    return _lag(u, 1200);
  }

  @override
  Future<void> removeUser(String name) async {
    users.removeWhere((u) => u.name == name);
  }

  @override
  Future<Bundle> getBundle(String user) => _lag(Bundle(
        user: user,
        fetchedAt: DateTime.now(),
        path: '/opt/moav/outputs/bundles/$user',
        entries: [
          BundleEntry(
            protocol: 'reality',
            fileName: 'reality.txt',
            content: _reality(user),
            qrPayload: _reality(user),
          ),
          BundleEntry(
            protocol: 'hysteria2',
            fileName: 'hysteria2.txt',
            content: _hy2(user),
            qrPayload: _hy2(user),
          ),
          BundleEntry(
            protocol: 'trojan',
            fileName: 'trojan.txt',
            content: _trojan(user),
            qrPayload: _trojan(user),
          ),
          BundleEntry(
            protocol: 'wireguard',
            fileName: 'wireguard.conf',
            content: _wg(user),
            qrPayload: _wg(user),
          ),
          const BundleEntry(
            protocol: 'trusttunnel',
            fileName: 'trusttunnel.toml',
            content: '# TrustTunnel client config\n',
          ),
          const BundleEntry(
            protocol: 'telegram',
            fileName: 'telegram-mtproxy.txt',
            content: 'tg://proxy?server=yorkschool.xyz&port=993&secret=ee…\n',
          ),
        ],
      ));

  static String _reality(String u) =>
      'vless://7f2a9c1e-4b3d-4e8f-9a6b-1c2d3e4f5a6b@yorkschool.xyz:443'
      '?encryption=none&flow=xtls-rprx-vision&security=reality'
      '&sni=www.microsoft.com&fp=chrome&pbk=Xq3mF9kL2pR7vT1wY6zB4nC8hJ0dS5gA2eK9uM4oP1I'
      '&sid=6ba85179e30d4fc2&type=tcp#yorkschool-reality-$u';
  static String _hy2(String u) =>
      'hysteria2://9d8c7b6a5f4e3d2c@yorkschool.xyz:8443/?sni=yorkschool.xyz'
      '&obfs=salamander&obfs-password=k2Lm9Qx4#yorkschool-hy2-$u';
  static String _trojan(String u) =>
      'trojan://1a2b3c4d5e6f7a8b@yorkschool.xyz:8445?security=tls'
      '&sni=yorkschool.xyz&type=tcp#yorkschool-trojan-$u';
  static String _wg(String u) => '[Interface]\n'
      'PrivateKey = cGxhY2Vob2xkZXJwcml2YXRla2V5MDAwMDAwMDAwMDA=\n'
      'Address = 10.66.66.104/32\nDNS = 10.66.66.1\n\n[Peer]\n'
      'PublicKey = c2VydmVycHVibGlja2V5cGxhY2Vob2xkZXIwMDAwMDA=\n'
      'Endpoint = yorkschool.xyz:51820\nAllowedIPs = 0.0.0.0/0, ::/0\n'
      'PersistentKeepalive = 25\n# $u\n';

  @override
  Future<DoctorReport> doctor() => _lag(
        DoctorReport(
          collectedAt: DateTime.now(),
          checks: const [
            DoctorCheck(name: 'docker', result: CheckResult.pass, detail: 'Check Docker and prerequisites\n✓ Docker 29.7.2 — running\n✓ Docker Compose 5.4.0'),
            DoctorCheck(name: 'memory', result: CheckResult.pass, detail: 'Check available RAM\nRAM: 1.9 GB total, 775 MB available (60% used)\n✓ Memory OK'),
            DoctorCheck(name: 'dns', result: CheckResult.fail, detail: 'Check DNS records for enabled protocols\n✓ Main A record: yorkschool.xyz\n✗ grafana.yorkschool.xyz does not resolve to the server IP'),
            DoctorCheck(name: 'services', result: CheckResult.pass, detail: 'Check running services vs enabled config\n✓ 27 services running, 2 one-shot'),
            DoctorCheck(name: 'ports', result: CheckResult.pass, detail: 'Check required ports are available\n✓ 443, 8443, 8445, 51820, 51821, 993, 53 bound by MoaV'),
            DoctorCheck(name: 'config', result: CheckResult.pass, detail: 'Validate .env and generated configs\n✓ 0 placeholder values'),
            DoctorCheck(name: 'certs', result: CheckResult.pass, detail: "Check TLS certificates\n✓ Let's Encrypt, 61 days left"),
            DoctorCheck(name: 'firewall', result: CheckResult.pass, detail: 'Check nftables rules\n✓ MoaV chain present'),
            DoctorCheck(name: 'time', result: CheckResult.pass, detail: 'Check clock sync\n✓ chrony synced, offset 2 ms'),
            DoctorCheck(name: 'disk', result: CheckResult.pass, detail: 'Check disk space\n✓ 41.2 GB free on /'),
            DoctorCheck(name: 'kernel', result: CheckResult.pass, detail: 'Check kernel tunables\n✓ BBR enabled'),
            DoctorCheck(name: 'users', result: CheckResult.pass, detail: 'Check user stores are consistent\n✓ 5 users, bundles present'),
            DoctorCheck(name: 'monitoring', result: CheckResult.pass, detail: 'Check Prometheus targets\n✓ 11 of 11 exporters up'),
            DoctorCheck(name: 'host', result: CheckResult.warn, detail: 'Check CPU load, swap pressure and zombie processes\n✓ load 4.80 on 2 vCPU\n! 929 MiB swapped out (775 MiB RAM available)\n  Swap I/O shows up as latency on every connection.'),
            DoctorCheck(name: 'updates', result: CheckResult.warn, detail: 'Check for MoaV updates\nCurrent version: v2.2.2\n○ Update available: v2.2.4\n  Run: moav update'),
          ],
        ),
        1500,
      );

  static ServiceStatus _svc(String n, {ServiceState s = ServiceState.running, String? up, List<String> ports = const []}) =>
      ServiceStatus(name: n, state: s, uptime: up, ports: ports);

  @override
  Future<ServiceStatusReport> status() => _lag(ServiceStatusReport(
        collectedAt: DateTime.now(),
        version: '2.2.2',
        adminUrl: Uri.parse('https://yorkschool.xyz:9443'),
        grafanaUrl: Uri.parse('https://yorkschool.xyz:9444'),
        grafanaCdnUrl: Uri.parse('https://grafana.yorkschool.xyz:2083'),
        defaultProfiles: const ['proxy', 'wireguard', 'amneziawg', 'dnstunnel', 'trusttunnel', 'xhttp', 'telegram', 'admin', 'conduit', 'snowflake', 'monitoring'],
        services: [
          _svc('admin', up: '3 weeks', ports: ['9443']),
          _svc('amneziawg', up: '2 weeks', ports: ['51821']),
          _svc('amneziawg-exporter', up: '4 weeks'),
          _svc('cadvisor', up: '5 weeks'),
          _svc('psiphon-conduit', up: '3 weeks'),
          _svc('decoy', up: '5 weeks', ports: ['80']),
          _svc('dns-router', up: '4 weeks', ports: ['53']),
          _svc('dnstt', up: '5 weeks'),
          _svc('docker-proxy', up: '5 weeks'),
          _svc('grafana', up: '2 weeks', ports: ['9444']),
          _svc('grafana-proxy', up: '5 weeks', ports: ['2083']),
          _svc('masterdns', up: '5 weeks'),
          _svc('node-exporter', up: '5 weeks'),
          _svc('prometheus', up: '2 weeks'),
          _svc('sing-box', up: '39 hours', ports: ['2082', '443', '8388', '8443', '8445']),
          _svc('singbox-exporter', up: '4 weeks'),
          _svc('slipstream', up: '5 weeks'),
          _svc('snowflake', up: '2 weeks'),
          _svc('snowflake-exporter', up: '2 weeks'),
          _svc('telemt', up: '39 hours', ports: ['993']),
          _svc('telemt-exporter', up: '4 weeks'),
          _svc('trusttunnel', up: '39 hours', ports: ['4443']),
          _svc('wireguard', up: '3 weeks', ports: ['51820']),
          _svc('wireguard-exporter', up: '4 weeks'),
          _svc('wstunnel', up: '4 weeks', ports: ['8080']),
          _svc('xray', up: '39 hours', ports: ['2096', '5356']),
          _svc('xray-exporter', up: '4 weeks'),
          _svc('certbot', s: ServiceState.exited),
          _svc('gooserelay', s: ServiceState.never),
        ],
      ));

  @override
  Future<void> service(ServiceAction action) => _lag(null, 800);

  @override
  Future<Monitoring> monitoring() => _lag(Monitoring(
        grafanaUrl: Uri.parse('https://yorkschool.xyz:9444'),
        grafanaCdnUrl: Uri.parse('https://grafana.yorkschool.xyz:2083'),
        adminUrl: Uri.parse('https://yorkschool.xyz:9443'),
        grafanaHealthy: true,
        grafanaVersion: '13.1.3',
        collectedAt: DateTime.now(),
        metrics: const [
          Metric(name: 'Exporters up', value: '11'),
          Metric(name: 'Load (1m)', value: '4.80'),
          Metric(name: 'RAM available', value: '775 MB'),
          Metric(name: 'RAM total', value: '1.9 GB'),
          Metric(name: 'Inbound', value: '1.2 MB', unit: '/s'),
          Metric(name: 'Outbound', value: '3.8 MB', unit: '/s'),
          Metric(name: 'Disk free', value: '41.2 GB'),
        ],
      ));

  @override
  Future<TestMatrix> testUser(String name) => _lag(TestMatrix(
        user: name,
        ranAt: DateTime.now(),
        overall: CheckResult.pass,
        results: const [
          ProtocolTest(protocol: 'reality', result: CheckResult.pass, detail: 'Connected'),
          ProtocolTest(protocol: 'hysteria2', result: CheckResult.pass, detail: 'Connected'),
          ProtocolTest(protocol: 'trojan', result: CheckResult.pass, detail: 'Connected'),
          ProtocolTest(protocol: 'shadowsocks', result: CheckResult.pass, detail: 'Connected'),
          ProtocolTest(protocol: 'xhttp', result: CheckResult.warn, detail: 'Slow handshake (2.1 s)'),
          ProtocolTest(protocol: 'wireguard', result: CheckResult.skip, detail: 'Needs a client tunnel'),
        ],
      ));
}
