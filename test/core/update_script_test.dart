import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/update_script.dart';

import '../support/fake_box.dart';

/// A stand-in `moav.sh` for the bash tests: the post-#345 build accepts
/// `--yes` and ignores stdin; the older one rejects it exactly like
/// upstream's `cmd_update` (`error "Unknown option: $1"`, return 1) and
/// otherwise reads its three prompts from stdin.
const _newMoav = r'''#!/bin/bash
case "$1" in
  --version) echo "MoaV 2.4.0"; exit 0 ;;
  update) shift ;;
  *) echo "usage"; exit 2 ;;
esac
for a in "$@"; do
  case "$a" in
    -y|--yes) export MOAV_NONINTERACTIVE=1 ;;
    *) echo "✗ Unknown option: $a"; exit 1 ;;
  esac
done
echo "new: noninteractive=${MOAV_NONINTERACTIVE:-0} stdin=$(cat)"
echo "new: updated"
''';

const _oldMoav = r'''#!/bin/bash
case "$1" in
  --version) echo "MoaV 2.3.1"; exit 0 ;;
  update) shift ;;
  *) echo "usage"; exit 2 ;;
esac
for a in "$@"; do
  case "$a" in
    -b|--branch) shift ;;
    -h|--help) echo "Usage: moav update [-b BRANCH]"; exit 0 ;;
    *) printf '\033[0;31m✗\033[0m Unknown option: %s\n' "$a"; echo "Use 'moav update --help' for usage"; exit 1 ;;
  esac
done
read -rp "Choice [1/2/3]: " choice; echo "old: stash choice='$choice'"
read -r -p "Update component versions in .env? [Y/n] " v; echo "old: versions='$v'"
read -r -p "Add these to your .env with default values? [Y/n] " e; echo "old: env additions='$e' (eof=$?)"
echo "old: updated"
''';

Future<({int code, String log})> runJob(String moavSh) async {
  final dir = await Directory.systemTemp.createTemp('moav-deploy-update-test');
  try {
    await Directory('${dir.path}/.git').create();
    await File('${dir.path}/moav.sh').writeAsString(moavSh);
    await Process.run('chmod', ['755', '${dir.path}/moav.sh']);
    final script = File('${dir.path}/update.sh')
      ..writeAsStringSync(UpdateScript.body);
    final r = await Process.run(
      'bash',
      [script.path],
      environment: {'MOAV_INSTALL_DIR': dir.path, 'PATH': Platform.environment['PATH'] ?? ''},
    );
    return (code: r.exitCode, log: '${r.stdout}${r.stderr}');
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  group('UpdateScript', () {
    test('tries `update --yes` first and the legacy answers second', () {
      expect(UpdateScript.updateCommand, 'update --yes');
      expect(UpdateScript.legacyUpdateCommand, 'update');
      expect(UpdateScript.legacyRejectionMarker, 'Unknown option: --yes');
      expect(UpdateScript.legacyAnswers, '1\nY\n');
      final body = UpdateScript.body;
      expect(body, contains('export MOAV_NONINTERACTIVE=1'));
      expect(body, contains('moav_cmd update --yes < /dev/null 2>&1 | tee'));
      expect(body, contains("grep -q 'Unknown option: --yes'"));
      expect(body, contains(r"printf '1\nY\n' | moav_cmd update 2>&1"));
      expect(body.indexOf('update --yes'), lessThan(body.indexOf("printf '1\\nY\\n'")));
      expect(body, isNot(contains('__UPDATE_COMMAND__')));
      expect(body, isNot(contains('__LEGACY_')));
      // Local changes are stashed, never discarded, on either path.
      expect(body, isNot(contains('reset --hard')));
      expect(UpdateScript.launch, contains('setsid nohup bash update.sh'));
    });

    test('startUpdate uploads that body and launches it detached', () async {
      final box = FakeBox.always('STARTED 4242\n');
      final uploads = box.uploads;
      final ran = box.ran;
      await box.controller.startUpdate();
      expect(uploads.single.$1, UpdateScript.scriptPath);
      expect(uploads.single.$1, '.moav-deploy/update.sh');
      expect(uploads.single.$3, '700');
      expect(uploads.single.$2, UpdateScript.body);
      expect(uploads.single.$2, contains('update --yes'));
      expect(uploads.single.$2, contains("printf '1\\nY\\n' | moav_cmd update"));
      expect(ran, [UpdateScript.launch]);
    });
  });

  group('the job on a box', () {
    final hasBash = Process.runSync('bash', ['-c', 'echo ok']).exitCode == 0;

    test('post-#345 moav: one non-interactive attempt, stdin unused', () async {
      final r = await runJob(_newMoav);
      expect(r.code, 0, reason: r.log);
      expect(r.log, contains('new: noninteractive=1 stdin='));
      expect(r.log, contains('new: updated'));
      expect(r.log, isNot(contains('retrying the legacy way')));
      expect(r.log, contains('[moav-deploy] step 3/3'));
      expect(r.log, contains('[moav-deploy] exit=0'));
    }, skip: hasBash ? false : 'bash not available');

    test('older moav: --yes is rejected, then the piped answers run', () async {
      final r = await runJob(_oldMoav);
      expect(r.code, 0, reason: r.log);
      expect(r.log, contains('Unknown option: --yes'));
      expect(r.log, contains('retrying the legacy way'));
      expect(r.log, contains("old: stash choice='1'"));
      expect(r.log, contains("old: versions='Y'"));
      // Third prompt hits EOF: empty answer, which upstream's [Y/n] accepts.
      expect(r.log, contains("old: env additions=''"));
      expect(r.log, contains('old: updated'));
      expect(r.log, contains('[moav-deploy] exit=0'));
    }, skip: hasBash ? false : 'bash not available');

    test('a real failure on new moav is not retried', () async {
      final r = await runJob(_newMoav.replaceFirst(
          'echo "new: updated"', 'echo "✗ git pull failed"; exit 3'));
      expect(r.code, 3);
      expect(r.log, isNot(contains('retrying the legacy way')));
      expect(r.log, contains('moav update failed (exit 3)'));
      expect(r.log, contains('[moav-deploy] exit=3'));
    }, skip: hasBash ? false : 'bash not available');
  });
}
