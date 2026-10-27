import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/install_script.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_services.dart';
import 'package:moav_deploy/core/ssh_connection.dart';

void main() {
  const base = InstallSpec(domain: 'vpn.example.org', email: 'a@b.c', adminPassword: 'pw');

  group('InstallScript.spec', () {
    test('an untouched spec carries the default profiles and their flags', () {
      final s = InstallScript.spec(base);
      final profiles = SshConnection.shellQuote(MoavProfiles.defaults.join(' '));
      expect(s, contains('MD_PROFILES=$profiles\n'));
      expect(s, contains('MD_ENABLE='));
      final enable = RegExp(r"MD_ENABLE='([^']*)'").firstMatch(s)!.group(1)!;
      final pairs = enable.split(' ');
      expect(pairs, contains('ENABLE_WIREGUARD=true'));
      expect(pairs, contains('ENABLE_REALITY=true'));
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
      expect(s, contains("MD_PROFILES='wireguard monitoring'\n"));
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
  });

  group('InstallScript.script', () {
    const script = InstallScript.script;

    test('DEFAULT_PROFILES is written before moav bootstrap --yes', () {
      final profiles = script.indexOf('set_if_empty DEFAULT_PROFILES "\$MD_PROFILES"');
      final bootstrap = script.indexOf('moav_cmd bootstrap --yes');
      final start = script.indexOf('moav_cmd start');
      expect(profiles, greaterThan(0));
      expect(profiles, lessThan(bootstrap));
      expect(bootstrap, lessThan(start));
    });

    test('ENABLE_* flags only touch a .env created by this run', () {
      expect(script, contains('ENV_FRESH=1'));
      expect(script, contains('if [ "\$ENV_FRESH" = 1 ]; then'));
      expect(script, contains('ENABLE_*=true|ENABLE_*=false) set_env'));
      expect(script, contains('Existing .env: ENABLE_* flags kept as configured'));
      // DEFAULT_PROFILES is never overwritten, only filled.
      expect(script, isNot(contains('set_env DEFAULT_PROFILES')));
    });

    test('bare moav start keeps relying on DEFAULT_PROFILES (no profile args)', () {
      expect(script, contains('moav_cmd start < /dev/null'));
      expect(script, isNot(contains('moav_cmd start --profile')));
      expect(script, isNot(contains('bootstrap --yes --profile')));
    });
  });
}
