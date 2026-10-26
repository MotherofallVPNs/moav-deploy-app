import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/ssh_endpoint.dart';

void main() {
  group('SshEndpoint.tryParse', () {
    test('bare hostname passes through lower-cased', () {
      final e = SshEndpoint.tryParse('BitChat.Center')!;
      expect(e.host, 'bitchat.center');
      expect(e.port, isNull);
      expect(e.username, isNull);
    });

    test('surrounding whitespace and a trailing slash are dropped', () {
      expect(
        SshEndpoint.tryParse('  bitchat.center/ \n')!.host,
        'bitchat.center',
      );
      expect(SshEndpoint.normalizeHost(' bitchat.center '), 'bitchat.center');
    });

    test('ssh:// scheme, user@ prefix and :port are peeled off', () {
      final e = SshEndpoint.tryParse('ssh://root@bitchat.center:2222')!;
      expect(e.host, 'bitchat.center');
      expect(e.port, 2222);
      expect(e.username, 'root');
      expect(e.toString(), 'root@bitchat.center:2222');
    });

    test('IPv4 literal with port', () {
      final e = SshEndpoint.tryParse('203.0.113.7:22')!;
      expect(e.host, '203.0.113.7');
      expect(e.port, 22);
    });

    test('bracketed IPv6 literal keeps the address and takes the port', () {
      final e = SshEndpoint.tryParse('[2001:db8::1]:2200')!;
      expect(e.host, '2001:db8::1');
      expect(e.port, 2200);
      expect(SshEndpoint.tryParse('[::1]')!.host, '::1');
    });

    test('unbracketed IPv6 literal is a host, not host:port', () {
      final e = SshEndpoint.tryParse('2001:db8::1')!;
      expect(e.host, '2001:db8::1');
      expect(e.port, isNull);
    });

    test('rejects empty, inner whitespace, bad port and junk', () {
      expect(SshEndpoint.tryParse(''), isNull);
      expect(SshEndpoint.tryParse('   '), isNull);
      expect(SshEndpoint.tryParse('bit chat.center'), isNull);
      expect(SshEndpoint.tryParse('host:99999'), isNull);
      expect(SshEndpoint.tryParse('host:abc'), isNull);
      expect(SshEndpoint.tryParse('[2001:db8::1'), isNull);
      expect(SshEndpoint.tryParse('host!name'), isNull);
    });

    test(
      'normalizeHost keeps unparseable text so validation can report it',
      () {
        expect(SshEndpoint.normalizeHost(' bad host '), 'bad host');
      },
    );
  });
}
