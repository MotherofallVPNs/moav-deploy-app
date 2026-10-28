import 'decoy_pin.dart';

/// The secret action that opens the passcode prompt inside the Notes decoy.
enum DecoyGesture {
  /// Press and hold the "Notes" title in the app bar.
  longPressTitle('Press and hold the Notes title'),

  /// Tap the "Notes" title five times in quick succession.
  tapTitleFiveTimes('Tap the Notes title five times');

  const DecoyGesture(this.label);

  /// Short description shown in the disguise settings.
  final String label;

  static DecoyGesture parse(Object? name) => values.firstWhere(
        (g) => g.name == name,
        orElse: () => DecoyGesture.longPressTitle,
      );
}

/// Persisted disguise settings. Stored as one JSON blob in the secure store
/// (see `SecureCredStore.writeDecoy`) and preserved by the emergency wipe.
///
/// The passcode is never stored: only a PBKDF2-HMAC-SHA256 hash with a
/// per-device random salt. Failed attempts and the lockout deadline live
/// here too so a restart does not reset the rate limit.
class DecoyConfig {
  const DecoyConfig({
    required this.enabled,
    this.pinHash,
    this.salt,
    this.iterations = DecoyPin.defaultIterations,
    this.gesture = DecoyGesture.longPressTitle,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  /// Disguise never set up (or turned off): the app is MoaV Deploy.
  static const off = DecoyConfig(enabled: false);

  final bool enabled;

  /// Base64 PBKDF2 output; null until a passcode has been set.
  final String? pinHash;

  /// Base64 random salt that goes with [pinHash].
  final String? salt;
  final int iterations;
  final DecoyGesture gesture;
  final int failedAttempts;

  /// UTC instant before which no passcode attempt is accepted.
  final DateTime? lockedUntil;

  /// True when a passcode exists, i.e. the secret unlock can succeed.
  bool get hasPin => pinHash != null && salt != null;

  DecoyConfig copyWith({
    bool? enabled,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockout = false,
  }) =>
      DecoyConfig(
        enabled: enabled ?? this.enabled,
        pinHash: pinHash,
        salt: salt,
        iterations: iterations,
        gesture: gesture,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedUntil: clearLockout ? null : (lockedUntil ?? this.lockedUntil),
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'pinHash': pinHash,
        'salt': salt,
        'iterations': iterations,
        'gesture': gesture.name,
        'failedAttempts': failedAttempts,
        'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
      };

  factory DecoyConfig.fromJson(Map<String, Object?> json) => DecoyConfig(
        enabled: json['enabled'] == true,
        pinHash: json['pinHash'] as String?,
        salt: json['salt'] as String?,
        iterations: (json['iterations'] as num?)?.toInt() ??
            DecoyPin.defaultIterations,
        gesture: DecoyGesture.parse(json['gesture']),
        failedAttempts: (json['failedAttempts'] as num?)?.toInt() ?? 0,
        lockedUntil: switch (json['lockedUntil']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is DecoyConfig &&
      other.enabled == enabled &&
      other.pinHash == pinHash &&
      other.salt == salt &&
      other.iterations == iterations &&
      other.gesture == gesture &&
      other.failedAttempts == failedAttempts &&
      other.lockedUntil == lockedUntil;

  @override
  int get hashCode => Object.hash(
      enabled, pinHash, salt, iterations, gesture, failedAttempts, lockedUntil);

  @override
  String toString() =>
      'DecoyConfig(enabled: $enabled, gesture: ${gesture.name}, '
      'failedAttempts: $failedAttempts, hasPin: $hasPin)';
}
