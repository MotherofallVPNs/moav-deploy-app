import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/dns_check.dart';
import 'package:moav_deploy/core/dns_records.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

import '../support/fake_controller.dart';

/// The DNS-records helpers behind the install form's info popup: the zone
/// file mirrors upstream `generate_dns_zone_file`, the public-IP parser and
/// the server-side check parser.

const _domain = 'vpn.example.org';
const _ip = '203.0.113.9';

void main() {
  group('DnsRecords.forDomain', () {
    test('lists the six records in upstream order', () {
      final r = DnsRecords.forDomain(_domain, _ip);
      expect(r.map((e) => '${e.type} ${e.name} ${e.value}'), [
        'A vpn.example.org 203.0.113.9',
        'A dns.vpn.example.org 203.0.113.9',
        'NS t.vpn.example.org dns.vpn.example.org',
        'NS s.vpn.example.org dns.vpn.example.org',
        'NS m.vpn.example.org dns.vpn.example.org',
        'NS x.vpn.example.org dns.vpn.example.org',
      ]);
      expect(r.where((e) => e.optional).map((e) => e.name), ['x.vpn.example.org']);
    });

    test('zone lines use the BIND form with TTL 1 and a trailing dot on NS', () {
      final r = DnsRecords.forDomain(_domain, _ip);
      expect(r[0].zoneLine, 'vpn.example.org.\t1\tIN\tA\t203.0.113.9');
      expect(r[2].zoneLine, 't.vpn.example.org.\t1\tIN\tNS\tdns.vpn.example.org.');
    });
  });

  group('DnsRecords.zoneFile', () {
    final zone = DnsRecords.zoneFile(
      _domain,
      _ip,
      now: DateTime.utc(2026, 10, 30, 9, 5, 7),
    );

    test('mirrors the upstream header and comments', () {
      expect(zone, startsWith(';;\n;; MoaV DNS Records for vpn.example.org\n'));
      expect(zone, contains(';; Generated: 2026-10-30 09:05:07 UTC\n'));
      expect(zone, contains(';; Import into Cloudflare: DNS > Records > Import and Upload\n'));
      expect(zone, contains(';; Main domain: points to your server (DNS only, NOT proxied)\n'));
      expect(zone, contains(';; DNS tunnel NS delegations\n'));
      expect(zone, isNot(contains('—')), reason: 'no em-dashes');
    });

    test('every record line is present and importable', () {
      for (final r in DnsRecords.forDomain(_domain, _ip)) {
        expect(zone, contains('\n${r.zoneLine}\n'));
      }
      // Only comments and record lines: nothing a zone importer would reject.
      for (final line in zone.split('\n')) {
        if (line.isEmpty || line.startsWith(';;')) continue;
        final cols = line.split('\t');
        expect(cols.length, 5, reason: line);
        expect(cols[1], '1');
        expect(cols[2], 'IN');
        expect(cols[3], anyOf('A', 'NS'));
      }
    });

    test('stamps the current UTC time by default', () {
      final z = DnsRecords.zoneFile(_domain, _ip);
      expect(z, matches(RegExp(r';; Generated: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC')));
    });
  });

  group('DnsRecords.normalizeDomain / isValidDomain', () {
    test('lowercases and strips scheme, path and trailing dot', () {
      expect(DnsRecords.normalizeDomain(' HTTPS://VPN.Example.org/x '), 'vpn.example.org');
      expect(DnsRecords.normalizeDomain('vpn.example.org.'), 'vpn.example.org');
      expect(DnsRecords.normalizeDomain('vpn.example.org'), 'vpn.example.org');
    });

    test('accepts hostnames and rejects shell-sensitive input', () {
      expect(DnsRecords.isValidDomain('vpn.example.org'), isTrue);
      expect(DnsRecords.isValidDomain('a-b.c1.io'), isTrue);
      expect(DnsRecords.isValidDomain('example'), isFalse);
      expect(DnsRecords.isValidDomain(''), isFalse);
      expect(DnsRecords.isValidDomain('bad domain.org'), isFalse);
      expect(DnsRecords.isValidDomain("x.org'; rm -rf /"), isFalse);
      expect(DnsRecords.isValidDomain('-bad.org'), isFalse);
    });
  });

  group('PublicIp', () {
    test('recognizes literal IPv4 hosts', () {
      expect(PublicIp.isLiteralV4('203.0.113.9'), isTrue);
      expect(PublicIp.isLiteralV4(' 203.0.113.9 '), isTrue);
      expect(PublicIp.isLiteralV4('203.0.113.999'), isFalse);
      expect(PublicIp.isLiteralV4('vpn.example.org'), isFalse);
      expect(PublicIp.isLiteralV4('1.2.3'), isFalse);
    });

    test('firstPublicV4 skips private, loopback, CGNAT and docker ranges', () {
      const hostnameI = '10.0.0.5 172.17.0.1 192.168.1.4 100.64.3.2 127.0.0.1 '
          '169.254.1.1 203.0.113.9 198.51.100.2';
      expect(PublicIp.firstPublicV4(hostnameI), '203.0.113.9');
      expect(PublicIp.firstPublicV4('10.0.0.5 172.31.255.1'), isNull);
      expect(PublicIp.firstPublicV4(''), isNull);
    });

    test('firstPublicV4 reads curl output, ip addr lines and ignores noise', () {
      expect(PublicIp.firstPublicV4('203.0.113.9\n'), '203.0.113.9');
      expect(
        PublicIp.firstPublicV4('2: eth0 inet 198.51.100.7/24 brd 198.51.100.255'),
        '198.51.100.7',
      );
      expect(PublicIp.firstPublicV4('version 1.2.3.4.5 then 203.0.113.9'), '203.0.113.9');
      expect(PublicIp.firstPublicV4('256.1.1.1 then 203.0.113.9'), '203.0.113.9');
    });
  });

  group('DnsCheck.command', () {
    test('queries both A hosts and the four tunnel subdomains', () {
      final cmd = DnsCheck.command(_domain);
      expect(cmd, contains("D='vpn.example.org'"));
      expect(cmd, contains('for s in t s m x; do'));
      expect(cmd, contains('dig +short A'));
      expect(cmd, contains('AUTHORITY SECTION'));
      expect(cmd, contains('getent ahostsv4'));
      expect(cmd, contains('host -t NS'));
      expect(cmd, contains('nslookup -type=NS'));
      expect(cmd, contains('echo "TOOL none"; exit 0;'));
    });

    test('refuses a domain that is not a bare hostname', () {
      expect(() => DnsCheck.command("x.org'; id"), throwsArgumentError);
      expect(() => DnsCheck.command(''), throwsArgumentError);
    });
  });

  group('DnsCheck.parse', () {
    test('all records right', () {
      const out = 'TOOL dig\n'
          'A vpn.example.org 203.0.113.9,\n'
          'A dns.vpn.example.org 203.0.113.9,\n'
          'NS t.vpn.example.org dns.vpn.example.org.,\n'
          'NS s.vpn.example.org DNS.VPN.EXAMPLE.ORG.,\n'
          'NS m.vpn.example.org dns.vpn.example.org,\n'
          'NS x.vpn.example.org dns.vpn.example.org.,\n';
      final r = DnsCheck.parse(out, domain: _domain, serverIp: _ip);
      expect(r.tool, 'dig');
      expect(r.checks.map((c) => c.result), everyElement(CheckResult.pass));
      expect(r.ready, isTrue);
      expect(r.overall, CheckResult.pass);
      expect(r.summary, 'All 6 records resolve as expected.');
      expect(r.checks[0].detail, 'points to 203.0.113.9');
      expect(r.checks[2].detail, 'delegates to dns.vpn.example.org');
    });

    test('wrong IP, missing delegation and an optional miss', () {
      const out = 'TOOL host\n'
          'A vpn.example.org 198.51.100.1,198.51.100.2,\n'
          'A dns.vpn.example.org \n'
          'NS t.vpn.example.org dns.vpn.example.org.,\n'
          'NS s.vpn.example.org ns1.other.net.,\n'
          'NS m.vpn.example.org dns.vpn.example.org.,\n'
          'NS x.vpn.example.org \n';
      final r = DnsCheck.parse(out, domain: _domain, serverIp: _ip);
      expect(r.tool, 'host');
      expect(r.checks[0].result, CheckResult.fail);
      expect(r.checks[0].detail, 'points to 198.51.100.1, 198.51.100.2');
      expect(r.checks[0].found, ['198.51.100.1', '198.51.100.2']);
      expect(r.checks[1].result, CheckResult.fail);
      expect(r.checks[1].detail, 'does not resolve');
      expect(r.checks[2].result, CheckResult.pass);
      expect(r.checks[3].result, CheckResult.fail);
      expect(r.checks[3].detail, 'delegates to ns1.other.net');
      expect(r.checks[5].result, CheckResult.warn, reason: 'x is opt-in');
      expect(r.checks[5].detail, 'no NS delegation');
      expect(r.failed, 3);
      expect(r.warned, 1);
      expect(r.ready, isFalse);
      expect(r.overall, CheckResult.fail);
      expect(r.summary, startsWith('3 of 6 records need attention.'));
    });

    test('only the optional record missing still counts as ready', () {
      const out = 'TOOL dig\n'
          'A vpn.example.org 203.0.113.9,\n'
          'A dns.vpn.example.org 203.0.113.9,\n'
          'NS t.vpn.example.org dns.vpn.example.org.,\n'
          'NS s.vpn.example.org dns.vpn.example.org.,\n'
          'NS m.vpn.example.org dns.vpn.example.org.,\n'
          'NS x.vpn.example.org \n';
      final r = DnsCheck.parse(out, domain: _domain, serverIp: _ip);
      expect(r.ready, isTrue);
      expect(r.overall, CheckResult.warn);
      expect(r.summary, contains('1 optional record is not set up'));
    });

    test('no DNS tool on the box skips every record', () {
      final r = DnsCheck.parse('TOOL none\n', domain: _domain, serverIp: _ip);
      expect(r.tool, isNull);
      expect(r.unavailable, isTrue);
      expect(r.ready, isFalse);
      expect(r.overall, CheckResult.skip);
      expect(r.checks.map((c) => c.result), everyElement(CheckResult.skip));
      expect(r.summary, contains('no dig, host or nslookup'));
    });

    test('a record the script never printed is skipped, not failed', () {
      const out = 'TOOL dig\nA vpn.example.org 203.0.113.9,\n';
      final r = DnsCheck.parse(out, domain: _domain, serverIp: _ip);
      expect(r.checks[0].result, CheckResult.pass);
      expect(r.checks[1].result, CheckResult.skip);
      expect(r.checks[1].detail, 'not checked');
      expect(r.unavailable, isFalse);
    });

    test('ignores stray lines such as login banners', () {
      const out = 'Welcome to Ubuntu\nTOOL dig\nA vpn.example.org 203.0.113.9,\n'
          'garbage line here\n';
      final r = DnsCheck.parse(out, domain: _domain, serverIp: _ip);
      expect(r.checks[0].result, CheckResult.pass);
    });
  });

  group('SshMoavController DNS methods', () {
    SshMoavController controller(Future<SshOutput> Function(String cmd) answer,
        {String host = 'demo.example.org'}) {
      return SshMoavController(
        profile: ServerProfile(
          id: 's1',
          label: 'Demo',
          host: host,
          port: 22,
          username: 'root',
          authMethod: SshAuthMethod.importedKey,
        ),
        secretResolver: (_) async => 'secret',
        runner: (cmd, {allowFailure = false, timeout = const Duration(seconds: 60)}) =>
            answer(cmd),
      );
    }

    test('publicIp picks the first public address from the command output', () async {
      final seen = <String>[];
      final c = controller((cmd) async {
        seen.add(cmd);
        return const SshOutput(
          stdout: '203.0.113.9\n\n10.0.0.5 203.0.113.9 172.17.0.1\n',
          stderr: '',
          exitCode: 0,
        );
      });
      expect(await c.publicIp(), '203.0.113.9');
      expect(seen.single, DnsCheck.publicIpCommand);
    });

    test('publicIp falls back to a literal SSH host when the box says nothing', () async {
      final c = controller(
        (_) async => const SshOutput(stdout: '\n10.0.0.5\n', stderr: '', exitCode: 0),
        host: '198.51.100.4',
      );
      expect(await c.publicIp(), '198.51.100.4');
      final named = controller(
        (_) async => const SshOutput(stdout: '', stderr: '', exitCode: 7),
      );
      expect(await named.publicIp(), isNull);
    });

    test('checkDns runs the lookup script and parses its output', () async {
      String? ran;
      final c = controller((cmd) async {
        ran = cmd;
        return const SshOutput(
          stdout: 'TOOL dig\nA vpn.example.org 203.0.113.9,\n'
              'A dns.vpn.example.org 203.0.113.9,\n'
              'NS t.vpn.example.org dns.vpn.example.org.,\n'
              'NS s.vpn.example.org dns.vpn.example.org.,\n'
              'NS m.vpn.example.org dns.vpn.example.org.,\n'
              'NS x.vpn.example.org dns.vpn.example.org.,\n',
          stderr: '',
          exitCode: 0,
        );
      });
      final r = await c.checkDns(domain: _domain, serverIp: _ip);
      expect(ran, DnsCheck.command(_domain));
      expect(r.ready, isTrue);
    });

    test('the stub controller throws for the new methods unless overridden', () {
      final stub = StubMoavController();
      expect(stub.publicIp, throwsUnimplementedError);
    });
  });
}
