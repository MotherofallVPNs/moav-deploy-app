import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_key_installer.dart';
import 'package:moav_deploy/features/servers/add_server_form.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/memory_cred_store.dart';

class _FakeKeyInstaller extends SshKeyInstaller {
  const _FakeKeyInstaller(this.log);

  final List<String> log;

  @override
  Future<void> install({
    required String host,
    required int port,
    required String username,
    String? password,
    String? authPrivateKeyPem,
    required String publicKeyLine,
    required String privateKeyPem,
  }) async {
    if (password == 'wrong') throw StateError('Authentication failed');
    log.add('$username@$host:$port pw=$password key=$publicKeyLine');
  }
}

/// Scripted controller: each `installStatus` call pops the next status.
class _FakeController implements MoavController {
  _FakeController(this.statuses);

  final List<InstallStatus> statuses;
  InstallSpec? installedSpec;
  int statusCalls = 0;

  /// Thrown by the next controller call, then cleared (fault injection).
  Object? nextError;

  void _maybeFail() {
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
  }
  final users = <MoavUser>[
    const MoavUser(name: 'alice', bundleReady: true, protocols: ['sing-box']),
    const MoavUser(name: 'bob'),
  ];
  final log = <String>[];

  /// Returned by [ping] when set; otherwise a healthy MoaV 2.2.2 box.
  ConnectionCheck? pingResult;

  @override
  Future<ConnectionCheck> ping() async =>
      pingResult ??
      const ConnectionCheck(reachable: true, moavInstalled: true, moavVersion: '2.2.2');

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    _maybeFail();
    installedSpec = spec;
    return const InstallHandle(jobId: '4242', logPath: '.moav-deploy/deploy.log');
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async {
    expect(handle.jobId, '4242');
    final i = statusCalls < statuses.length ? statusCalls : statuses.length - 1;
    statusCalls++;
    return statuses[i];
  }

  @override
  Future<List<MoavUser>> listUsers() async {
    _maybeFail();
    return List.of(users);
  }

  @override
  Future<MoavUser> addUser(String name) async {
    log.add('add $name');
    final u = MoavUser(name: name, bundleReady: true);
    users.add(u);
    return u;
  }

  @override
  Future<void> removeUser(String name) async {
    log.add('remove $name');
    users.removeWhere((u) => u.name == name);
  }

  @override
  Future<Bundle> getBundle(String user) async {
    _maybeFail();
    log.add('bundle $user');
    if (!users.any((u) => u.name == user)) throw StateError('No bundle');
    return Bundle(
      user: user,
      fetchedAt: DateTime(2026),
      path: '/opt/moav/outputs/bundles/$user',
      entries: [
        BundleEntry(
          protocol: 'reality',
          fileName: 'reality.txt',
          content: 'vless://$user@h:443\n',
          qrPayload: 'vless://$user@h:443',
        ),
        const BundleEntry(
          protocol: 'trusttunnel',
          fileName: 'trusttunnel.toml',
          content: '# tt',
        ),
        BundleEntry(
          protocol: 'subscription',
          fileName: 'subscription.txt',
          content: 'c3Vic2NyaXB0aW9uLWZvci0k$user\n',
          qrPayload: 'c3Vic2NyaXB0aW9uLWZvci0k$user',
        ),
      ],
    );
  }

  @override
  Future<DoctorReport> doctor() async => DoctorReport(
        collectedAt: DateTime(2026, 9, 14, 8),
        checks: const [
          DoctorCheck(name: 'docker', result: CheckResult.pass, detail: 'Check Docker\n✓ Docker 29 - running'),
          DoctorCheck(name: 'host', result: CheckResult.warn, detail: 'Check CPU load\n! 929 MiB swapped out'),
          DoctorCheck(name: 'services', result: CheckResult.fail, detail: 'Check services\n✗ sing-box - not running'),
        ],
      );

  @override
  Future<ServiceStatusReport> status() async {
    _maybeFail();
    return _status();
  }

  ServiceStatusReport _status() => ServiceStatusReport(
        collectedAt: DateTime(2026),
        version: '2.2.2',
        defaultProfiles: const ['proxy', 'admin'],
        grafanaUrl: Uri.parse('https://example.org:9444'),
        services: const [
          ServiceStatus(name: 'sing-box', state: ServiceState.running, uptime: '7 days', ports: ['443']),
          ServiceStatus(name: 'certbot', state: ServiceState.exited),
        ],
      );

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    onOutput?.call('${action.kind.name} ${action.service ?? 'all'}: ok\n');
    log.add('service ${action.kind.name} ${action.service}');
  }

  int monitoringCalls = 0;
  int metricsCalls = 0;
  int serverInfoCalls = 0;

  /// Completes the next [metrics] call only when resolved by the test.
  Completer<MetricsSnapshot>? metricsGate;

  @override
  Future<Monitoring> monitoring() async {
    _maybeFail();
    monitoringCalls++;
    return Monitoring(
      grafanaUrl: Uri.parse('https://example.org:9444'),
      adminUrl: Uri.parse('https://example.org:9443'),
      grafanaHealthy: true,
      grafanaVersion: '13.1.3',
      collectedAt: DateTime(2026, 9, 14, 8),
    );
  }

  /// Thrown by the next [metrics] call only, then cleared.
  Object? nextMetricsError;

  /// The charts section has its own cache; empty here so the tab tests
  /// above stay about metrics, Grafana health and protocol status.
  @override
  Future<ChartsSnapshot> metricSeries() async =>
      ChartsSnapshot(series: const [], collectedAt: DateTime(2026, 9, 14, 8));

  @override
  Future<MetricsSnapshot> metrics() async {
    _maybeFail();
    metricsCalls++;
    final me = nextMetricsError;
    if (me != null) {
      nextMetricsError = null;
      throw me;
    }
    final gate = metricsGate;
    if (gate != null) return gate.future;
    return MetricsSnapshot(
      collectedAt: DateTime(2026, 9, 14, 8),
      metrics: const [
        Metric(name: 'Load (1m)', value: '1.18'),
        Metric(name: 'Inbound', value: '33 B', unit: '/s'),
      ],
    );
  }

  @override
  Future<ServerInfo> serverInfo() async {
    _maybeFail();
    serverInfoCalls++;
    return ServerInfo(
      collectedAt: DateTime(2026, 9, 14, 8),
      host: const HostMetrics(
        cpuCount: 2,
        cpuUsage: 0.42,
        load1: 2.3,
        load5: 1.9,
        load15: 1.7,
        memTotalBytes: 2057842688,
        memAvailableBytes: 698351616,
        swapTotalBytes: 2147479552,
        swapFreeBytes: 1036640256,
        diskTotalBytes: 61255049216,
        diskAvailableBytes: 43789910016,
        uptime: Duration(days: 80, hours: 3),
      ),
      version: const VersionInfo(
        moavVersion: '2.3.0',
        branch: 'dev',
        commit: 'e218483',
        components: [
          ComponentVersion(name: 'sing-box', version: '1.14.3', source: 'github.com/SagerNet/sing-box'),
          ComponentVersion(name: 'xray-core', version: 'v26.10.21', source: 'github.com/XTLS/Xray-core'),
        ],
      ),
    );
  }

  UpdateCheck updateCheck = UpdateCheck(
    updateAvailable: true,
    checkedAt: DateTime(2026, 9, 14, 8),
    currentVersion: '2.3.0',
    latestVersion: '2.3.1',
    message: 'Update available: v2.3.1',
  );

  @override
  Future<UpdateCheck> checkForUpdates() async {
    _maybeFail();
    log.add('check updates');
    return updateCheck;
  }

  /// Statuses returned by successive [updateStatus] calls after [startUpdate].
  List<InstallStatus> updateStatuses = const [];
  int updateStatusCalls = 0;
  bool updateStarted = false;

  @override
  Future<void> startUpdate() async {
    _maybeFail();
    log.add('start update');
    updateStarted = true;
    updateStatusCalls = 0;
  }

  @override
  Future<InstallStatus?> updateStatus() async {
    if (!updateStarted || updateStatuses.isEmpty) return null;
    final i = updateStatusCalls < updateStatuses.length
        ? updateStatusCalls
        : updateStatuses.length - 1;
    updateStatusCalls++;
    return updateStatuses[i];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeFactory extends MoavControllerFactory {
  _FakeFactory(this.controller) : super(secretResolver: (_) async => null);

  final MoavController controller;

  @override
  MoavController forServer(ServerProfile profile) => controller;
}

Widget _app(MemoryCredStore store, {List<Override> overrides = const []}) =>
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

const _profile = ServerProfile(
  id: 's1',
  label: 'Demo',
  host: 'demo.example.org',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.importedKey,
);

/// Scrolls the current page's ListView until [f] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder f, {double delta = 120}) async {
  await tester.scrollUntilVisible(
    f,
    delta,
    scrollable: find
        .descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first,
  );
  // scrollUntilVisible ends with ensureVisible but no frame; lay it out.
  await tester.pumpAndSettle();
}

/// Pumps a few frames; for screens with a spinner that must keep spinning.
Future<void> _pumpFor(WidgetTester tester, [int ms = 400]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

void main() {
  testWidgets('home shows empty state and opens add-server form',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()));
    await tester.pumpAndSettle();

    expect(find.text('No servers yet'), findsOneWidget);

    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Generate key'), findsOneWidget);
  });

  testWidgets('saving a password-auth server lists it and stores the secret',
      (tester) async {
    final store = MemoryCredStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Host'), 'vpn.example.org');
    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'hunter2');
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Save server'));
    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    expect(find.text('vpn.example.org'), findsOneWidget);
    expect(store.profiles.single.authMethod, SshAuthMethod.password);
    expect(store.secrets.values.single, 'hunter2');
  });

  testWidgets('generate key, install it with a one-time password, save',
      (tester) async {
    final store = MemoryCredStore();
    final installs = <String>[];
    await tester.pumpWidget(_app(
      store,
      overrides: [
        keyInstallerProvider.overrideWithValue(_FakeKeyInstaller(installs)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Host'), 'h.example');
    await tester.tap(find.text('Generate key'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Generate ed25519 key'));
    await tester.tap(find.text('Generate ed25519 key'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ssh-ed25519 AAAA'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Install key on server'),
      ).onPressed,
      isNull,
      reason: 'needs a one-time password first',
    );

    await tester.enterText(
        find.widgetWithText(TextField, 'Server password (one-time)'), 'wrong');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Install key on server'));
    await tester.tap(find.text('Install key on server'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.textContaining('Could not install key'));
    expect(find.textContaining('Could not install key'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Server password (one-time)'), 'pw');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Install key on server'));
    await tester.tap(find.text('Install key on server'));
    await tester.pumpAndSettle();

    expect(find.text('Installed on the server'), findsOneWidget);
    expect(installs.single, startsWith('root@h.example:22 pw=pw key=ssh-ed25519 '));

    await _scrollTo(tester, find.text('Save server'));
    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    final saved = store.profiles.single;
    expect(saved.authMethod, SshAuthMethod.generatedKey);
    expect(store.secrets[saved.id], startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    // The one-time password is never persisted.
    expect(store.secrets.values.any((s) => s.contains('pw=')), isFalse);
  });

  testWidgets('test connection reports the MoaV version', (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const []);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected. MoaV 2.2.2 is installed.'), findsOneWidget);
  });

  testWidgets('editing a server keeps its saved credential', (tester) async {
    final store = MemoryCredStore()
      ..profiles = [_profile]
      ..secrets[_profile.id] = 'private-key';
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Host'), 'fixed.example');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(store.profiles.single.host, 'fixed.example');
    expect(store.secrets[_profile.id], 'private-key');
  });

  testWidgets('deploy screen starts a detached install and streams the log',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [
      InstallStatus(
        phase: InstallPhase.running,
        progress: 0.2,
        message: 'Preflight',
        logTail: ['[moav-deploy] step 1/5: Preflight'],
      ),
      InstallStatus(
        phase: InstallPhase.succeeded,
        progress: 1,
        message: 'Install finished',
        logTail: [
          '[moav-deploy] step 1/5: Preflight',
          '[moav-deploy] step 5/5: Start services',
          '[moav-deploy] exit=0',
        ],
      ),
    ]);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    expect(find.text('Users'), findsOneWidget);
    await _scrollTo(tester, find.text('Deploy'));
    await tester.tap(find.text('Deploy'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Domain'), 'vpn.example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Admin dashboard password'), 'secret');
    // The service selection sits between the inputs and the button.
    await _scrollTo(tester, find.text('Start install'));
    expect(find.text('Start install'), findsOneWidget);
    await tester.tap(find.text('Start install'));
    await tester.pump();
    await tester.pump();

    expect(controller.installedSpec?.domain, 'vpn.example.org');
    expect(store.installHandles['s1']?['jobId'], '4242');
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('[moav-deploy] step 1/5: Preflight'), findsOneWidget);

    // Next poll reports completion and polling stops.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('[moav-deploy] exit=0'), findsOneWidget);
    expect(find.text('Start another install'), findsOneWidget);
    final callsAtDone = controller.statusCalls;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.statusCalls, callsAtDone);

    await tester.tap(find.text('Start another install'));
    await tester.pumpAndSettle();
    expect(store.installHandles, isEmpty);
    await _scrollTo(tester, find.text('Start install'));
    expect(find.text('Start install'), findsOneWidget);
  });

  testWidgets('deploy screen re-attaches to a saved job on open',
      (tester) async {
    final store = MemoryCredStore()
      ..profiles = [_profile]
      ..installHandles['s1'] = {'jobId': '4242', 'logPath': 'x'};
    final controller = _FakeController(const [
      InstallStatus(phase: InstallPhase.running, message: 'Bootstrap'),
    ]);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Deploy'));
    await tester.tap(find.text('Deploy'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Bootstrap'), findsOneWidget);
    expect(find.text('Start install'), findsNothing);
  });

  // Regression: `a ?? b || c` groups as `a ?? (b || c)`, so with a non-null
  // status the unknown-phase branch was never reached and the user had no
  // way to start over after the server-side job vanished.
  testWidgets('deploy screen offers a new install when the job phase is unknown',
      (tester) async {
    final store = MemoryCredStore()
      ..profiles = [_profile]
      ..installHandles['s1'] = {'jobId': '4242', 'logPath': 'x'};
    final controller = _FakeController(const [
      InstallStatus(
        phase: InstallPhase.unknown,
        message: 'No job with that id on the server',
      ),
    ]);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Deploy'));
    await tester.tap(find.text('Deploy'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Start another install'), findsOneWidget);
  });

  testWidgets('users: list, open bundle with QR, add and revoke',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const []);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.textContaining('Bundle ready'), findsOneWidget);

    // Tapping a row opens the detail view: protocols, subscription and
    // bundle. It fetches the bundle; there is no connectivity test anymore.
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    expect(find.text('BUNDLE READY'), findsOneWidget);
    expect(find.text('SING-BOX'), findsOneWidget);
    expect(find.text('Copy subscription'), findsOneWidget);
    expect(find.text('Download connection bundle'), findsOneWidget);
    expect(find.text('Run connection test'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(controller.log, ['bundle alice']);

    // Copy puts the subscription blob on the clipboard.
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await tester.tap(find.text('Copy subscription'));
    await tester.pumpAndSettle();
    expect(clipboard, ['c3Vic2NyaXB0aW9uLWZvci0kalice']);
    expect(find.text('Subscription copied'), findsOneWidget);

    // Bundle screen renders a QR per link and lists the rest.
    await tester.tap(find.text('Download connection bundle'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNWidgets(2));
    expect(find.text('VLESS Reality'), findsOneWidget);
    await _scrollTo(tester, find.text('TrustTunnel'));
    expect(find.text('TrustTunnel'), findsOneWidget);
    expect(controller.log, ['bundle alice']);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Add: validation, then creation navigates to the new bundle.
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'bad name');
    await tester.pumpAndSettle();
    expect(find.text('Letters, numbers, _ and - only'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add')).onPressed,
      isNull,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'carol');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(controller.log, contains('add carol'));
    expect(find.text('carol'), findsOneWidget); // bundle screen title
    expect(find.byType(QrImageView), findsNWidgets(2));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('carol'), findsOneWidget);

    // Revoke with confirmation.
    await tester.tap(find.byIcon(Icons.person_remove_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Revoke carol?'), findsOneWidget);
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(controller.log, contains('remove carol'));
    expect(find.text('carol'), findsNothing);
    expect(controller.users.map((u) => u.name), ['alice', 'bob']);
  });

  testWidgets('operate: services with confirmed restart, health, monitoring',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const []);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('MoaV v2.2.2'), findsOneWidget);
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);

    // Restart all asks first; cancel does nothing.
    await tester.tap(find.text('Restart all'));
    await tester.pumpAndSettle();
    expect(find.text('Restart all services?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.log, isNot(contains(startsWith('service'))));

    // Per-service stop goes through after confirmation.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sing-box?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(controller.log, contains('service stop sing-box'));
    expect(find.text('Stop sing-box done'), findsOneWidget);

    // Start all needs no confirmation.
    await tester.tap(find.text('Start all'));
    await tester.pumpAndSettle();
    expect(controller.log, contains('service start null'));

    // Health tab shows doctor checks with the failing one flagged.
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    expect(find.text('1 check failing'), findsOneWidget);
    expect(find.text('docker'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsWidgets);
    await tester.tap(find.text('services'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sing-box - not running'), findsOneWidget);

    // Analytics tab shows Grafana health, URL, metrics and protocol status.
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Grafana 13.1.3 is up'), findsOneWidget);
    expect(find.text('https://example.org:9444'), findsOneWidget);
    expect(find.text('LOAD (1M)'), findsOneWidget);
    expect(find.text('33 B/s'), findsOneWidget);
    // Protocol pills come from the status report (sing-box → reality etc.).
    await _scrollTo(tester, find.text('REALITY'));
    expect(find.text('HYSTERIA2'), findsOneWidget);
    // Native charts section (empty series here) sits between them.
    await _scrollTo(tester, find.text('LAST HOUR'));
    await _scrollTo(tester, find.text('Admin dashboard'));
    expect(find.text('Admin dashboard'), findsOneWidget);
  });

  testWidgets('users screen: timeout shows a hint and Retry recovers',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..nextError = TimeoutException('listUsers');
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(find.text('The server did not respond in time.'), findsOneWidget);
    expect(find.textContaining('Check the connection'), findsOneWidget);
    expect(find.text('alice'), findsNothing);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('bundle screen: failed command shows exit code, never the secret',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const []);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    controller.nextError = SshCommandException(
      'cat bundle',
      const SshOutput(
        stdout: 'ADMIN_PASSWORD="hunter2"\nvless://abc@h:443#x',
        stderr: '',
        exitCode: 2,
      ),
    );
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();

    // The detail view shows the failure inline next to its Retry; the rest
    // of the screen (bundle and test buttons) stays usable.
    expect(find.text('The command failed on the server (exit 2).'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Download connection bundle'), findsOneWidget);
    await tester.tap(find.text('Download connection bundle'));
    await tester.pumpAndSettle();

    expect(find.text('The command failed on the server (exit 2).'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining('vless://abc'), findsNothing);
    expect(find.textContaining('[redacted]'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNWidgets(2));
  });

  testWidgets('services tab: unreachable host shows Retry; deploy shows a banner',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..nextError = const SocketException(
        'Connection failed',
        osError: OSError('Connection refused', 61),
      );
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('Connection refused by the server.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('sing-box'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    controller.nextError = const SocketException(
      'Failed host lookup',
      osError: OSError('nodename nor servname provided, or not known', 8),
    );
    await _scrollTo(tester, find.text('Deploy'));
    await tester.tap(find.text('Deploy'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Start install'));
    await tester.tap(find.text('Start install'));
    await tester.pumpAndSettle();
    expect(find.text('Could not find the server.'), findsOneWidget);
    expect(find.textContaining('Check the hostname'), findsOneWidget);
    await _scrollTo(tester, find.text('Start install'));
    expect(find.text('Start install'), findsOneWidget); // form stays, can retry
  });

  testWidgets('add server defaults to Saved key and preselects the newest key',
      (tester) async {
    final store = MemoryCredStore()
      ..sshKeys = [
        StoredSshKey(
          id: 'k-old',
          label: 'Old laptop key',
          publicKey: 'ssh-ed25519 AAAAOLD old',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        StoredSshKey(
          id: 'k-new',
          label: 'Phone key',
          publicKey: 'ssh-ed25519 AAAANEW phone',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ]
      ..sshKeySecrets['k-old'] = 'pem-old'
      ..sshKeySecrets['k-new'] = 'pem-new';
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    // Four cards, one selected, and it is Saved key.
    expect(find.text('Saved key'), findsOneWidget);
    expect(find.text('Generate key'), findsOneWidget);
    expect(find.text('Import key'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
    expect(find.text('Device key'), findsOneWidget);
    expect(find.text('Phone key'), findsOneWidget);
    expect(find.textContaining('AAAANEW'), findsOneWidget);

    // Host plus the preselected key is enough to save.
    await tester.enterText(
        find.widgetWithText(TextField, 'Host'), ' ssh://root@Example.Org:22/ ');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Save server'));
    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    final saved = store.profiles.single;
    expect(saved.host, 'example.org');
    expect(saved.label, 'example.org');
    expect(store.secrets[saved.id], 'pem-new');
  });

  testWidgets('add server with an empty keyring offers to generate instead',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    expect(find.text('No reusable keys yet.'), findsOneWidget);
    await _scrollTo(tester, find.text('Generate a key instead'));
    await tester.tap(find.text('Generate a key instead'));
    await tester.pumpAndSettle();
    expect(find.text('Generate ed25519 key'), findsOneWidget);

    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('test connection failure names the cause in a quiet snackbar',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..pingResult = ConnectionCheck(
        reachable: false,
        error: 'Could not find demo.example.org:22.',
        failure: AppError.from(
          const SocketException(
            'Failed host lookup',
            osError: OSError('No address associated with hostname', 7),
          ),
          host: 'demo.example.org',
          port: 22,
        ),
      );
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect. Could not find demo.example.org:22.'),
        findsOneWidget);
    expect(find.textContaining('Check the hostname'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('server hub: Check connection shows the cause inline',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..pingResult = ConnectionCheck(
        reachable: false,
        error: 'Authentication failed.',
        failure: AppError.from(SSHAuthFailError('rejected')),
      );
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();

    expect(find.text('Not checked yet'), findsOneWidget);
    await tester.tap(find.text('Check connection'));
    await tester.pumpAndSettle();
    expect(find.text('Authentication failed.'), findsOneWidget);
    expect(find.textContaining('rejected the key or password'), findsOneWidget);
    expect(find.byIcon(Icons.key_off), findsOneWidget);

    controller.pingResult = null;
    await tester.tap(find.text('Check connection'));
    await tester.pumpAndSettle();
    expect(find.text('Connected. MoaV 2.2.2 is installed.'), findsOneWidget);
  });

  test('form normalises pasted connect strings before dialling', () {
    const pasted = AddServerFormState(
      host: ' ssh://root@Example.Org:22/ ',
      authChoice: AuthChoice.password,
      password: 'p',
    );
    expect(pasted.hostError, isNull);
    expect(pasted.normalizedHost, 'example.org');
    expect(pasted.toProfile('x').host, 'example.org');

    const junk = AddServerFormState(host: 'not a host', authChoice: AuthChoice.password, password: 'p');
    expect(junk.hostError, isNotNull);
  });

  test('form validation', () {
    const empty = AddServerFormState();
    expect(empty.isValid, isFalse);
    expect(empty.hostError, isNotNull);

    const ok = AddServerFormState(
      host: 'h',
      authChoice: AuthChoice.password,
      password: 'p',
    );
    expect(ok.isValid, isTrue);
    expect(ok.toProfile('x').label, 'h');

    const badPort = AddServerFormState(host: 'h', port: '70000');
    expect(badPort.portError, isNotNull);
  });

  testWidgets('analytics: slow metrics never block the tab and survive a tab switch',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..metricsGate = Completer<MetricsSnapshot>();
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analytics'));
    await _pumpFor(tester);

    // Grafana and protocols render while Prometheus is still being queried.
    expect(find.text('Grafana 13.1.3 is up'), findsOneWidget);
    expect(find.textContaining('Querying Prometheus'), findsOneWidget);
    expect(find.text('LOAD (1M)'), findsNothing);
    expect(controller.metricsCalls, 1);

    // Switching away and back keeps the cached cards and the one fetch.
    await tester.tap(find.widgetWithText(Tab, 'Health'));
    await _pumpFor(tester);
    expect(find.text('1 check failing'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Analytics'));
    await _pumpFor(tester);
    expect(find.text('Grafana 13.1.3 is up'), findsOneWidget);
    expect(controller.metricsCalls, 1);
    expect(controller.monitoringCalls, 1);

    // The slow query lands and fills the grid in place.
    controller.metricsGate!.complete(MetricsSnapshot(
      collectedAt: DateTime(2026, 9, 14, 8, 5),
      metrics: const [Metric(name: 'Load (1m)', value: '2.15')],
    ));
    controller.metricsGate = null;
    await tester.pumpAndSettle();
    expect(find.text('LOAD (1M)'), findsOneWidget);
    expect(find.text('2.15'), findsOneWidget);

    // The app bar refresh re-fetches every section of the open tab.
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.refresh),
    ));
    await tester.pumpAndSettle();
    expect(controller.metricsCalls, 2);
    expect(controller.monitoringCalls, 2);
  });

  testWidgets('analytics: metrics timeout shows the cause with Retry, grafana stays',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..nextMetricsError = TimeoutException('prometheus');
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();

    expect(find.text('Grafana 13.1.3 is up'), findsOneWidget);
    expect(find.text('The server did not respond in time.'), findsOneWidget);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('The server did not respond in time.'), findsNothing);
    expect(find.text('LOAD (1M)'), findsOneWidget);
    expect(controller.metricsCalls, 2);
  });

  testWidgets('services tab: a failed refresh keeps the last result and offers Retry',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const []);
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('sing-box'), findsOneWidget);

    controller.nextError = TimeoutException('status');
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.refresh),
    ));
    await tester.pumpAndSettle();
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.textContaining('Showing the last result.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing the last result.'), findsNothing);
    expect(find.text('sing-box'), findsOneWidget);
  });

  testWidgets('server tab: host metrics, versions, check for updates and confirmed update',
      (tester) async {
    final store = MemoryCredStore()..profiles = [_profile];
    final controller = _FakeController(const [])
      ..updateStatuses = const [
        InstallStatus(
          phase: InstallPhase.running,
          progress: 2 / 3,
          message: 'Run moav update',
          logTail: ['[moav-deploy] step 2/3: Run moav update', 'Pulling latest changes...'],
        ),
        InstallStatus(
          phase: InstallPhase.succeeded,
          progress: 1,
          message: 'Install finished',
          logTail: ['Updated: e218483 -> f00ba47', '[moav-deploy] exit=0'],
        ),
      ];
    await tester.pumpWidget(_app(
      store,
      overrides: [
        moavControllerFactoryProvider.overrideWithValue(_FakeFactory(controller)),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Server info'));
    await tester.tap(find.text('Server info'));
    await tester.pumpAndSettle();

    expect(find.text('MoaV v2.3.0'), findsOneWidget);
    expect(find.text('dev @ e218483'), findsOneWidget);
    expect(find.text('Not checked yet'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('2 vCPU, 1 s sample'), findsOneWidget);
    expect(find.text('RAM'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
    expect(find.text('DISK'), findsOneWidget);
    expect(find.text('29%'), findsOneWidget);
    await _scrollTo(tester, find.text('xray-core'));
    expect(find.text('v26.10.21'), findsOneWidget);
    expect(controller.serverInfoCalls, 1);

    // Check for updates: verdict plus an Update button.
    await _scrollTo(tester, find.text('Check for updates'), delta: -120);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(controller.log, contains('check updates'));
    expect(find.text('Update available: v2.3.1'), findsOneWidget);
    expect(find.text('Update to v2.3.1'), findsOneWidget);

    // Update asks first; cancel starts nothing.
    await tester.tap(find.text('Update to v2.3.1'));
    await tester.pumpAndSettle();
    expect(find.text('Update MoaV to v2.3.1?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.log, isNot(contains('start update')));

    // Confirmed: the job starts and its log streams until done. Bounded
    // pumps: the spinning activity indicator would let pumpAndSettle poll.
    await tester.tap(find.text('Update to v2.3.1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await _pumpFor(tester);
    expect(controller.log, contains('start update'));
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.textContaining('Pulling latest changes'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('DONE'), findsOneWidget);
    expect(find.textContaining('f00ba47'), findsOneWidget);
    // Success re-reads versions and forgets the stale verdict.
    expect(controller.serverInfoCalls, 2);
    expect(find.text('Update to v2.3.1'), findsNothing);
    await _scrollTo(tester, find.text('Dismiss'));
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('DONE'), findsNothing);
  });
}
