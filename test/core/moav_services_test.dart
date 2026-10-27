import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_services.dart';

void main() {
  group('MoavProfiles', () {
    test('defaults are exactly the recommended set (stock .env.example)', () {
      final recommended = MoavProfiles.all
          .where((p) => p.recommended)
          .map((p) => p.name)
          .toSet();
      expect(MoavProfiles.defaults.toSet(), recommended);
      expect(MoavProfiles.defaults, isNot(contains('monitoring')));
      expect(MoavProfiles.defaults, isNot(contains('gooserelay')));
      expect(MoavProfiles.defaults.toSet().length, MoavProfiles.defaults.length);
    });

    test('names are valid `moav start` arguments and flags are ENABLE_*', () {
      for (final p in MoavProfiles.all) {
        expect(MoavProfiles.validName.hasMatch(p.name), isTrue, reason: p.name);
        expect(p.onFlags, isNotEmpty, reason: p.name);
        for (final f in p.allFlags) {
          expect(MoavServices.validFlag.hasMatch(f), isTrue, reason: f);
        }
        expect(MoavProfiles.byName(p.name), same(p));
      }
      expect(MoavProfiles.byName('nope'), isNull);
    });

    test('enableFlagsFor: selected on, deselected off, opt-in never forced on',
        () {
      final f = MoavProfiles.enableFlagsFor(['wireguard', 'proxy', 'bogus']);
      expect(f['ENABLE_WIREGUARD'], isTrue);
      expect(f['ENABLE_REALITY'], isTrue);
      expect(f['ENABLE_SNELL'], isTrue);
      // AnyTLS is opt-in upstream: selecting proxy leaves it alone.
      expect(f.containsKey('ENABLE_ANYTLS'), isFalse);
      expect(f['ENABLE_AMNEZIAWG'], isFalse);
      expect(f['ENABLE_TELEMT'], isFalse);
      expect(f['ENABLE_MONITORING'], isFalse);
      expect(f['ENABLE_GOOSERELAY'], isFalse);
    });

    test('the default selection only turns off the two opt-in profiles', () {
      final f = MoavProfiles.enableFlagsFor(MoavProfiles.defaults);
      final off = f.entries.where((e) => !e.value).map((e) => e.key).toList();
      expect(off, unorderedEquals(['ENABLE_MONITORING', 'ENABLE_GOOSERELAY']));
      expect(f['ENABLE_DNSTT'], isTrue);
      expect(f['ENABLE_ADMIN_UI'], isTrue);
    });
  });

  group('MoavServices', () {
    test('toggles cover the compose services with a flag, not the support ones',
        () {
      expect(MoavServices.toggleFor('wireguard')!.onFlags, ['ENABLE_WIREGUARD']);
      expect(MoavServices.toggleFor('grafana')!.onFlags, ['ENABLE_MONITORING']);
      expect(MoavServices.toggleFor('telemt')!.onFlags, ['ENABLE_TELEMT']);
      expect(MoavServices.toggleFor('psiphon-conduit')!.onFlags, ['ENABLE_CONDUIT']);
      for (final s in ['certbot', 'decoy', 'dns-router', 'docker-proxy', 'bootstrap']) {
        expect(MoavServices.toggleFor(s), isNull, reason: s);
      }
    });

    test('sing-box: enable sets the five stock protocols, disable all six', () {
      final t = MoavServices.toggleFor('sing-box')!;
      final on = t.flags(enabled: true);
      expect(on.keys, isNot(contains('ENABLE_ANYTLS')));
      expect(on.values.every((v) => v), isTrue);
      expect(on.length, 5);
      final off = t.flags(enabled: false);
      expect(off.keys, contains('ENABLE_ANYTLS'));
      expect(off.values.every((v) => !v), isTrue);
      expect(off.length, 6);
    });

    test('flagDefault mirrors get_env_val defaults', () {
      expect(MoavServices.flagDefault('ENABLE_ANYTLS'), isFalse);
      expect(MoavServices.flagDefault('ENABLE_GOOSERELAY'), isFalse);
      expect(MoavServices.flagDefault('ENABLE_WIREGUARD'), isTrue);
      expect(MoavServices.flagDefault('ENABLE_MONITORING'), isTrue);
    });
  });

  group('ServiceFlags', () {
    const raw = '''
ENABLE_WIREGUARD=false
ENABLE_TELEMT="true"  # quoted, trailing comment
ENABLE_MONITORING=
ENABLE_SNOWFLAKE='TRUE'
DEFAULT_PROFILES="proxy wireguard admin"
NOT_A_FLAG=true
''';

    test('parseServiceFlags strips quotes and comments, keeps DEFAULT_PROFILES',
        () {
      final f = MoavCli.parseServiceFlags(raw, now: DateTime(2026));
      expect(f.values['ENABLE_WIREGUARD'], 'false');
      expect(f.values['ENABLE_TELEMT'], 'true');
      expect(f.values['ENABLE_SNOWFLAKE'], 'true');
      expect(f.values['ENABLE_MONITORING'], '');
      expect(f.values.containsKey('NOT_A_FLAG'), isFalse);
      expect(f.defaultProfiles, ['proxy', 'wireguard', 'admin']);
      expect(f.collectedAt, DateTime(2026));
    });

    test('isOn applies upstream defaults for unset or absent flags', () {
      final f = MoavCli.parseServiceFlags(raw);
      expect(f.isOn('ENABLE_WIREGUARD'), isFalse);
      expect(f.isOn('ENABLE_TELEMT'), isTrue);
      expect(f.isOn('ENABLE_MONITORING'), isTrue, reason: 'empty = default on');
      expect(f.isOn('ENABLE_REALITY'), isTrue, reason: 'absent = default on');
      expect(f.isOn('ENABLE_ANYTLS'), isFalse, reason: 'absent opt-in = off');
    });

    test('serviceEnabled: per service, any-of for multi-flag, null for support',
        () {
      final f = MoavCli.parseServiceFlags(raw);
      expect(f.serviceEnabled('wireguard'), isFalse);
      expect(f.serviceEnabled('wstunnel'), isFalse);
      expect(f.serviceEnabled('telemt'), isTrue);
      expect(f.serviceEnabled('grafana'), isTrue);
      expect(f.serviceEnabled('sing-box'), isTrue);
      expect(f.serviceEnabled('certbot'), isNull);
      final allOff = MoavCli.parseServiceFlags([
        for (final k in MoavServices.toggleFor('sing-box')!.allFlags) '$k=false',
      ].join('\n'));
      expect(allOff.serviceEnabled('sing-box'), isFalse);
    });

    test('empty output means no flags known, defaults apply', () {
      final f = MoavCli.parseServiceFlags('');
      expect(f.values, isEmpty);
      expect(f.defaultProfiles, isEmpty);
      expect(f.serviceEnabled('wireguard'), isTrue);
    });
  });

  group('MoavCli.setEnableFlags', () {
    test('emits one set_env per flag plus a read-back grep', () {
      final s = MoavCli.setEnableFlags({'ENABLE_WIREGUARD': true, 'ENABLE_TELEMT': false});
      expect(s, contains('set_env ENABLE_WIREGUARD true'));
      expect(s, contains('set_env ENABLE_TELEMT false'));
      expect(s, contains("grep -E '^(ENABLE_WIREGUARD|ENABLE_TELEMT)=' .env"));
      expect(s, contains('cd ${MoavCli.root}'));
      // Same replace / uncomment / append rules as upstream update_env_var.
      expect(s, contains(r'grep -qE "^#[[:space:]]*$1=" .env'));
      expect(s, contains(r'echo "$1=$2" >> .env'));
    });

    test('rejects anything that is not an ENABLE_* flag', () {
      expect(() => MoavCli.setEnableFlags({}), throwsArgumentError);
      expect(() => MoavCli.setEnableFlags({'DOMAIN': true}), throwsArgumentError);
      expect(() => MoavCli.setEnableFlags({'ENABLE_X; rm -rf /': true}),
          throwsArgumentError);
      expect(() => MoavCli.setEnableFlags({'enable_wireguard': true}),
          throwsArgumentError);
    });

    test('enable/disable are not moav verbs', () {
      expect(
        () => MoavCli.service(const ServiceAction(ServiceActionKind.enable, service: 'x')),
        throwsArgumentError,
      );
      expect(ServiceActionKind.enable.perService, isTrue);
      expect(ServiceActionKind.stop.perService, isFalse);
    });
  });
}
