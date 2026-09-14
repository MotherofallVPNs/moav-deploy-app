import 'package:dartssh2/dartssh2.dart';

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
  /// M1 follow-up: dartssh2 does not expose key *generation*, so this will use
  /// a small ed25519 primitive and emit OpenSSH private-key format.
  Future<Ed25519KeyMaterial> generateEd25519({String comment = 'moav-deploy'}) {
    throw UnimplementedError('On-device key generation lands later in M1');
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
