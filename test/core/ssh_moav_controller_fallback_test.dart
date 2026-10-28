import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/update_script.dart';
import 'package:moav_deploy/security/app_log.dart';

import '../support/fake_box.dart';
import '../support/fixtures.dart';

/// Each box entry maps the command's tail (after the prelude and `"$M"`)
/// to its output; `ran` records the tails in order (see `FakeBox.byTail`).

/// 2.2.x: `moav doctor --json` takes the flag for a check name.
final doctorRejected = failed(jsonFixture('doctor_json_rejected_2_2.txt'));

/// 2.2.x: `user-add.sh` rejects the unknown flag before creating anything.
final addRejected = failed('Unknown option: --json\n');

void main() {
  final logged = <String>[];
  setUp(() {
    logged.clear();
    AppLog.sink = logged.add;
  });
  tearDown(() => AppLog.sink = null);

  group('status', () {
    test('2.3.x: json document, one round trip', () async {
      final box = FakeBox.byTail({tail(MoavCli.statusJson): ok(jsonFixture('status.json'))});
      final s = await controllerFor(box).status();
      expect(s.version, '2.3.1');
      expect(s.services.length, 6);
      expect(box.ran, ['status --json']);
      expect(logged, contains(contains('status via json')));
    });

    test('2.2.x ignores the flag: text table parsed from the same output', () async {
      final box = FakeBox.byTail({tail(MoavCli.statusJson): ok(fixture('status.txt'))});
      final s = await controllerFor(box).status();
      expect(s.version, '2.2.2');
      expect(s.services.length, 5);
      expect(box.ran, ['status --json']);
      expect(logged, contains(contains('status via text')));
    });

    test('neither json nor table: re-runs the text command', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.statusJson): failed('Unknown status option: --json\n'),
        tail(MoavCli.status): ok(fixture('status.txt')),
      });
      final s = await controllerFor(box).status();
      expect(s.version, '2.2.2');
      expect(box.ran, ['status --json', 'status 2>&1']);
    });

    test('no services on either path throws', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.statusJson): failed('boom'),
        tail(MoavCli.status): ok('nothing'),
      });
      await expectLater(controllerFor(box).status(), throwsStateError);
    });
  });

  group('doctor', () {
    test('2.3.x: json (non-zero exit when a check fails)', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.doctorJson): failed(
          '[\n  {"id": "docker", "status": "pass", "detail": "✓ ok"},\n'
          '  {"id": "services", "status": "fail", "detail": "✗ grafana down"}\n]\n',
        ),
      });
      final r = await controllerFor(box).doctor();
      expect(r.checks.map((c) => c.name), ['docker', 'services']);
      expect(r.healthy, isFalse);
      expect(box.ran, ['doctor --json']);
      expect(logged, contains(contains('doctor via json')));
    });

    test('2.2.x rejects the flag: falls back to moav doctor text', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.doctorJson): doctorRejected,
        tail(MoavCli.doctor): ok(fixture('doctor.txt')),
      });
      final r = await controllerFor(box).doctor();
      expect(r.checks.map((c) => c.name), contains('docker'));
      expect(r.checks.length, 7);
      expect(box.ran, ['doctor --json', 'doctor 2>&1']);
      expect(logged, contains(contains('doctor via text')));
    });
  });

  group('listUsers', () {
    test('2.3.x: json', () async {
      final box = FakeBox.byTail({tail(MoavCli.userListJson): ok(jsonFixture('user_list.json'))});
      final users = await controllerFor(box).listUsers();
      expect(users.map((u) => u.name), ['alice', 'bob', 'carol']);
      expect(box.ran, ['user list --json']);
      expect(logged, contains(contains('user list via json')));
    });

    test('2.2.x ignores the flag: sectioned text parsed, no re-run', () async {
      final box = FakeBox.byTail({tail(MoavCli.userListJson): ok(fixture('user_list.txt'))});
      final users = await controllerFor(box).listUsers();
      expect(users.map((u) => u.name), ['alice', 'bob', 'carol']);
      expect(box.ran, ['user list --json']);
      expect(logged, contains(contains('user list via text')));
    });

    test('unrecognised output: re-runs the text command', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userListJson): failed('Unknown option: --json'),
        tail(MoavCli.userList): ok(fixture('user_list.txt')),
      });
      final users = await controllerFor(box).listUsers();
      expect(users.length, 3);
      expect(box.ran, ['user list --json', 'user list 2>&1']);
    });
  });

  group('addUser', () {
    final listedWithDave = ok(
      '[\n  {"user": "alice", "services": ["sing-box"], "bundle": true},\n'
      '  {"user": "dave", "services": ["sing-box", "xray"], "bundle": true}\n]\n',
    );

    test('2.3.x: json result then re-list', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userAddJson('dave')):
            ok(jsonFixture('user_add.json'), stderr: "[INFO] Adding user 'dave'"),
        tail(MoavCli.userListJson): listedWithDave,
      });
      final u = await controllerFor(box).addUser('dave');
      expect(u.name, 'dave');
      expect(u.bundleReady, isTrue);
      expect(u.protocols, ['sing-box', 'xray']);
      expect(box.ran, ["user add 'dave' --json", 'user list --json']);
      expect(logged, contains(contains('user add via json')));
    });

    test('2.3.x: duplicate is not an error', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userAddJson('dave')): failed(jsonFixture('user_add_dup.json')),
        tail(MoavCli.userListJson): listedWithDave,
      });
      final u = await controllerFor(box).addUser('dave');
      expect(u.name, 'dave');
    });

    test('2.3.x: script failure throws with the json error', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userAddJson('badguy')): failed(jsonFixture('user_add_failed.json')),
      });
      await expectLater(
        controllerFor(box).addUser('badguy'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('user-add.sh exited 1'))),
      );
      expect(box.ran, ["user add 'badguy' --json"]);
    });

    test('2.2.x rejects the flag: text add then re-list', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userAddJson('dave')): addRejected,
        tail(MoavCli.userAdd('dave')): ok("[INFO] ✓ User 'dave' created successfully\n"),
        tail(MoavCli.userListJson): ok(fixture('user_list.txt').replaceFirst(
            '  • bob\n', '  • bob\n  • dave [bundle ready]\n')),
      });
      final u = await controllerFor(box).addUser('dave');
      expect(u.name, 'dave');
      expect(box.ran, ["user add 'dave' --json", "user add 'dave' 2>&1", 'user list --json']);
      expect(logged, contains(contains('user add via text')));
    });

    test('invalid names never reach the box', () async {
      final box = FakeBox.byTail({});
      await expectLater(controllerFor(box).addUser('bad name'), throwsArgumentError);
      expect(box.ran, isEmpty);
    });
  });

  group('removeUser', () {
    final listedWithout = ok('[\n  {"user": "alice", "services": ["sing-box"], "bundle": true}\n]\n');

    test('2.3.x: json result then re-list', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userRemoveJson('dave')): ok(jsonFixture('user_remove.json')),
        tail(MoavCli.userListJson): listedWithout,
      });
      await controllerFor(box).removeUser('dave');
      expect(box.ran, ["user remove 'dave' --json", 'user list --json']);
      expect(logged, contains(contains('user remove via json')));
    });

    test('2.3.x: unknown user is already gone, so no error', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userRemoveJson('nobody')): failed(jsonFixture('user_remove_unknown.json')),
        tail(MoavCli.userListJson): listedWithout,
      });
      await controllerFor(box).removeUser('nobody');
    });

    test('2.3.x: user still listed afterwards throws', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userRemoveJson('alice')): failed(
            '{"ok": false, "action": "remove", "users": [{"user": "alice", "ok": false, "error": "revoke failed (exit 2)"}]}'),
        tail(MoavCli.userListJson): listedWithout,
      });
      await expectLater(
        controllerFor(box).removeUser('alice'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('revoke failed'))),
      );
    });

    test('2.2.x: text revoke then re-list', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.userRemoveJson('dave')): ok("[INFO] Revoking user 'dave'\n[ERROR] User '--json' not found\n"),
        tail(MoavCli.userRevoke('dave')): ok("[ERROR] User 'dave' not found\n"),
        tail(MoavCli.userListJson): ok(fixture('user_list.txt')),
      });
      await controllerFor(box).removeUser('dave');
      expect(box.ran, ["user remove 'dave' --json", "user revoke 'dave' 2>&1", 'user list --json']);
      expect(logged, contains(contains('user remove via text')));
    });
  });

  group('checkForUpdates', () {
    test('2.3.x: json document, one round trip', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.doctorUpdatesJson): failed(jsonFixture('doctor_updates.json')),
      });
      final c = await controllerFor(box).checkForUpdates();
      expect(c.updateAvailable, isTrue);
      expect(c.latestVersion, '2.3.1');
      expect(box.ran, ['doctor updates --json']);
      expect(logged, contains(contains('doctor updates via json')));
    });

    test('2.2.x rejects the flag: falls back to the text check', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.doctorUpdatesJson): doctorRejected,
        tail(MoavCli.doctorUpdates): ok(
          'updates - Check for MoaV updates\n'
          '    Current version: v2.2.2\n'
          '    ✓ Up to date (v2.2.2)\n',
        ),
      });
      final c = await controllerFor(box).checkForUpdates();
      expect(c.updateAvailable, isFalse);
      expect(c.currentVersion, '2.2.2');
      expect(box.ran, ['doctor updates --json', 'doctor updates 2>&1']);
      expect(logged, contains(contains('doctor updates via text')));
    });

    test('no version on either path throws', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.doctorUpdatesJson): failed('nope'),
        tail(MoavCli.doctorUpdates): ok('nope'),
      });
      await expectLater(controllerFor(box).checkForUpdates(), throwsStateError);
    });
  });

  group('serverInfo', () {
    test('parses the host snippet', () async {
      final box = FakeBox.byTail({tail(MoavCli.hostInfo): ok(fixture('host_info.txt'))});
      final s = await controllerFor(box).serverInfo();
      expect(s.version.moavVersion, '2.3.0');
      expect(s.host.cpuCount, 2);
      expect(s.host.diskUsage, closeTo(0.285, 0.001));
    });

    test('an empty answer throws instead of showing blanks', () async {
      final box = FakeBox.byTail({tail(MoavCli.hostInfo): ok('')});
      await expectLater(controllerFor(box).serverInfo(), throwsStateError);
    });
  });

  group('metrics', () {
    test('parses the prometheus snippet into a snapshot', () async {
      final box = FakeBox.byTail({
        tail(MoavCli.prometheus): ok(
          '__URLS__\n__HEALTH__\n\n__PROM__\n__Q__ load1\n'
          '{"status":"success","data":{"result":[{"value":[1,"2.15"]}]}}\n__END__\n',
        ),
      });
      final m = await controllerFor(box).metrics();
      expect(m.metrics.single.name, 'Load (1m)');
      expect(m.metrics.single.value, '2.15');
    });
  });

  group('updateStatus', () {
    test('no job ever launched gives null', () async {
      final box = FakeBox.byTail({tail(UpdateScript.status()): ok('NOJOB\n')});
      expect(await controllerFor(box).updateStatus(), isNull);
    });

    test('a live job reports its step out of three', () async {
      final box = FakeBox.byTail({
        tail(UpdateScript.status()): ok(
          'ALIVE\n__LOG__\n[moav-deploy] step 2/3: Run moav update\nPulling...\n',
        ),
      });
      final s = (await controllerFor(box).updateStatus())!;
      expect(s.phase, InstallPhase.running);
      expect(s.progress, closeTo(2 / 3, 1e-9));
      expect(s.message, 'Run moav update');
    });

    test('a finished job reports the exit marker', () async {
      final box = FakeBox.byTail({
        tail(UpdateScript.status()): ok(
          'DEAD\n__LOG__\n[moav-deploy] step 3/3: Report\n[moav-deploy] exit=0\n',
        ),
      });
      final s = (await controllerFor(box).updateStatus())!;
      expect(s.phase, InstallPhase.succeeded);
      expect(s.progress, 1.0);
    });
  });

  test('update script runs the documented command without a TTY', () {
    expect(UpdateScript.body, contains('moav_cmd update --yes < /dev/null'));
    expect(UpdateScript.body, isNot(contains('__UPDATE_COMMAND__')));
    expect(UpdateScript.body, contains('MOAV_NONINTERACTIVE=1'));
    expect(UpdateScript.body, isNot(contains('reset --hard')));
    expect(UpdateScript.body, isNot(contains('moav_cmd restart')));
    expect(UpdateScript.body, isNot(contains('moav_cmd build')));
    expect(UpdateScript.launch, contains('setsid nohup bash update.sh'));
  });

  test('log lines never carry the document, only the format', () async {
    final box = FakeBox.byTail({tail(MoavCli.statusJson): ok(jsonFixture('status.json'))});
    await controllerFor(box).status();
    expect(logged.single, '[I] moav-cli: status via json');
  });
}
