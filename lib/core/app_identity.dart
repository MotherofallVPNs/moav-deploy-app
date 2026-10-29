import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the About screen shows about the running build: the version from
/// the package metadata and, on Android, the APK signing fingerprint.
class AppIdentity {
  const AppIdentity({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.signingFingerprints,
    this.packageName = '',
  });

  final String appName;
  final String version;
  final String buildNumber;

  /// Bundle identifier (iOS) or application id (Android), from the package
  /// metadata; empty when unknown.
  final String packageName;

  /// SHA-256 of each signing certificate as `AA:BB:...`. Empty when the
  /// platform does not expose it (iOS, tests) or the lookup failed.
  final List<String> signingFingerprints;

  /// `0.2.7 (10)`: the pubspec version and build number.
  String get versionLabel =>
      buildNumber.isEmpty ? version : '$version ($buildNumber)';

  /// The first (current) signer, or null when none is known.
  String? get signingFingerprint =>
      signingFingerprints.isEmpty ? null : signingFingerprints.first;
}

/// Reads the APK's signing certificates from Android's PackageManager
/// through a small method channel in `MainActivity.kt`.
///
/// Nothing is bundled at build time: the value is whatever certificate
/// signed the APK that is actually installed, so a re-signed copy shows a
/// different fingerprint than the one the project publishes.
class AppSigning {
  const AppSigning([this._channel = const MethodChannel(channelName)]);

  // Mirrored in android/.../MainActivity.kt.
  static const channelName = 'org.motherofallvpns.moavdeploy/signing';
  static const method = 'signingFingerprints';

  final MethodChannel _channel;

  /// Fingerprints of the running build's signers; empty when the platform
  /// has no handler (iOS, tests) or the native side threw.
  Future<List<String>> fingerprints() async {
    try {
      final raw = await _channel.invokeListMethod<String>(method);
      return List.unmodifiable(raw ?? const <String>[]);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}

final appSigningProvider = Provider<AppSigning>((_) => const AppSigning());

final appIdentityProvider = FutureProvider<AppIdentity>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final fingerprints = await ref.watch(appSigningProvider).fingerprints();
  return AppIdentity(
    appName: info.appName.isEmpty ? 'MoaV Deploy' : info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
    signingFingerprints: fingerprints,
    packageName: info.packageName,
  );
});
