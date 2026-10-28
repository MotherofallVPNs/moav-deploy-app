import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/security/redactor.dart';

import '../support/fixtures.dart';

/// `moav donate` has no `--json` (MoaV 2.3.1, lib/donate.sh); these pin the
/// exact invocations and the text parsers against captured output shapes.
void main() {
  group('commands', () {
    test('env snippet checks presence of MAHSANET_API_KEY and never prints it',
        () {
      expect(DonateCli.env, contains(MoavCli.envReader));
      expect(DonateCli.env, contains('mahsanet_key=present'));
      expect(DonateCli.env, contains('mahsanet_key=absent'));
      // No line echoes the variable's value.
      expect(DonateCli.env, isNot(contains('echo "\$(ev MAHSANET_API_KEY)"')));
      expect(DonateCli.env, isNot(contains('key=\$(ev MAHSANET_API_KEY)')));
    });

    test('status and list run non-interactively from the checkout', () {
      expect(DonateCli.status,
          '${MoavCli.prelude}MOAV_NONINTERACTIVE=1 "\$M" donate status 2>&1');
      expect(DonateCli.list,
          '${MoavCli.prelude}MOAV_NONINTERACTIVE=1 "\$M" donate list 2>&1');
    });

    test('setup answers "1" then the key from the 0600 file, then deletes it',
        () {
      final c = DonateCli.setupMahsaNet;
      expect(c, startsWith(MoavCli.prelude));
      expect(c, contains('K="\$HOME/${DonateCli.keyFile}"'));
      expect(c, contains('{ echo 1; cat "\$K"; } | MOAV_NONINTERACTIVE=1 "\$M" donate setup 2>&1'));
      expect(c, contains('rm -f "\$K"'));
      expect(c, endsWith('exit \$rc'));
    });

    test('submit feeds count and prefix on stdin; confirm takes its default',
        () {
      final c = DonateCli.submit(count: 3, prefix: 'mahsa');
      expect(c, startsWith(MoavCli.prelude));
      expect(c, contains("printf '%s\\n%s\\n' 3 'mahsa' | "));
      expect(c, endsWith('MOAV_NONINTERACTIVE=1 "\$M" donate submit 2>&1'));
      expect(DonateCli.submit(count: 1, force: true),
          endsWith('donate submit --force 2>&1'));
    });

    test('submit refuses what upstream would reject', () {
      expect(() => DonateCli.submit(count: 0), throwsArgumentError);
      expect(() => DonateCli.submit(count: 51), throwsArgumentError);
      expect(() => DonateCli.submit(count: 1, prefix: ''), throwsArgumentError);
      expect(() => DonateCli.submit(count: 1, prefix: 'a b'), throwsArgumentError);
      expect(() => DonateCli.submit(count: 1, prefix: "x'y"), throwsArgumentError);
      expect(DonateCli.submit(count: 50, prefix: 'Donor_1-x'), contains("'Donor_1-x'"));
    });

    test('form validation mirrors the command checks', () {
      expect(DonateCli.validateCount('1'), isNull);
      expect(DonateCli.validateCount('50'), isNull);
      expect(DonateCli.validateCount('0'), isNotNull);
      expect(DonateCli.validateCount('51'), isNotNull);
      expect(DonateCli.validateCount('x'), isNotNull);
      expect(DonateCli.validatePrefix('mahsa'), isNull);
      expect(DonateCli.validatePrefix(''), isNotNull);
      expect(DonateCli.validatePrefix('ma hsa'), isNotNull);
    });
  });

  group('parseEnv', () {
    test('key present with settings', () {
      final env = DonateCli.parseEnv('''
__DONATE__
mahsanet_key=present
protocols=reality hysteria2 xhttp
pool=mahsa
conduit_enabled=true
snowflake_enabled=false
__END__
''', now: DateTime(2026));
      expect(env, isNotNull);
      expect(env!.mahsaNetKeyPresent, isTrue);
      expect(env.protocols, ['reality', 'hysteria2', 'xhttp']);
      expect(env.pool, 'mahsa');
      expect(env.conduitEnabled, isTrue);
      expect(env.snowflakeEnabled, isFalse);
      expect(env.toString(), isNot(contains('secret')));
    });

    test('key absent; unset settings take upstream defaults', () {
      final env = DonateCli.parseEnv('''
__DONATE__
mahsanet_key=absent
protocols=
pool=
conduit_enabled=
snowflake_enabled=
__END__
''');
      expect(env!.mahsaNetKeyPresent, isFalse);
      expect(env.protocols, DonateCli.defaultProtocols);
      expect(env.pool, isNull);
      expect(env.conduitEnabled, isTrue);
      expect(env.snowflakeEnabled, isTrue);
    });

    test('no checkout: markers missing', () {
      expect(DonateCli.parseEnv(''), isNull);
      expect(DonateCli.parseEnv('bash: moav: not found'), isNull);
    });
  });

  group('parseStatus', () {
    test('configured key, both bandwidth services running', () {
      final s = DonateCli.parseStatus(fixture('donate_status.txt'), now: DateTime(2026))!;
      expect(s.mahsaNet.configured, isTrue);
      expect(s.mahsaNet.hasStats, isTrue);
      expect(s.mahsaNet.total, 12);
      expect(s.mahsaNet.active, 11);
      expect(s.mahsaNet.inactive, 1);
      expect(s.mahsaNet.statsError, isNull);

      expect(s.conduit.enabled, isTrue);
      expect(s.conduit.running, isTrue);
      expect(s.conduit.bandwidthMbps, 100);
      expect(s.conduit.maxClients, 200);
      expect(s.conduit.connected, 37);
      expect(s.conduit.uploaded, '41.2 GB');
      expect(s.conduit.downloaded, '118.6 GB');

      expect(s.snowflake.running, isTrue);
      expect(s.snowflake.bandwidthMbps, 5);
      expect(s.snowflake.maxClients, 50);
      expect(s.snowflake.served, 1284);
      expect(s.snowflake.uploaded, '6.1 GB');
      expect(s.snowflake.downloaded, '9.8 GB');
    });

    test('nothing configured: not configured, stopped, disabled', () {
      final s = DonateCli.parseStatus(fixture('donate_status_unconfigured.txt'))!;
      expect(s.mahsaNet.configured, isFalse);
      expect(s.mahsaNet.hasStats, isFalse);
      expect(s.conduit.enabled, isTrue);
      expect(s.conduit.running, isFalse);
      expect(s.conduit.hasTraffic, isFalse);
      expect(s.snowflake.enabled, isFalse);
      expect(s.snowflake.running, isFalse);
    });

    test('key set but MahsaNet unreachable', () {
      final s = DonateCli.parseStatus('''
  MahsaNet
    ○ Could not fetch stats

  Psiphon Conduit
    ✓ Running — 100 Mbps, 200 max clients

  Tor Snowflake
    ✓ Running — 5 Mbps, 50 capacity
    Stats unavailable — enable monitoring: moav start monitoring
''')!;
      expect(s.mahsaNet.configured, isTrue);
      expect(s.mahsaNet.hasStats, isFalse);
      expect(s.mahsaNet.statsError, 'Could not fetch stats');
      expect(s.conduit.hasTraffic, isFalse);
      expect(s.snowflake.running, isTrue);
      expect(s.snowflake.hasTraffic, isFalse);
    });

    test('not a status printout', () {
      expect(DonateCli.parseStatus(''), isNull);
      expect(DonateCli.parseStatus('Unknown command: donate'), isNull);
    });
  });

  group('parseList', () {
    test('rows without their share links', () {
      final rows = DonateCli.parseList(fixture('donate_list.txt'))!;
      expect(rows.length, 3);
      expect(rows[0].index, 1);
      expect(rows[0].scheme, 'vless');
      expect(rows[0].active, isTrue);
      expect(rows[0].healthPercent, 100);
      expect(rows[0].used, 33);
      expect(rows[1].scheme, 'hysteria2');
      expect(rows[1].healthPercent, 97);
      expect(rows[2].active, isFalse);
      expect(rows[2].healthPercent, isNull);
      expect(rows[2].used, 0);
      // The credential-bearing link text is not carried anywhere.
      for (final r in rows) {
        expect('$r', isNot(contains('://')));
        expect(r.scheme, isNot(contains('averysecretpassword')));
      }
    });

    test('empty and unparseable', () {
      expect(DonateCli.parseList('ℹ No configs donated yet.\n'), isEmpty);
      expect(DonateCli.parseList('ℹ Total: 0 config(s)\n'), isEmpty);
      expect(DonateCli.parseList('✗ No donation service configured'), isNull);
      expect(DonateCli.parseList(''), isNull);
    });
  });

  group('setup and submit outcomes', () {
    test('keySaved and setupFailure', () {
      expect(DonateCli.keySaved(fixture('donate_setup_ok.txt')), isTrue);
      const bad = '  API Key: ℹ Validating API key...\n\x1b[0;31m✗\x1b[0m Invalid API key (HTTP 401)\n';
      expect(DonateCli.keySaved(bad), isFalse);
      expect(DonateCli.setupFailure(bad), 'MahsaNet rejected the key: Invalid API key (HTTP 401)');
      expect(DonateCli.setupFailure(''), 'moav donate setup did not save the key');
    });

    test('parseSubmit reads the summary block', () {
      final r = DonateCli.parseSubmit(fixture('donate_submit.txt'))!;
      expect(r.usersCreated, 2);
      expect(r.donated, 3);
      expect(r.skipped, 0);
      expect(r.failed, 1);
      expect(r.quotaHit, isFalse);
    });

    test('parseSubmit flags a quota stop and handles skipped', () {
      final r = DonateCli.parseSubmit('''
  Donation Summary
  Users created: 5
  Configs donated: 2
  Skipped: 4
⚠ Stopped early: MahsaNet submission quota reached.
''')!;
      expect(r.usersCreated, 5);
      expect(r.donated, 2);
      expect(r.skipped, 4);
      expect(r.quotaHit, isTrue);
    });

    test('no summary: failure sentence from the ✗ line, scrubbed', () {
      const out = 'ℹ Validating API key...\n✗ Invalid API key (HTTP 403)\n';
      expect(DonateCli.parseSubmit(out), isNull);
      expect(DonateCli.submitFailure(out), 'Donation stopped: Invalid API key (HTTP 403)');
      expect(DonateCli.submitFailure(''), 'moav donate submit did not finish');
      // A link preview in the error path never survives.
      final leak = DonateCli.submitFailure('✗ bad link vless://uuid@host:443?x=1\n');
      expect(leak, isNot(contains('uuid@host')));
    });
  });

  test('the redactor already covers the .env variable name', () {
    final s = Redactor.scrub('MAHSANET_API_KEY=mk_live_abcdef123456');
    expect(s, isNot(contains('mk_live_abcdef123456')));
    expect(s, contains(Redactor.valueMarker));
  });
}
