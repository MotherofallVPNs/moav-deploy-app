import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/key_service.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

void main() {
  const service = KeyService();

  test('generated key round-trips through dartssh2 and verifies signatures',
      () async {
    final key = await service.generateEd25519(comment: 'unit test!');

    expect(key.privateKeyPem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    expect(key.privateKeyPem.trim(), endsWith('-----END OPENSSH PRIVATE KEY-----'));

    final pairs = SSHKeyPair.fromPem(key.privateKeyPem);
    final pair = pairs.single as OpenSSHEd25519KeyPair;
    expect(pair.comment, 'unit-test-');

    // Public line matches what dartssh2 derives from the private key.
    final parts = key.publicKeyOpenSsh.split(' ');
    expect(parts, hasLength(3));
    expect(parts[0], 'ssh-ed25519');
    expect(parts[2], 'unit-test-');
    expect(base64Decode(parts[1]), pair.toPublicKey().encode());

    // Signature produced via the OpenSSH key verifies with the raw public key.
    final message = utf8.encode('hello moav');
    final sig = pair.sign(message);
    final verifier = ed25519.VerifyKey(pair.publicKey);
    expect(
      verifier.verify(
        signature: ed25519.Signature(sig.signature),
        message: message,
      ),
      isTrue,
    );

    // Each call yields a distinct key.
    final other = await service.generateEd25519();
    expect(other.publicKeyOpenSsh, isNot(key.publicKeyOpenSsh));
  });

  test('publicKeyFromPem derives the same line', () async {
    final key = await service.generateEd25519();
    expect(service.publicKeyFromPem(key.privateKeyPem), key.publicKeyOpenSsh);
    expect(service.publicKeyFromPem('garbage'), isNull);
  });

  test('validatePrivateKeyPem accepts generated keys', () async {
    final key = await service.generateEd25519();
    expect(service.validatePrivateKeyPem(key.privateKeyPem), isNull);
    expect(service.validatePrivateKeyPem(''), isNotNull);
    expect(service.validatePrivateKeyPem('nope'), isNotNull);
  });
}
