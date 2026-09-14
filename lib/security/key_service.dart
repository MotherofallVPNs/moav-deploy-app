import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

/// An ed25519 key pair held in memory only while the user is adding a server.
class Ed25519KeyMaterial {
  const Ed25519KeyMaterial({
    required this.privateKeyPem,
    required this.publicKeyOpenSsh,
  });

  /// OpenSSH-format private key. Goes straight into [SecureCredStore].
  final String privateKeyPem;

  /// `ssh-ed25519 AAAA… comment` line for the "Install my public key" helper.
  final String publicKeyOpenSsh;
}

/// Generates and validates SSH keys on-device.
class KeyService {
  const KeyService();

  /// Generates a fresh ed25519 key pair on-device.
  ///
  /// The seed comes from pinenacl's CSPRNG (the same primitive dartssh2 uses to
  /// sign). The private key is serialised as an unencrypted
  /// `OPENSSH PRIVATE KEY` block, which is what [SSHKeyPair.fromPem] consumes
  /// for auth; the public line is standard `authorized_keys` syntax.
  Future<Ed25519KeyMaterial> generateEd25519({
    String comment = 'moav-deploy',
  }) async {
    final signing = ed25519.SigningKey.generate();
    // OpenSSH stores the 64-byte (seed ‖ public) form as the private key.
    final privateKey = Uint8List.fromList(signing.asTypedList);
    final publicKey = Uint8List.fromList(signing.verifyKey.asTypedList);
    final safeComment = sanitizeComment(comment);
    final pair = OpenSSHEd25519KeyPair(publicKey, privateKey, safeComment);
    return Ed25519KeyMaterial(
      privateKeyPem: pair.toPem(),
      publicKeyOpenSsh: publicKeyLine(pair, safeComment),
    );
  }

  /// `ssh-ed25519 <base64 wire blob> <comment>`.
  static String publicKeyLine(OpenSSHEd25519KeyPair pair, String comment) {
    final blob = base64Encode(pair.toPublicKey().encode());
    return comment.isEmpty
        ? 'ssh-ed25519 $blob'
        : 'ssh-ed25519 $blob $comment';
  }

  /// Comments end up in `authorized_keys`; keep them shell- and file-safe.
  static String sanitizeComment(String comment) =>
      comment.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '-');

  /// Derives the public `authorized_keys` line from a private key PEM, or
  /// `null` if the PEM is not a single usable ed25519 key.
  String? publicKeyFromPem(String pem, {String comment = 'moav-deploy'}) {
    try {
      final pairs = SSHKeyPair.fromPem(pem.trim());
      final pair = pairs.whereType<OpenSSHEd25519KeyPair>().firstOrNull;
      if (pair == null) return null;
      final c = pair.comment.isEmpty ? comment : pair.comment;
      return publicKeyLine(pair, sanitizeComment(c));
    } on Object catch (_) {
      return null;
    }
  }

  /// Validates a pasted private key. Returns an error message, or `null` when
  /// the PEM parses to at least one usable key pair.
  String? validatePrivateKeyPem(String pem, {String? passphrase}) {
    final trimmed = pem.trim();
    if (trimmed.isEmpty) return 'Paste a private key';
    try {
      final pairs = SSHKeyPair.fromPem(trimmed, passphrase);
      if (pairs.isEmpty) return 'No key found in the pasted text';
      return null;
    } on Object catch (_) {
      return 'Could not parse this key (expected OpenSSH or PEM ed25519)';
    }
  }
}
