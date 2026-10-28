import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/install_script.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';

void main() {
  const base = InstallSpec(
    domain: 'vpn.example.org',
    email: 'a@b.c',
    adminPassword: 'pw',
  );

  group('InstallScript.spec', () {
    test('an untouched spec carries the default selection as ENABLE_* pairs', () {
      final s = InstallScript.spec(base);
      expect(s, contains("MD_DOMAIN='vpn.example.org'\n"));
      expect(s, contains("MD_EMAIL='a@b.c'\n"));
      expect(s, contains('MD_ENABLE='));
      // DEFAULT_PROFILES is derived by install.sh from the flags, not sent.
      expect(s, isNot(contains('MD_PROFILES')));
      final enable = RegExp(r"MD_ENABLE='([^']*)'").firstMatch(s)!.group(1)!;
      final pairs = enable.split(' ');
      expect(pairs, contains('ENABLE_WIREGUARD=true'));
      expect(pairs, contains('ENABLE_REALITY=true'));
      expect(pairs, contains('ENABLE_TROJAN=true'));
      expect(pairs, contains('ENABLE_MONITORING=false'));
      expect(pairs, contains('ENABLE_GOOSERELAY=false'));
      expect(pairs, isNot(contains('ENABLE_ANYTLS=true')));
      expect(pairs.every(RegExp(r'^ENABLE_[A-Z0-9_]+=(true|false)$').hasMatch), isTrue);
    });

    test('a custom selection drops unknown names and flips the flags', () {
      final s = InstallScript.spec(InstallSpec(
        domain: '',
        email: '',
        adminPassword: 'pw',
        profiles: const ['wireguard', 'bad name; rm -rf /', 'monitoring', 'wireguard'],
      ));
      expect(s, contains("MD_DOMAIN=''\n"));
      final enable = RegExp(r"MD_ENABLE='([^']*)'").firstMatch(s)!.group(1)!.split(' ');
      expect(enable, contains('ENABLE_WIREGUARD=true'));
      expect(enable, contains('ENABLE_MONITORING=true'));
      expect(enable, contains('ENABLE_REALITY=false'));
      expect(enable, contains('ENABLE_TELEMT=false'));
      expect(enable, contains('ENABLE_ANYTLS=false'));
      expect(s, isNot(contains('rm -rf')));
    });

    test('the password is single-quoted and never in the script itself', () {
      expect(InstallScript.spec(base), contains("MD_ADMIN_PASSWORD='pw'"));
      expect(InstallScript.script, isNot(contains('pw')));
      expect(InstallScript.script, isNot(contains('MD_ADMIN_PASSWORD=\'')));
    });

    test('extra env goes through as exports with a validated key', () {
      final s = InstallScript.spec(const InstallSpec(
        domain: '',
        email: '',
        adminPassword: 'pw',
        extraEnv: {'MOAV_BRANCH': 'dev', 'bad key': 'x', 'X; rm': 'y'},
      ));
      expect(s, contains("export MOAV_BRANCH='dev'\n"));
      expect(s, isNot(contains('bad key')));
      expect(s, isNot(contains('rm')));
      expect(SshConnection.shellQuote("it's"), "'it'\\''s'");
    });
  });

  group('InstallScript.script', () {
    const script = InstallScript.script;

    test("drives install.sh's non-interactive contract", () {
      expect(script, contains('export MOAV_NONINTERACTIVE=1'));
      expect(script, contains('export MOAV_ADMIN_PASSWORD="\$MD_ADMIN_PASSWORD"'));
      expect(script, contains('export MOAV_DOMAIN="\$MD_DOMAIN" MOAV_EMAIL="\$MD_EMAIL"'));
      expect(script, contains('export MOAV_DOMAINLESS=1'));
      expect(script, contains('export MOAV_BOOTSTRAP=1'));
      expect(script, contains('https://moav.sh/install.sh | bash'));
    });

    test('domainless is a flag, not an app-side protocol disable list', () {
      final domainless = script.indexOf('export MOAV_DOMAINLESS=1');
      expect(domainless, greaterThan(0));
      expect(script.substring(0, domainless), contains('if [ -n "\$MD_DOMAIN" ]; then'));
      // Upstream owns the set of certificate-dependent protocols.
      expect(script, isNot(contains('ENABLE_TROJAN')));
      expect(script, isNot(contains('ENABLE_HYSTERIA2')));
      expect(script, isNot(contains(RegExp(r'(^|[^A-Z_])DOMAIN=', multiLine: true))));
    });

    test('.env is written by install.sh, never by the job', () {
      expect(script, isNot(contains('.env.example')));
      expect(script, isNot(contains('set_if_empty')));
      expect(script, isNot(contains('DEFAULT_PROFILES "')));
      expect(script, isNot(contains('set_env')));
      expect(script, isNot(contains('>> .env')));
    });

    test('ENABLE_* flags only reach a .env this run creates', () {
      expect(script, contains('if [ ! -f "\$INSTALL_DIR/.env" ]; then'));
      expect(script, contains('ENABLE_*=true|ENABLE_*=false) export "\$kv"'));
      expect(script, contains('Existing .env: ENABLE_* flags kept as configured'));
    });

    test('bootstrap and start are left to the installer, only on a fresh box', () {
      expect(script, contains('BOOTSTRAP=1'));
      expect(script, contains('outputs/bundles'));
      expect(script, contains('Already bootstrapped - bootstrap and start will be skipped'));
      expect(script, contains('if [ "\$BOOTSTRAP" = 1 ]; then\n  export MOAV_BOOTSTRAP=1'));
      expect(script, isNot(contains('moav_cmd bootstrap')));
      expect(script, isNot(contains('moav_cmd start')));
      expect(script, contains('moav_cmd status < /dev/null'));
    });

    test('the clone is world-readable while the launcher files stay private', () {
      expect(InstallScript.launch, contains('umask 077'));
      expect(script, contains('\numask 022\n'));
      final umask = script.indexOf('\numask 022\n');
      final installer = script.indexOf('install.sh | bash');
      expect(umask, lessThan(installer));
    });

    test('three self-describing steps and an exit marker', () {
      expect(InstallScript.totalSteps, 3);
      for (var i = 1; i <= InstallScript.totalSteps; i++) {
        expect(script, contains('step $i "'));
      }
      expect(script, contains('[moav-deploy] step \$1/${InstallScript.totalSteps}:'));
      expect(script, contains(InstallScript.exitMarker));
      expect(script, isNot(contains('rm -rf')));
    });
  });
}
