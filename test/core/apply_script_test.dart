import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/apply_script.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/core/update_script.dart';

import '../support/fake_box.dart';

/// Stand-ins for the two programs the apply job drives. Each appends its
/// arguments to `calls` in the box directory; marker files there make a
/// step fail (`fail-build`, `fail-regen`, `fail-start`).
const _docker = r'''#!/bin/bash
echo "docker $*" >> "$BOX/calls"
if [ "$1 $2" = "compose version" ]; then exit 0; fi
for a in "$@"; do
  if [ "$a" = build ]; then
    echo "#1 building"
    if [ -f "$BOX/fail-build" ]; then echo "build error"; exit 17; fi
  fi
done
exit 0
''';

const _moav = r'''#!/bin/bash
echo "moav $* ni=${MOAV_NONINTERACTIVE:-0}" >> "$BOX/calls"
case "$1" in
  --version) echo "MoaV v2.4.0" ;;
  update)
    cd "$MOAV_INSTALL_DIR" && echo x >> pulled && git add -A > /dev/null \
      && git -c user.email=t@example.org -c user.name=t commit -qm pull
    echo "pulled a new revision" ;;
  regenerate-users) if [ -f "$BOX/fail-regen" ]; then exit 5; fi; echo "regenerated" ;;
  start) if [ -f "$BOX/fail-start" ]; then exit 6; fi; echo "Services started!" ;;
  status) echo "status table" ;;
esac
''';

/// A throwaway box: an install dir with `.env` and the stubs, a state dir
/// standing in for `~/.moav-deploy`, and `bin/` ahead of PATH.
class _Box {
  _Box(this.dir);

  final Directory dir;

  String get install => '${dir.path}/moav';
  String get state => '${dir.path}/state';

  Map<String, String> get env => {
        'MOAV_INSTALL_DIR': install,
        'MOAV_DEPLOY_DIR': state,
        'BOX': dir.path,
        'PATH': '${dir.path}/bin:${Platform.environment['PATH'] ?? ''}',
      };

  static Future<_Box> create({String? env = 'DEFAULT_PROFILES="proxy admin"\n'}) async {
    final dir = await Directory.systemTemp.createTemp('moav-deploy-apply-test');
    final box = _Box(dir);
    await Directory(box.install).create();
    await Directory(box.state).create();
    await Directory('${dir.path}/bin').create();
    await File('${dir.path}/bin/docker').writeAsString(_docker);
    await File('${box.install}/moav.sh').writeAsString(_moav);
    await Process.run('chmod', ['755', '${dir.path}/bin/docker', '${box.install}/moav.sh']);
    if (env != null) await File('${box.install}/.env').writeAsString(env);
    await File('${box.state}/apply.sh').writeAsString(ApplyScript.script);
    return box;
  }

  Future<void> flag(String name) => File('${dir.path}/$name').writeAsString('');

  Future<({int code, String log})> apply(List<String> args) async {
    final r = await Process.run('bash', ['$state/apply.sh', ...args], environment: env);
    return (code: r.exitCode, log: '${r.stdout}${r.stderr}');
  }

  List<String> get calls {
    final f = File('${dir.path}/calls');
    return f.existsSync() ? f.readAsLinesSync() : const [];
  }

  String? read(String name) {
    final f = File('$state/$name');
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  }

  Future<void> dispose() => dir.delete(recursive: true);
}

void main() {
  group('ApplyScript', () {
    test('arguments: flags first, validated service names after', () {
      expect(ApplyScript.args(const ApplySpec()), '');
      expect(ApplyScript.args(ApplySpec.afterUpdate), '--regenerate');
      expect(
        ApplyScript.args(const ApplySpec(services: ['sing-box', 'xray'], noCache: true)),
        '--no-cache sing-box xray',
      );
      for (final bad in ['a b', 'x;reboot', r'$(id)', '--no-cache', '']) {
        expect(
          () => ApplyScript.args(ApplySpec(services: [bad])),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('launch: detached, one job at a time, never over a live script', () {
      final launch = ApplyScript.launch(const ApplySpec(services: ['xray'], noCache: true));
      expect(launch, contains('nohup bash apply.sh --no-cache xray > apply.log 2>&1 < /dev/null &'));
      expect(launch, contains(r'$(command -v setsid) nohup'));
      expect(launch, contains('echo "BUSY update"; exit 0'));
      expect(launch, contains(r'if apply_alive; then echo "RUNNING $(cat apply.pid)"; exit 0; fi'));
      expect(launch.indexOf('apply_alive; then'), lessThan(launch.indexOf('mv -f apply.sh.new apply.sh')));
      // A new launch forgets the previous result before it starts.
      expect(launch, contains('rm -f apply.exit apply.ack apply.job'));
    });

    test('the job itself: build, then users, then start; no cleanup verbs', () {
      const s = ApplyScript.script;
      expect(s, contains('export MOAV_NONINTERACTIVE=1'));
      expect(s, contains('trap on_exit EXIT'));
      expect(s.indexOf('step 2 "Build images"'), lessThan(s.indexOf('moav_cmd regenerate-users')));
      expect(s.indexOf('moav_cmd regenerate-users'), lessThan(s.indexOf(r'moav_cmd start $SERVICES')));
      for (final verb in ['down', 'prune', 'rm -rf', 'reset --hard', 'moav_cmd stop']) {
        expect(s, isNot(contains(verb)), reason: verb);
      }
    });

    test('startApply uploads beside the script, then launches', () async {
      final box = FakeBox.always('STARTED 4242\n');
      const spec = ApplySpec(services: ['sing-box'], noCache: true);
      await box.controller.startApply(spec);
      expect(box.uploads.single.$1, '.moav-deploy/apply.sh.new');
      expect(box.uploads.single.$2, ApplyScript.script);
      expect(box.uploads.single.$3, '700');
      expect(box.ran, [ApplyScript.launch(spec)]);
    });

    test('startApply: attaches to a running job, refuses during an update',
        () async {
      await FakeBox.always('RUNNING 77\n').controller.startApply(const ApplySpec());
      await expectLater(
        FakeBox.always('BUSY update\n').controller.startApply(const ApplySpec()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('update is still running'))),
      );
      await expectLater(
        FakeBox.always('bash: nohup: not found\n').controller.startApply(const ApplySpec()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('Could not start the rebuild'))),
      );
    });

    test('a bad service name never reaches the box', () async {
      final box = FakeBox.always('STARTED 1\n');
      await expectLater(
        box.controller.startApply(const ApplySpec(services: ['x; rm -rf /'])),
        throwsArgumentError,
      );
      expect(box.uploads, isEmpty);
      expect(box.ran, isEmpty);
    });

    test('acknowledgeApply only marks a job that has ended', () async {
      final box = FakeBox.always('');
      await box.controller.acknowledgeApply();
      expect(box.ran.single, ApplyScript.acknowledge);
      expect(ApplyScript.acknowledge, contains('! apply_alive'));
    });
  });

  group('parseApplyStatus', () {
    ApplyStatus parse(String raw) => SshMoavController.parseApplyStatus(raw);

    test('no job, with and without a pending update', () {
      expect(parse('NOJOB\n').job, isNull);
      expect(parse('NOJOB\n').updatePending, isFalse);
      final pending = parse('PENDING\nNOJOB\n');
      expect(pending.job, isNull);
      expect(pending.updatePending, isTrue);
      expect(parse('').job, isNull);
    });

    test('running: the step comes from the whole log, not the tail', () {
      final s = parse('PENDING\nALIVE\n'
          'JOB=id=1795545846-3588 no_cache=0 regenerate=1 services=\n'
          'STEP=[moav-deploy] step 2/4: Build images\n'
          '__LOG__\n#598 building layer\n#599 building layer\n');
      expect(s.running, isTrue);
      expect(s.job!.phase, InstallPhase.running);
      expect(s.job!.step, 2);
      expect(s.job!.totalSteps, 4);
      expect(s.job!.message, 'Build images');
      expect(s.job!.logTail, ['#598 building layer', '#599 building layer']);
      expect(s.jobId, '1795545846-3588');
      expect(s.spec!.allServices, isTrue);
      expect(s.spec!.regenerateUsers, isTrue);
      expect(s.exitCode, isNull);
      expect(s.updatePending, isTrue);
      expect(s.hasUnseenResult, isFalse);
    });

    test('ended: success and failure carry the exit code', () {
      final ok = parse('DEAD\nEXIT=0\n'
          'JOB=id=1-2 no_cache=1 regenerate=0 services=sing-box,xray\n'
          'STEP=[moav-deploy] step 4/4: Start services on the new images\n'
          '__LOG__\nApplied.\n\n[moav-deploy] exit=0\n');
      expect(ok.running, isFalse);
      expect(ok.job!.phase, InstallPhase.succeeded);
      expect(ok.job!.message, 'Rebuild finished');
      expect(ok.exitCode, 0);
      expect(ok.spec!.services, ['sing-box', 'xray']);
      expect(ok.spec!.noCache, isTrue);
      expect(ok.spec!.label, 'Rebuild sing-box, xray (no cache)');
      expect(ok.hasUnseenResult, isTrue);

      final failed = parse('DEAD\nEXIT=17\nACKED\nJOB=id=3-4 no_cache=0 regenerate=1 services=\n'
          'STEP=[moav-deploy] step 2/4: Build images\n__LOG__\nbuild error\n\n[moav-deploy] exit=17\n');
      expect(failed.job!.phase, InstallPhase.failed);
      expect(failed.job!.message, 'Rebuild failed (exit 17)');
      expect(failed.job!.step, 2);
      expect(failed.exitCode, 17);
      expect(failed.acknowledged, isTrue);
      expect(failed.hasUnseenResult, isFalse);
    });

    test('the exit file decides even when the log lost its last line', () {
      final s = parse('DEAD\nEXIT=143\nSTEP=\n__LOG__\nInterrupted (SIGTERM)\n');
      expect(s.job!.phase, InstallPhase.failed);
      expect(s.job!.message, 'Rebuild failed (exit 143)');
      expect(s.spec, isNull);
    });

    test('dead without any result is a failure, not a hang', () {
      final s = parse('DEAD\nSTEP=[moav-deploy] step 2/4: Build images\n__LOG__\n#1 building\n');
      expect(s.running, isFalse);
      expect(s.job!.phase, InstallPhase.failed);
      expect(s.job!.message, 'Rebuild process ended without reporting a result');
    });

    test('applyStatus runs the status snippet once', () async {
      final box = FakeBox.always('NOJOB\n');
      expect((await box.controller.applyStatus()).job, isNull);
      expect(box.ran, [ApplyScript.status()]);
    });
  });

  group('the job on a box', () {
    final hasBash = Process.runSync('bash', ['-c', 'echo ok']).exitCode == 0;
    final skip = hasBash ? false : 'bash not available';
    late _Box box;
    tearDown(() => box.dispose());

    test('all services: enabled profiles only, users, start, exit file', () async {
      box = await _Box.create();
      await File('${box.state}/apply.pending').writeAsString('abc\n');
      final r = await box.apply(['--regenerate']);
      expect(r.code, 0, reason: r.log);
      expect(box.calls, [
        'docker compose version',
        'docker compose --profile proxy --profile admin build',
        'moav regenerate-users ni=1',
        'moav start ni=1',
        'moav status ni=1',
      ]);
      expect(r.log, contains('[moav-deploy] step 4/4: Start services on the new images'));
      expect(r.log, contains('[moav-deploy] exit=0'));
      expect(box.read('apply.exit'), '0');
      expect(box.read('apply.job'), matches(r'^id=\d+-\d+ no_cache=0 regenerate=1 services=$'));
      // The pulled update is applied now.
      expect(box.read('apply.pending'), isNull);
    }, skip: skip);

    test('one service, forced: --no-cache build and a scoped start', () async {
      box = await _Box.create();
      await File('${box.state}/apply.pending').writeAsString('abc\n');
      final r = await box.apply(['--no-cache', 'sing-box']);
      expect(r.code, 0, reason: r.log);
      expect(box.calls, [
        'docker compose version',
        'docker compose --profile all build --no-cache sing-box',
        'moav start sing-box ni=1',
        'moav status ni=1',
      ]);
      expect(r.log, contains('Skipped (not requested).'));
      expect(box.read('apply.job'), endsWith('no_cache=1 regenerate=0 services=sing-box'));
      // A partial rebuild does not settle a pending update.
      expect(box.read('apply.pending'), 'abc');
    }, skip: skip);

    test('a failed build restarts nothing and reports its exit code', () async {
      box = await _Box.create();
      await box.flag('fail-build');
      final r = await box.apply(['--regenerate']);
      expect(r.code, 17);
      expect(box.calls.where((c) => c.startsWith('moav ')), isEmpty);
      expect(r.log, contains('Nothing was restarted'));
      expect(r.log, contains('[moav-deploy] exit=17'));
      expect(box.read('apply.exit'), '17');
    }, skip: skip);

    test('failed regenerate-users still starts, then fails the job', () async {
      box = await _Box.create();
      await box.flag('fail-regen');
      final r = await box.apply(['--regenerate']);
      expect(r.code, 5);
      expect(box.calls, contains('moav start ni=1'));
      expect(r.log, contains('the user bundles were not regenerated (exit 5)'));
      expect(box.read('apply.exit'), '5');
    }, skip: skip);

    test('a failed start is the job result', () async {
      box = await _Box.create();
      await box.flag('fail-start');
      final r = await box.apply([]);
      expect(r.code, 6);
      expect(r.log, contains('moav start failed (exit 6)'));
      expect(box.read('apply.exit'), '6');
    }, skip: skip);

    test('preflight: no .env, no DEFAULT_PROFILES, bad argument', () async {
      box = await _Box.create(env: null);
      var r = await box.apply([]);
      expect(r.code, 1);
      expect(r.log, contains('install and bootstrap first'));
      expect(box.read('apply.exit'), '1');

      await File('${box.install}/.env').writeAsString('DOMAIN=x\n');
      r = await box.apply([]);
      expect(r.code, 1);
      expect(r.log, contains('DEFAULT_PROFILES is not set'));
      expect(box.calls.where((c) => c.contains(' build')), isEmpty);

      r = await box.apply(['x;reboot']);
      expect(r.code, 2);
      expect(r.log, contains('Unknown argument'));
    }, skip: skip);

    test('the update job starts the apply itself and marks it pending',
        () async {
      box = await _Box.create();
      final hasGit = Process.runSync('git', ['--version']).exitCode == 0;
      if (!hasGit) return markTestSkipped('git not available');
      for (final args in [
        ['init', '-q', '.'],
        ['-c', 'user.email=t@example.org', '-c', 'user.name=t', 'commit', '-qm', 'init', '--allow-empty'],
      ]) {
        final g = await Process.run('git', args, workingDirectory: box.install);
        expect(g.exitCode, 0, reason: '${g.stderr}');
      }
      final update = File('${box.state}/update.sh')..writeAsStringSync(UpdateScript.body);

      // Without the opt-in the new revision is left pending, loudly.
      var r = await Process.run('bash', [update.path], environment: box.env);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('[moav-deploy] apply=pending'));
      expect(box.read('apply.pending'), isNotNull);
      expect(box.read('apply.pid'), isNull);

      r = await Process.run(
        'bash',
        [update.path],
        environment: {...box.env, 'MD_APPLY_AFTER': '1'},
      );
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('[moav-deploy] apply=started'));
      // Detached: the update has returned, the apply finishes on its own.
      for (var i = 0; i < 100 && box.read('apply.exit') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(box.read('apply.exit'), '0', reason: box.read('apply.log') ?? 'no log');
      expect(box.read('apply.job'), endsWith('regenerate=1 services='));
      expect(box.read('apply.pending'), isNull);
      expect(box.calls, containsAllInOrder([
        'moav update --yes ni=1',
        'docker compose --profile proxy --profile admin build',
        'moav regenerate-users ni=1',
        'moav start ni=1',
      ]));
    }, skip: skip);
  });
}
