import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/decoy/decoy_config.dart';
import 'package:moav_deploy/security/decoy/decoy_pin.dart';

/// Disguise mode (issue #15): the passcode is stored only as a salted
/// PBKDF2 hash and guessing is rate limited.
void main() {
  const fast = 1000;

  group('DecoyPin', () {
    test('accepts 4 to 12 digits only', () {
      expect(DecoyPin.isValid('1234'), isTrue);
      expect(DecoyPin.isValid('123456789012'), isTrue);
      expect(DecoyPin.isValid('123'), isFalse);
      expect(DecoyPin.isValid('1234567890123'), isFalse);
      expect(DecoyPin.isValid('12a4'), isFalse);
      expect(DecoyPin.isValid(' 1234'), isFalse);
      expect(DecoyPin.isValid(''), isFalse);
    });

    test('hash round-trips and rejects a wrong passcode', () async {
      final d = await DecoyPin.hash('2580', iterations: fast);
      expect(d.hash, isNot(contains('2580')));
      expect(
        await DecoyPin.verify('2580',
            hash: d.hash, salt: d.salt, iterations: fast),
        isTrue,
      );
      expect(
        await DecoyPin.verify('2581',
            hash: d.hash, salt: d.salt, iterations: fast),
        isFalse,
      );
      expect(
        await DecoyPin.verify('25800',
            hash: d.hash, salt: d.salt, iterations: fast),
        isFalse,
      );
    });

    test('every setup gets its own salt, so equal passcodes differ', () async {
      final a = await DecoyPin.hash('1111', iterations: fast);
      final b = await DecoyPin.hash('1111', iterations: fast);
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
    });

    test('a seeded generator gives a reproducible salt', () async {
      final a = await DecoyPin.hash('1111', iterations: fast, random: Random(7));
      final b = await DecoyPin.hash('1111', iterations: fast, random: Random(7));
      expect(a.salt, b.salt);
      expect(a.hash, b.hash);
    });

    test('garbage in the store verifies as false, never throws', () async {
      expect(
        await DecoyPin.verify('1234', hash: '!!', salt: '??', iterations: fast),
        isFalse,
      );
    });

    test('constantTimeEquals compares whole arrays', () {
      expect(DecoyPin.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(DecoyPin.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(DecoyPin.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
      expect(DecoyPin.constantTimeEquals([], []), isTrue);
    });
  });

  group('DecoyLockout', () {
    test('five free attempts, then doubling waits capped at an hour', () {
      for (var i = 0; i < 5; i++) {
        expect(DecoyLockout.after(i), Duration.zero, reason: '$i');
      }
      expect(DecoyLockout.after(5), const Duration(seconds: 30));
      expect(DecoyLockout.after(6), const Duration(minutes: 1));
      expect(DecoyLockout.after(7), const Duration(minutes: 2));
      expect(DecoyLockout.after(11), const Duration(minutes: 32));
      expect(DecoyLockout.after(12), const Duration(hours: 1));
      expect(DecoyLockout.after(40), const Duration(hours: 1));
      expect(DecoyLockout.after(1 << 20), const Duration(hours: 1));
    });
  });

  group('DecoyConfig', () {
    test('serialises every field and parses unknown gestures safely', () {
      final c = DecoyConfig(
        enabled: true,
        pinHash: 'h',
        salt: 's',
        iterations: 42,
        gesture: DecoyGesture.tapTitleFiveTimes,
        failedAttempts: 3,
        lockedUntil: DateTime.utc(2026, 10, 28, 12),
      );
      expect(DecoyConfig.fromJson(c.toJson()), c);
      expect(
        DecoyConfig.fromJson({'enabled': true, 'gesture': 'nope'}).gesture,
        DecoyGesture.longPressTitle,
      );
      expect(DecoyConfig.fromJson({}).hasPin, isFalse);
      expect(DecoyConfig.off.enabled, isFalse);
    });

    test('copyWith can clear the lockout', () {
      final c = DecoyConfig(
        enabled: true,
        failedAttempts: 6,
        lockedUntil: DateTime.utc(2026),
      );
      final reset = c.copyWith(failedAttempts: 0, clearLockout: true);
      expect(reset.failedAttempts, 0);
      expect(reset.lockedUntil, isNull);
      expect(c.copyWith(failedAttempts: 7).lockedUntil, DateTime.utc(2026));
    });
  });
}
