import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/key_export_service.dart';
import 'package:moav_deploy/security/key_service.dart';

void main() {
  test('encrypted SSH key export round-trips with its label', () async {
    final material = await const KeyService().generateEd25519();
    final bundle = await const KeyExportService().encrypt(
      label: 'Travel key',
      privateKeyPem: material.privateKeyPem,
      passphrase: 'a sufficiently long passphrase',
    );

    expect(bundle, startsWith(KeyExportService.prefix));
    expect(bundle, isNot(contains('OPENSSH PRIVATE KEY')));

    final decoded = await const KeyExportService().decrypt(
      bundle,
      'a sufficiently long passphrase',
    );
    expect(decoded.label, 'Travel key');
    expect(decoded.privateKeyPem, material.privateKeyPem);
  });

  test('encrypted SSH key export rejects the wrong passphrase', () async {
    final material = await const KeyService().generateEd25519();
    final bundle = await const KeyExportService().encrypt(
      label: 'Main key',
      privateKeyPem: material.privateKeyPem,
      passphrase: 'correct horse battery staple',
    );

    await expectLater(
      const KeyExportService().decrypt(bundle, 'incorrect passphrase'),
      throwsA(isA<FormatException>()),
    );
  });
}
