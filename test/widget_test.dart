import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_key_installer.dart';
import 'package:moav_deploy/features/servers/add_server_form.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';

/// In-memory stand-in so tests never touch platform channels.
class _FakeCredStore implements SecureCredStore {
  List<ServerProfile> profiles = [];
  final Map<String, String> secrets = {};
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
  Future<void> writeInstallHandle(String id, Map<String, Object?> json) async =>
      installHandles[id] = json;
  @override
  Future<Map<String, Object?>?> readInstallHandle(String id) async =>
      installHandles[id];
  @override
  Future<void> deleteInstallHandle(String id) async =>
      installHandles.remove(id);
  @override
  Future<void> wipeAll() async {
    profiles = [];
    secrets.clear();
    installHandles.clear();
  }
}

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

  @override
  Future<ConnectionCheck> ping() async =>
      const ConnectionCheck(reachable: true, moavInstalled: true, moavVersion: '2.2.2');

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeFactory extends MoavControllerFactory {
  _FakeFactory(this.controller) : super(secretResolver: (_) async => null);

  final MoavController controller;

  @override
  MoavController forServer(ServerProfile profile) => controller;
}

Widget _app(_FakeCredStore store, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

const _profile = ServerProfile(
  id: 's1',
  label: 'York',
  host: 'yorkschool.example',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.importedKey,
);

void main() {
  testWidgets('home shows empty state and opens add-server form',
      (tester) async {
    await tester.pumpWidget(_app(_FakeCredStore()));
    await tester.pumpAndSettle();

    expect(find.text('No servers yet'), findsOneWidget);

    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Generate key'), findsOneWidget);
  });

  testWidgets('saving a password-auth server lists it and stores the secret',
      (tester) async {
    final store = _FakeCredStore();
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

    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    expect(find.text('vpn.example.org'), findsOneWidget);
    expect(store.profiles.single.authMethod, SshAuthMethod.password);
    expect(store.secrets.values.single, 'hunter2');
  });

  testWidgets('generate key, install it with a one-time password, save',
      (tester) async {
    final store = _FakeCredStore();
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
    await tester.ensureVisible(find.text('Install key on server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install key on server'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not install key'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Server password (one-time)'), 'pw');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Install key on server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install key on server'));
    await tester.pumpAndSettle();

    expect(find.text('Installed on the server'), findsOneWidget);
    expect(installs.single, startsWith('root@h.example:22 pw=pw key=ssh-ed25519 '));

    await tester.ensureVisible(find.text('Save server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    final saved = store.profiles.single;
    expect(saved.authMethod, SshAuthMethod.generatedKey);
    expect(store.secrets[saved.id], startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    // The one-time password is never persisted.
    expect(store.secrets.values.any((s) => s.contains('pw=')), isFalse);
  });

  testWidgets('test connection reports the MoaV version', (tester) async {
    final store = _FakeCredStore()..profiles = [_profile];
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

  testWidgets('deploy screen starts a detached install and streams the log',
      (tester) async {
    final store = _FakeCredStore()..profiles = [_profile];
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

    await tester.tap(find.text('York'));
    await tester.pumpAndSettle();
    expect(find.text('Start install'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Domain'), 'vpn.example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Admin dashboard password'), 'secret');
    await tester.tap(find.text('Start install'));
    await tester.pump();
    await tester.pump();

    expect(controller.installedSpec?.domain, 'vpn.example.org');
    expect(store.installHandles['s1']?['jobId'], '4242');
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('[moav-deploy] step 1/5: Preflight'), findsOneWidget);

    // Next poll reports completion and polling stops.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('[moav-deploy] exit=0'), findsOneWidget);
    expect(find.text('Start another install'), findsOneWidget);
    final callsAtDone = controller.statusCalls;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.statusCalls, callsAtDone);

    await tester.tap(find.text('Start another install'));
    await tester.pumpAndSettle();
    expect(store.installHandles, isEmpty);
    expect(find.text('Start install'), findsOneWidget);
  });

  testWidgets('deploy screen re-attaches to a saved job on open',
      (tester) async {
    final store = _FakeCredStore()
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
    await tester.tap(find.text('York'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Bootstrap'), findsOneWidget);
    expect(find.text('Start install'), findsNothing);
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
}
