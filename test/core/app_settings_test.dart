import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_settings.dart';

/// The About screen's "Open App Settings" shortcut: the `app-settings:` URL
/// on iOS, a method channel into MainActivity on Android, nothing elsewhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppSettingsLink.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS launches the app-settings: URL, never the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final launched = <Uri>[];
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('iOS must not use the Android channel'),
    );
    final link = AppSettingsLink(launch: (url) async {
      launched.add(url);
      return true;
    });
    expect(AppSettingsLink.supported, isTrue);
    expect(await link.open(), isTrue);
    expect(launched.single.toString(), 'app-settings:');
  });

  test('iOS reports a refused launch as not opened', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await AppSettingsLink(launch: (_) async => false).open(), isFalse);
    expect(
      await AppSettingsLink(
        launch: (_) async => throw PlatformException(code: 'nope'),
      ).open(),
      isFalse,
    );
  });

  test('Android asks MainActivity over the settings channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final link = AppSettingsLink(
      launch: (_) async => fail('Android must not launch a URL'),
    );
    expect(AppSettingsLink.supported, isTrue);
    expect(await link.open(), isTrue);
    expect(calls, [AppSettingsLink.method]);
  });

  test('Android without a handler or with a native error is not opened',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await const AppSettingsLink().open(), isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'nope'),
    );
    expect(await const AppSettingsLink().open(), isFalse);
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await const AppSettingsLink().open(), isFalse);
  });

  test('desktop has no per-app settings page', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(AppSettingsLink.supported, isFalse);
    expect(
      await AppSettingsLink(launch: (_) async => fail('must not launch')).open(),
      isFalse,
    );
  });

  test('channel and method names match MainActivity.kt', () {
    final kotlin = File(
      'android/app/src/main/kotlin/org/motherofallvpns/moavdeploy/MainActivity.kt',
    ).readAsStringSync();
    expect(kotlin, contains('"${AppSettingsLink.channelName}"'));
    expect(kotlin, contains('"${AppSettingsLink.method}"'));
    expect(kotlin, contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'));
  });
}
