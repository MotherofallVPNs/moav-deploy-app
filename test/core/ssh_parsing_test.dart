import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/install_script.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

void main() {
  group('parsePing', () {
    test('installed with version (ANSI-coloured)', () {
      final c = SshMoavController.parsePing(
        '__ok__\n\n\x1b[0;36mMoaV\x1b[0m v2.2.2\n\x1b[1;37m━━━\x1b[0m\n',
      );
      expect(c.reachable, isTrue);
      expect(c.moavInstalled, isTrue);
      expect(c.moavVersion, '2.2.2');
      expect(c.error, isNull);
    });

    test('not installed', () {
      final c = SshMoavController.parsePing('__ok__\n__nomoav__\n');
      expect(c.moavInstalled, isFalse);
      expect(c.moavVersion, isNull);
    });

    test('unexpected shell', () {
      final c = SshMoavController.parsePing('garbage');
      expect(c.reachable, isTrue);
      expect(c.moavInstalled, isNull);
      expect(c.error, isNotNull);
    });
  });

  group('parseInstallStatus', () {
    const log = '''
[moav-deploy] step 1/3: Preflight
Existing MoaV install found
[moav-deploy] step 2/3: Run MoaV installer (non-interactive)
\x1b[0;34mUsing existing installation.\x1b[0m
''';

    test('running with progress', () {
      final s = SshMoavController.parseInstallStatus('ALIVE\n__LOG__\n$log');
      expect(s.phase, InstallPhase.running);
      expect(s.progress, closeTo(2 / 3, 0.001));
      expect(s.message, 'Run MoaV installer (non-interactive)');
      expect(s.logTail, contains('Using existing installation.'));
    });

    test('succeeded', () {
      final s = SshMoavController.parseInstallStatus(
        'DEAD\n__LOG__\n$log\n[moav-deploy] step 3/3: Verify\n'
        '[moav-deploy] exit=0\n',
      );
      expect(s.phase, InstallPhase.succeeded);
      expect(s.progress, 1.0);
      expect(s.isTerminal, isTrue);
    });

    test('failed with exit code', () {
      final s = SshMoavController.parseInstallStatus(
        'DEAD\n__LOG__\n$log[moav-deploy] exit=3\n',
      );
      expect(s.phase, InstallPhase.failed);
      expect(s.message, contains('3'));
    });

    test('died without marker', () {
      final s = SshMoavController.parseInstallStatus('DEAD\n__LOG__\n$log');
      expect(s.phase, InstallPhase.failed);
    });

    test('pending before first step', () {
      final s = SshMoavController.parseInstallStatus('ALIVE\n__LOG__\n');
      expect(s.phase, InstallPhase.pending);
      expect(s.progress, isNull);
    });

    test('no log at all', () {
      final s = SshMoavController.parseInstallStatus('DEAD\n__LOG__\n');
      expect(s.phase, InstallPhase.unknown);
    });
  });

  group('InstallScript', () {
    test('spec quotes values and filters extra env keys', () {
      const spec = InstallSpec(
        domain: 'vpn.example.org ',
        email: 'me@example.org',
        adminPassword: "p'a\$s\"w|&d",
        extraEnv: {'MOAV_BRANCH': 'dev', 'bad key': 'x', 'X=1': 'y'},
      );
      final text = InstallScript.spec(spec);
      expect(text, contains("MD_DOMAIN='vpn.example.org'\n"));
      expect(text, contains("MD_EMAIL='me@example.org'\n"));
      expect(text, contains("MD_ADMIN_PASSWORD='p'\\''a\$s\"w|&d'\n"));
      expect(text, contains("export MOAV_BRANCH='dev'\n"));
      expect(text, isNot(contains('bad key')));
      expect(text, isNot(contains('X=1')));
    });

    test('script never wipes /opt/moav and gates the bootstrap', () {
      expect(InstallScript.script, isNot(contains('rm -rf')));
      expect(InstallScript.script, contains('export MOAV_BOOTSTRAP=1'));
      expect(InstallScript.script, contains('Already bootstrapped - bootstrap and start will be skipped'));
      expect(InstallScript.script, contains('BOOTSTRAP=0'));
      expect(InstallScript.script, contains(InstallScript.exitMarker));
      for (var i = 1; i <= InstallScript.totalSteps; i++) {
        expect(InstallScript.script, contains('step $i '));
      }
    });
  });

  test('shellQuote and stripAnsi', () {
    expect(SshConnection.shellQuote("a'b"), "'a'\\''b'");
    expect(SshConnection.stripAnsi('\x1b[1;32m✓\x1b[0m done'), '✓ done');
  });

  test('describeError hides internals', () {
    expect(
      SshMoavController.describeError(
        Exception('x' * 500),
      ).length,
      lessThanOrEqualTo(201),
    );
  });
}
