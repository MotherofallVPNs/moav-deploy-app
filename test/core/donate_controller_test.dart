import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/security/app_log.dart';

import '../support/fake_box.dart';
import '../support/fixtures.dart';

const secretKey = 'mk_live_VERYSECRETKEY_0123456789';

/// The box is scripted by exact command string (see `FakeBox`), so a test
/// can prove where the API key did and did not go.

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
