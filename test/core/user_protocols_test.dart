import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_services.dart';

/// Device feedback: the user detail view listed the six user stores from
/// `moav user list --json` as if they were the protocols. The protocols a
/// user gets are the server's `ENABLE_*` flags crossed with those stores.
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final users = MoavCli.parseUserListJson(_fixture('json/user_list.json'))!;
  final flags = MoavCli.parseServiceFlags(_fixture('env_flags.txt'));

  test('alice (five stores) gets every enabled protocol of those stores', () {
    final alice = users.firstWhere((u) => u.name == 'alice');
    expect(alice.protocols,
        ['amneziawg', 'sing-box', 'telegram', 'wireguard', 'xray']);
    expect(MoavServices.userProtocols(alice.protocols, flags: flags), [
      'reality',
      'trojan',
      'hysteria2',
      'shadowsocks',
      'xhttp',
      'xdns',
      'wireguard',
      'wireguard-wstunnel',
      'amneziawg',
      'telegram',
      'dnstt',
      'masterdns',
    ]);
  });

  test('a store the user is not in contributes nothing', () {
    final carol = users.firstWhere((u) => u.name == 'carol');
    expect(carol.protocols, ['wireguard']);
    expect(MoavServices.userProtocols(carol.protocols, flags: flags),
        ['wireguard', 'wireguard-wstunnel', 'dnstt', 'masterdns']);
  });

  test('flags turned off in .env drop their protocol', () {
    final bob = users.firstWhere((u) => u.name == 'bob');
    final got = MoavServices.userProtocols(bob.protocols, flags: flags);
    expect(got, contains('trusttunnel'));
    expect(got, isNot(contains('snell'))); // ENABLE_SNELL=false
    expect(got, isNot(contains('anytls'))); // ENABLE_ANYTLS=false
    expect(got, isNot(contains('slipstream'))); // ENABLE_SLIPSTREAM=false
    expect(got, isNot(contains('wireguard'))); // not in that store
  });

  test('without .env the upstream defaults apply (opt-ins stay off)', () {
    final got = MoavServices.userProtocols(['sing-box', 'xray']);
    expect(got, [
      'reality',
      'trojan',
      'hysteria2',
      'shadowsocks',
      'snell',
      'xhttp',
      'xdns',
      'dnstt',
      'slipstream',
      'masterdns',
    ]);
    expect(got, isNot(contains('anytls')));
    expect(got, isNot(contains('cdn')));
    expect(got, isNot(contains('gooserelay')));
  });

  test('every protocol id has a display title', () {
    for (final p in MoavServices.userProtocolFlags) {
      expect(BundleEntry.titles, contains(p.id), reason: p.id);
    }
  });
}
