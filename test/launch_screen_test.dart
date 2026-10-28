import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/main.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

/// Branded launch screen (issue #27): the native splash on Android and iOS
/// shows the MoaV lockup, and the first Flutter frame repeats it in place.

const _res = 'android/app/src/main/res';
const _imageset = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

/// Never resolves: keeps FirstRunGate on its loading frame.
class _PendingStore implements OnboardingStore {
  @override
  Future<bool> isComplete() => Completer<bool>().future;
  @override
  Future<void> markComplete() async {}
}

void main() {
  group('Android', () {
    test('launch_background centres the lockup on the dark colour', () {
      for (final dir in ['drawable', 'drawable-v21']) {
        final xml = File('$_res/$dir/launch_background.xml').readAsStringSync();
        expect(xml, contains('@color/launch_background'));
        expect(xml, contains('android:src="@drawable/splash_logo"'));
        expect(xml, contains('android:gravity="center"'));
      }
      final colors = File('$_res/values/colors.xml').readAsStringSync();
      expect(colors, contains('name="launch_background">#0a0a0f<'));
    });

    test('Android 12+ system splash uses the mark on the dark colour', () {
      final v31 = File('$_res/values-v31/styles.xml').readAsStringSync();
      expect(
        v31,
        contains(
          'name="android:windowSplashScreenBackground">@color/launch_background<',
        ),
      );
      expect(
        v31,
        contains(
          'name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon<',
        ),
      );
    });

    test('no values-night: the night qualifier would shadow values-v31', () {
      expect(Directory('$_res/values-night').existsSync(), isFalse);
    });

    test('splash bitmaps exist at every density and scale together', () {
      final (baseW, baseH) = _pngSize('$_res/drawable-mdpi/splash_logo.png');
      for (final MapEntry(key: density, value: scale) in _densities.entries) {
        final (w, h) = _pngSize('$_res/drawable-$density/splash_logo.png');
        expect((w / scale - baseW).abs(), lessThan(1.5), reason: density);
        expect((h / scale - baseH).abs(), lessThan(1.5), reason: density);
        final (iw, ih) = _pngSize('$_res/drawable-$density/splash_icon.png');
        expect(
          (iw, ih),
          ((288 * scale).round(), (288 * scale).round()),
          reason: density,
        );
      }
    });
  });

  group('iOS', () {
    test('LaunchScreen.storyboard matches the 1x launch image', () {
      final (w, h) = _pngSize('$_imageset/LaunchImage.png');
      final storyboard = File(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      ).readAsStringSync();
      expect(
        storyboard,
        contains('<image name="LaunchImage" width="$w" height="$h"/>'),
      );
      expect(storyboard, contains('contentMode="center"'));
      // #0a0a0f as sRGB components.
      expect(
        storyboard,
        contains('red="0.039215686" green="0.039215686" blue="0.058823529"'),
      );
      for (final (scale, name) in [
        (2, 'LaunchImage@2x.png'),
        (3, 'LaunchImage@3x.png'),
      ]) {
        final (sw, sh) = _pngSize('$_imageset/$name');
        expect((sw / scale - w).abs(), lessThan(1.5), reason: name);
        expect((sh / scale - h).abs(), lessThan(1.5), reason: name);
      }
    });
  });

  group('Flutter first frame', () {
    testWidgets('FirstRunGate shows the lockup while the flag loads', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            onboardingStoreProvider.overrideWithValue(_PendingStore()),
          ],
          child: MaterialApp(
            theme: moavDarkTheme(),
            home: const FirstRunGate(child: SizedBox.shrink()),
          ),
        ),
      );
      expect(find.byType(MoavLockup), findsOneWidget);
      expect(find.byType(MoavMark), findsOneWidget);
      expect(find.text('MoaV'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      // Centred as a unit, like the native splash image.
      final lockup = tester.getRect(find.byType(MoavLockup));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(lockup.center, screen.center);
      expect(tester.getSize(find.byType(MoavMark)), const Size(120, 120));
    });

    testWidgets('holdFirstFrameForMark releases once the mark is decoded', (
      tester,
    ) async {
      final binding = tester.binding;
      binding.resetFirstFrameSent();
      await tester.runAsync(() async {
        holdFirstFrameForMark(binding);
        expect(binding.sendFramesToEngine, isFalse);
        for (var i = 0; i < 200 && !binding.sendFramesToEngine; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      expect(binding.sendFramesToEngine, isTrue);
      // The decoded mark is in the cache, ready for the first frame.
      final key = await const AssetImage(
        MoavMark.asset,
      ).obtainKey(ImageConfiguration.empty);
      expect(imageCache.containsKey(key), isTrue);
    });
  });
}
