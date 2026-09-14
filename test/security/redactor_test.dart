import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/app_log.dart';
import 'package:moav_deploy/security/key_service.dart';
import 'package:moav_deploy/security/redactor.dart';

void main() {
  group('Redactor', () {
    test('removes a real OpenSSH private key, keeps surrounding text', () async {
      final key = await const KeyService().generateEd25519();
      final text = 'Could not save: ${key.privateKeyPem} (server york)';
      final out = Redactor.scrub(text);
      expect(out, 'Could not save: ${Redactor.keyMarker} (server york)');
      // Neither the header nor any 40-char slice of the key body survives.
      final body = key.privateKeyPem.split('\n').where((l) => !l.startsWith('-----')).join();
      for (var i = 0; i + 40 <= body.length; i += 40) {
        expect(out, isNot(contains(body.substring(i, i + 40))));
      }
    });

    test('removes a truncated key (no END line) and PKCS#8 / RSA headers', () {
      final cut = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMw';
      expect(Redactor.scrub('x $cut'), 'x ${Redactor.keyMarker}');
      expect(
        Redactor.scrub('-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----'),
        Redactor.keyMarker,
      );
      expect(
        Redactor.scrub('-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAA\n-----END ENCRYPTED PRIVATE KEY-----'),
        Redactor.keyMarker,
      );
    });

    test('redacts passwords and passphrases in every common shape', () {
      expect(Redactor.scrub('ADMIN_PASSWORD="hunter2"'), 'ADMIN_PASSWORD=[redacted]');
      expect(Redactor.scrub("storePassword='s3cr3t' keyPassword=k3y"),
          'storePassword=[redacted] keyPassword=[redacted]');
      expect(Redactor.scrub('passphrase: correct-horse'), 'passphrase: [redacted]');
      expect(Redactor.scrub('{"password": "p@ss", "user": "bob"}'),
          '{"password": "[redacted]", "user": "bob"}');
      expect(Redactor.scrub('{"private_key":"abc","short_id":"0123"}'),
          '{"private_key":"[redacted]","short_id":"[redacted]"}');
      expect(Redactor.scrub('PrivateKey = cGxhaW4=\nPresharedKey = eA=='),
          'PrivateKey = [redacted]\nPresharedKey = [redacted]');
    });

    test('redacts share links and subscription URLs from bundles', () {
      const links = [
        'vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?security=reality#york',
        'hysteria2://pw@203.0.113.7:443/?sni=example.org',
        'trojan://pw@203.0.113.7:8443',
        'ss://YWVzLTI1Ni1nY206cGFzcw@203.0.113.7:8388#tag',
        'tg://proxy?server=203.0.113.7&port=443&secret=ee0123',
        'https://t.me/proxy?server=203.0.113.7&port=443&secret=ee0123',
        'https://example.org/sub/0123456789abcdef',
      ];
      for (final l in links) {
        final out = Redactor.scrub('open $l now');
        expect(out, startsWith('open [redacted '), reason: l);
        expect(out, endsWith(' link] now'), reason: l);
        expect(out, isNot(contains('203.0.113.7')), reason: l);
        expect(out, isNot(contains('0123')), reason: l);
      }
    });

    test('leaves ordinary error text and public keys alone', () {
      const plain = 'Authentication failed for root@york.example:22 (exit 255)';
      expect(Redactor.scrub(plain), plain);
      const pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxvbmdlbm91Z2hwdWJsaWNrZXlibG9i moav-deploy';
      expect(Redactor.scrub(pub), pub);
      expect(Redactor.scrub(''), '');
      expect(Redactor.scrub(null), '');
    });
  });

  group('AppLog', () {
    late List<String> lines;
    setUp(() {
      lines = [];
      AppLog.sink = lines.add;
    });
    tearDown(() => AppLog.sink = null);

    test('scrubs key material before it reaches the sink', () async {
      final key = await const KeyService().generateEd25519();
      AppLog.error('ssh', StateError('boom ${key.privateKeyPem}'));
      AppLog.info('deploy', 'ADMIN_PASSWORD="pw" written');
      AppLog.warn('bundle', 'got vless://u@h:443#x');
      expect(lines, hasLength(3));
      expect(lines.join('\n'), isNot(contains('PRIVATE KEY-----\nb3Bl')));
      expect(lines[0], contains(Redactor.keyMarker));
      expect(lines[1], '[I] deploy: ADMIN_PASSWORD=[redacted] written');
      expect(lines[2], '[W] bundle: got [redacted vless link]');
      for (final l in lines) {
        expect(Redactor.looksSecret(l), isFalse);
      }
    });

    test('is silent when no sink is installed (release default)', () {
      AppLog.sink = null;
      AppLog.error('x', Exception('y'));
      expect(lines, isEmpty);
    });
  });
}
