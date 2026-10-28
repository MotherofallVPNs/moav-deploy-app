import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Hashing and checking of the disguise passcode.
///
/// PBKDF2-HMAC-SHA256 with a random 16-byte salt. The passcode is digits
/// only (4 to 12) so it can be typed on the Notes passcode sheet without
/// looking out of place. Offline guessing is bounded by the secure store
/// (Keystore / Keychain wrapped) and online guessing by [DecoyLockout].
abstract final class DecoyPin {
  static const defaultIterations = 100000;
  static const minLength = 4;
  static const maxLength = 12;
  static const saltBytes = 16;
  static const hashBits = 256;

  static final _digits = RegExp('^[0-9]{$minLength,$maxLength}\$');

  /// True for a passcode the setup form accepts.
  static bool isValid(String pin) => _digits.hasMatch(pin);

  /// Derives a fresh salt and the hash for [pin]. Both are base64.
  static Future<({String hash, String salt})> hash(
    String pin, {
    int iterations = defaultIterations,
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(saltBytes, (_) => rng.nextInt(256)),
    );
    final digest = await _derive(pin, salt, iterations);
    return (hash: base64Encode(digest), salt: base64Encode(salt));
  }

  /// Constant-time check of [pin] against a stored hash and salt.
  static Future<bool> verify(
    String pin, {
    required String hash,
    required String salt,
    int iterations = defaultIterations,
  }) async {
    final Uint8List expected;
    final Uint8List saltBytes;
    try {
      expected = base64Decode(hash);
      saltBytes = base64Decode(salt);
    } on FormatException {
      return false;
    }
    final actual = await _derive(pin, saltBytes, iterations);
    return constantTimeEquals(actual, expected);
  }

  static Future<List<int>> _derive(
    String pin,
    List<int> salt,
    int iterations,
  ) async {
    final kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: hashBits);
    final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  /// Compares every byte regardless of where the first mismatch is.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Rate limit for passcode attempts: five free tries, then a wait that
/// doubles with every further failure, capped at one hour.
abstract final class DecoyLockout {
  static const freeAttempts = 5;
  static const base = Duration(seconds: 30);
  static const max = Duration(hours: 1);

  /// How long to wait after [failedAttempts] consecutive failures.
  static Duration after(int failedAttempts) {
    if (failedAttempts < freeAttempts) return Duration.zero;
    final doublings = min(failedAttempts - freeAttempts, 12);
    final wait = base * (1 << doublings);
    return wait > max ? max : wait;
  }
}
