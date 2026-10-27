import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// Records every command; answers with the first matching [responses] entry
/// (a substring of the command) or an empty success.
class _Box {
  _Box([this.responses = const {}]);

  final Map<String, SshOutput> responses;
  final ran = <String>[];

  Future<SshOutput> run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    ran.add(command);
    var out = const SshOutput(stdout: '', stderr: '', exitCode: 0);
    for (final e in responses.entries) {
      if (command.contains(e.key)) {
        out = e.value;
        break;
      }
    }
    if (!allowFailure && out.exitCode != 0) {
      throw SshCommandException(command, out);
    }
    return out;
  }
}

SshMoavController _controllerFor(_Box box) => SshMoavController(
      profile: const ServerProfile(
        id: 't',
        label: 't',
        host: 'h',
        port: 22,
        username: 'root',
        authMethod: SshAuthMethod.importedKey,
      ),
      secretResolver: (_) async => throw StateError('no ssh in unit tests'),
      runner: box.run,
    );

const verb = '"\$M"';

void main() {
  group('start / stop / restart', () {
    test('run the exact moav verb with the service name', () async {
      final box = _Box();
      final c = _controllerFor(box);
      await c.service(const ServiceAction(ServiceActionKind.start, service: 'wireguard'));
      await c.service(const ServiceAction(ServiceActionKind.stop, service: 'sing-box'));
      await c.service(const ServiceAction(ServiceActionKind.restart, service: 'telemt'));
      await c.service(ServiceAction.restart);
      expect(box.ran.map((r) => r.substring(MoavCli.prelude.length)), [
        "$verb start 'wireguard' 2>&1",
        "$verb stop 'sing-box' 2>&1",
        "$verb restart 'telemt' 2>&1",
        '$verb restart 2>&1',
      ]);
    });

    test('a non-zero exit surfaces the CLI text as the cause', () async {
      final box = _Box({
        "start 'wireguard'": const SshOutput(
          stdout: "⚠ Profile 'wireguard' is disabled in .env.\n"
              'ℹ Non-interactive shell, skipping \'wireguard\'.\n✗ No service selected\n',
          stderr: '',
          exitCode: 1,
        ),
      });
      Object? caught;
      try {
        await _controllerFor(box).service(
            const ServiceAction(ServiceActionKind.start, service: 'wireguard'));
      } on Object catch (e) {
        caught = e;
      }
      final err = AppError.from(caught!);
      expect(err.kind, AppErrorKind.commandFailed);
      expect(err.message, contains('exit 1'));
      expect(err.detail, contains("Profile 'wireguard' is disabled in .env"));
    });

    test('service names are validated before they reach the shell', () async {
      final box = _Box();
      await expectLater(
        _controllerFor(box).service(
            const ServiceAction(ServiceActionKind.stop, service: 'a;rm -rf /')),
        throwsArgumentError,
      );
      expect(box.ran, isEmpty);
    });
  });

  group('enable / disable', () {
    test('enable writes the flag, then moav start <service>', () async {
      final box = _Box();
      await _controllerFor(box)
          .service(const ServiceAction(ServiceActionKind.enable, service: 'wireguard'));
      expect(box.ran, hasLength(2));
      expect(box.ran[0], contains('set_env ENABLE_WIREGUARD true'));
      expect(box.ran[0], isNot(contains('false')));
      expect(box.ran[0], contains("grep -E '^(ENABLE_WIREGUARD)=' .env"));
      expect(box.ran[1], endsWith("$verb start 'wireguard' 2>&1"));
    });

    test('disable writes every flag false, then moav stop <service>', () async {
      final box = _Box();
      await _controllerFor(box)
          .service(const ServiceAction(ServiceActionKind.disable, service: 'sing-box'));
      expect(box.ran, hasLength(2));
      for (final f in [
        'ENABLE_REALITY',
        'ENABLE_TROJAN',
        'ENABLE_HYSTERIA2',
        'ENABLE_SS',
        'ENABLE_SNELL',
        'ENABLE_ANYTLS',
      ]) {
        expect(box.ran[0], contains('set_env $f false'));
      }
      expect(box.ran[0], isNot(contains(' true')));
      expect(box.ran[1], endsWith("$verb stop 'sing-box' 2>&1"));
    });

    test('monitoring containers share ENABLE_MONITORING', () async {
      final box = _Box();
      await _controllerFor(box)
          .service(const ServiceAction(ServiceActionKind.enable, service: 'grafana'));
      expect(box.ran[0], contains('set_env ENABLE_MONITORING true'));
      expect(box.ran[1], endsWith("$verb start 'grafana' 2>&1"));
    });

    test('a failed .env write stops before moav start runs', () async {
      final box = _Box({
        'set_env': const SshOutput(stdout: '.env is not writable\n', stderr: '', exitCode: 1),
      });
      Object? caught;
      try {
        await _controllerFor(box)
            .service(const ServiceAction(ServiceActionKind.enable, service: 'telemt'));
      } on Object catch (e) {
        caught = e;
      }
      expect(AppError.from(caught!).detail, contains('.env is not writable'));
      expect(box.ran, hasLength(1));
    });

    test('support services have no flag and are refused locally', () async {
      final box = _Box();
      await expectLater(
        _controllerFor(box)
            .service(const ServiceAction(ServiceActionKind.disable, service: 'certbot')),
        throwsStateError,
      );
      await expectLater(
        _controllerFor(box).service(const ServiceAction(ServiceActionKind.enable)),
        throwsArgumentError,
      );
      expect(box.ran, isEmpty);
    });
  });

  group('serviceFlags', () {
    test('reads ENABLE_* and DEFAULT_PROFILES from .env', () async {
      final box = _Box({
        'grep -E': const SshOutput(
          stdout: 'ENABLE_WIREGUARD=false\nENABLE_TELEMT=true\n'
              'DEFAULT_PROFILES="proxy admin"\n',
          stderr: '',
          exitCode: 0,
        ),
      });
      final f = await _controllerFor(box).serviceFlags();
      expect(box.ran.single, MoavCli.serviceFlags);
      expect(f.serviceEnabled('wireguard'), isFalse);
      expect(f.serviceEnabled('telemt'), isTrue);
      expect(f.defaultProfiles, ['proxy', 'admin']);
    });

    test('a missing .env yields no flags rather than an error', () async {
      final box = _Box({
        'grep -E': const SshOutput(stdout: '', stderr: '', exitCode: 1),
      });
      final f = await _controllerFor(box).serviceFlags();
      expect(f.values, isEmpty);
    });
  });
}
