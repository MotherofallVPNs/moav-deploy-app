import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_identity.dart';

/// The signing fingerprint comes from Android's PackageManager over a
/// method channel; every other platform answers "not available".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppSigning.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns what MainActivity reports', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, AppSigning.method);
      return ['AA:BB', 'CC:DD'];
    });
    expect(await const AppSigning().fingerprints(), ['AA:BB', 'CC:DD']);
  });

  test('no handler (iOS, tests) means no fingerprint, not an error',
      () async {
    expect(await const AppSigning().fingerprints(), isEmpty);
  });

  test('a native failure also degrades to no fingerprint', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'nope'),
    );
    expect(await const AppSigning().fingerprints(), isEmpty);
  });

  test('channel and method names match MainActivity.kt', () {
    final kotlin = File(
      'android/app/src/main/kotlin/org/motherofallvpns/moavdeploy/MainActivity.kt',
    ).readAsStringSync();
    expect(kotlin, contains('"${AppSigning.channelName}"'));
    expect(kotlin, contains('"${AppSigning.method}"'));
  });

  test('version label is "version (build)"', () {
    const id = AppIdentity(
      appName: 'MoaV Deploy',
      version: '0.2.7',
      buildNumber: '10',
      signingFingerprints: ['AA'],
    );
    expect(id.versionLabel, '0.2.7 (10)');
    expect(id.signingFingerprint, 'AA');
    const noBuild = AppIdentity(
      appName: 'x',
      version: '1.0',
      buildNumber: '',
      signingFingerprints: [],
    );
    expect(noBuild.versionLabel, '1.0');
    expect(noBuild.signingFingerprint, isNull);
  });
}
