import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/security/app_log.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const secretKey = 'mk_live_VERYSECRETKEY_0123456789';

/// Scripts the remote box by exact command string and records every command
/// and file upload, so a test can prove where the API key did and did not go.
class FakeBox {
  FakeBox(this.responses);

  final Map<String, SshOutput> responses;
  final ran = <String>[];
  final uploads = <(String path, String content, String mode)>[];

  Future<SshOutput> run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    ran.add(command);
    final out = responses[command];
    if (out == null) throw StateError('unscripted command: $command');
    if (!allowFailure && out.exitCode != 0) {
      throw SshCommandException(command, out);
    }
    return out;
  }

  Future<void> write(String path, String content, {String mode = '600'}) async {
    uploads.add((path, content, mode));
  }
}

SshOutput ok(String stdout) => SshOutput(stdout: stdout, stderr: '', exitCode: 0);
SshOutput failed(String stdout, {int code = 1}) =>
    SshOutput(stdout: stdout, stderr: '', exitCode: code);

SshMoavController controllerFor(FakeBox box) => SshMoavController(
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
      fileWriter: box.write,
    );

void main() {
  final logged = <String>[];
  setUp(() {
    logged.clear();
    AppLog.sink = logged.add;
  });
  tearDown(() => AppLog.sink = null);

  group('donateEnv', () {
    test('present', () async {
      final box = FakeBox({
        DonateCli.env: ok('__DONATE__\nmahsanet_key=present\nprotocols=reality hysteria2\n__END__\n'),
      });
      final env = await controllerFor(box).donateEnv();
      expect(env.mahsaNetKeyPresent, isTrue);
      expect(env.protocols, ['reality', 'hysteria2']);
      expect(box.ran, [DonateCli.env]);
    });

    test('absent', () async {
      final box = FakeBox({DonateCli.env: ok('__DONATE__\nmahsanet_key=absent\n__END__\n')});
      expect((await controllerFor(box).donateEnv()).mahsaNetKeyPresent, isFalse);
    });

    test('no checkout throws', () async {
      final box = FakeBox({DonateCli.env: ok('')});
      await expectLater(controllerFor(box).donateEnv(), throwsStateError);
    });
  });

  group('donateStatus / donateList', () {
    test('status parsed from the text printout', () async {
      final box = FakeBox({DonateCli.status: ok(fixture('donate_status.txt'))});
      final s = await controllerFor(box).donateStatus();
      expect(s.mahsaNet.total, 12);
      expect(s.conduit.connected, 37);
      expect(box.ran, [DonateCli.status]);
    });

    test('status: unknown command throws', () async {
      final box = FakeBox({DonateCli.status: failed('Unknown command: donate')});
      await expectLater(controllerFor(box).donateStatus(), throwsStateError);
    });

    test('list parsed; exit 1 without a key is a StateError', () async {
      final box = FakeBox({DonateCli.list: ok(fixture('donate_list.txt'))});
      final rows = await controllerFor(box).donateList();
      expect(rows.map((r) => r.scheme), ['vless', 'hysteria2', 'vless']);

      final noKey = FakeBox({DonateCli.list: failed('✗ No donation service configured\n')});
      await expectLater(controllerFor(noKey).donateList(), throwsStateError);
    });
  });

  group('saveMahsaNetKey', () {
    test('uploads the key 0600, runs setup, never logs or echoes the key',
        () async {
      final box = FakeBox({DonateCli.setupMahsaNet: ok(fixture('donate_setup_ok.txt'))});
      final streamed = StringBuffer();
      await controllerFor(box).saveMahsaNetKey(' $secretKey \n', onOutput: streamed.write);

      expect(box.uploads, [(DonateCli.keyFile, '$secretKey\n', '600')]);
      expect(box.ran, [DonateCli.setupMahsaNet]);
      for (final c in box.ran) {
        expect(c, isNot(contains(secretKey)));
      }
      expect(streamed.toString(), contains('API key saved to .env'));
      expect(streamed.toString(), isNot(contains(secretKey)));
      expect(logged.join('\n'), isNot(contains(secretKey)));
    });

    test('rejected key: setup error surfaces, key still absent from it',
        () async {
      final box = FakeBox({
        DonateCli.setupMahsaNet: failed(
          '  API Key: ℹ Validating API key...\n✗ Invalid API key (HTTP 401)\n',
        ),
      });
      Object? error;
      try {
        await controllerFor(box).saveMahsaNetKey(secretKey);
      } on Object catch (e) {
        error = e;
      }
      expect(error, isStateError);
      expect('$error', contains('Invalid API key (HTTP 401)'));
      expect('$error', isNot(contains(secretKey)));
      // The upload still happened (setup deletes the file server-side).
      expect(box.uploads.length, 1);
    });

    test('exit 0 without the saved line is still a failure', () async {
      final box = FakeBox({DonateCli.setupMahsaNet: ok('✗ .env file not found. Run moav setup first.\n')});
      await expectLater(controllerFor(box).saveMahsaNetKey(secretKey), throwsStateError);
    });

    test('empty or multi-line input never reaches the server', () async {
      final box = FakeBox({});
      await expectLater(controllerFor(box).saveMahsaNetKey('   '), throwsArgumentError);
      await expectLater(controllerFor(box).saveMahsaNetKey('a\nb'), throwsArgumentError);
      expect(box.uploads, isEmpty);
      expect(box.ran, isEmpty);
    });
  });

  group('donateConfigs', () {
    test('issues the stdin-driven submit and parses the summary', () async {
      final cmd = DonateCli.submit(count: 2, prefix: 'mahsa');
      final box = FakeBox({cmd: ok(fixture('donate_submit.txt'))});
      final streamed = StringBuffer();
      final r = await controllerFor(box)
          .donateConfigs(count: 2, prefix: 'mahsa', onOutput: streamed.write);
      expect(box.ran, [cmd]);
      expect(cmd, contains("printf '%s\\n%s\\n' 2 'mahsa' | MOAV_NONINTERACTIVE=1"));
      expect(r.usersCreated, 2);
      expect(r.donated, 3);
      expect(r.failed, 1);
      expect(streamed.toString(), contains('Donation Summary'));
    });

    test('force re-donates', () async {
      final cmd = DonateCli.submit(count: 1, force: true);
      final box = FakeBox({cmd: ok('  Users created: 1\n  Configs donated: 2\n')});
      final r = await controllerFor(box).donateConfigs(count: 1, force: true);
      expect(r.donated, 2);
      expect(box.ran.single, endsWith('donate submit --force 2>&1'));
    });

    test('out-of-range count or bad prefix never runs anything', () async {
      final box = FakeBox({});
      await expectLater(controllerFor(box).donateConfigs(count: 0), throwsArgumentError);
      await expectLater(controllerFor(box).donateConfigs(count: 51), throwsArgumentError);
      await expectLater(controllerFor(box).donateConfigs(count: 1, prefix: 'a b'), throwsArgumentError);
      expect(box.ran, isEmpty);
    });

    test('no summary: the ✗ line becomes the error', () async {
      final cmd = DonateCli.submit(count: 1);
      final box = FakeBox({cmd: failed('ℹ Validating API key...\n✗ MahsaNet API error (HTTP 503)\n')});
      Object? error;
      try {
        await controllerFor(box).donateConfigs(count: 1);
      } on Object catch (e) {
        error = e;
      }
      expect('$error', contains('MahsaNet API error (HTTP 503)'));
    });
  });
}
