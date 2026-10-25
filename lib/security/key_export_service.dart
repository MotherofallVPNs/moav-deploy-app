import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Password-encrypted, portable SSH-key backup. No plaintext key material is
/// written to disk: callers share/paste the returned `moav-key-v1:` string.
class KeyExportService {
  const KeyExportService();

  static const prefix = 'moav-key-v1:';

  Future<String> encrypt({
    required String label,
    required String privateKeyPem,
    required String passphrase,
  }) async {
    if (passphrase.length < 10) {
      throw ArgumentError('Use a passphrase of at least 10 characters');
    }
    final salt = _random(16);
    final nonce = _random(12);
    final key = await _derive(passphrase, salt);
    final clear = utf8.encode(
      jsonEncode({'label': label, 'privateKeyPem': privateKeyPem}),
    );
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
    );
    return prefix +
        base64UrlEncode(
          utf8.encode(
            jsonEncode({
              'salt': base64Encode(salt),
              'nonce': base64Encode(nonce),
              'ciphertext': base64Encode(box.cipherText),
              'mac': base64Encode(box.mac.bytes),
            }),
          ),
        );
  }

  Future<({String label, String privateKeyPem})> decrypt(
    String bundle,
    String passphrase,
  ) async {
    if (!bundle.trim().startsWith(prefix)) {
      throw const FormatException('Not a MoaV encrypted key export');
    }
    try {
      final outer =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(bundle.trim().substring(prefix.length)),
                ),
              )
              as Map<String, dynamic>;
      final salt = base64Decode(outer['salt'] as String);
      final nonce = base64Decode(outer['nonce'] as String);
      final key = await _derive(passphrase, salt);
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(outer['ciphertext'] as String),
          nonce: nonce,
          mac: Mac(base64Decode(outer['mac'] as String)),
        ),
        secretKey: key,
      );
      final inner = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return (
        label: inner['label'] as String,
        privateKeyPem: inner['privateKeyPem'] as String,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong passphrase or damaged export');
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Could not read this encrypted export');
    }
  }

  Future<SecretKey> _derive(String passphrase, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  List<int> _random(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
