import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Disguise mode (issue #15): the native pieces the Dart side relies on.
/// Android swaps two predeclared activity-aliases; iOS has an alternate
/// app icon compiled into the asset catalog.

const _res = 'android/app/src/main/res';
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

(int, int) _pngSize(String path) {
  final data = ByteData.sublistView(File(path).readAsBytesSync());
  return (data.getUint32(16), data.getUint32(20));
}

/// The `<activity ...>...</activity>` or alias block whose name is [name].
String _component(String manifest, String tag, String name) {
  final start = manifest.indexOf('<$tag\n            android:name="$name"');
  expect(start, greaterThanOrEqualTo(0), reason: '$tag $name declared');
  final end = manifest.indexOf('</$tag>', start);
  return manifest.substring(start, end);
}

void main() {
  group('Android manifest', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    const launcher = 'android.intent.category.LAUNCHER';

    test('the activities themselves are not launcher entries', () {
      expect(_component(manifest, 'activity', '.MainActivity'),
          isNot(contains(launcher)));
      expect(_component(manifest, 'activity', '.DecoyActivity'),
          isNot(contains(launcher)));
    });

    test('MoaV alias is the default launcher entry', () {
      final alias = _component(manifest, 'activity-alias', '.MoavLauncher');
      expect(alias, contains(launcher));
      expect(alias, contains('android:targetActivity=".MainActivity"'));
      expect(alias, contains('android:label="MoaV Deploy"'));
      expect(alias, contains('android:icon="@mipmap/ic_launcher"'));
      expect(alias, isNot(contains('android:enabled="false"')));
    });

    test('Notes alias is declared but disabled until disguise is on', () {
      final alias = _component(manifest, 'activity-alias', '.NotesLauncher');
      expect(alias, contains(launcher));
      expect(alias, contains('android:targetActivity=".DecoyActivity"'));
      expect(alias, contains('android:enabled="false"'));
      expect(alias, contains('android:label="Notes"'));
      expect(alias, contains('android:icon="@mipmap/ic_notes"'));
      expect(alias, contains('android:roundIcon="@mipmap/ic_notes_round"'));
    });

    test('DecoyActivity has its own plain themes and the Notes label', () {
      final activity = _component(manifest, 'activity', '.DecoyActivity');
      expect(activity, contains('android:theme="@style/DecoyLaunchTheme"'));
      expect(activity, contains('android:resource="@style/DecoyNormalTheme"'));
      expect(activity, contains('android:label="Notes"'));
      expect(activity, contains('android:taskAffinity=""'));
      expect(activity, contains('android:launchMode="singleTop"'));
    });

    test('decoy themes never reference MoaV splash artwork', () {
      for (final dir in ['values', 'values-v31']) {
        final xml = File('$_res/$dir/styles.xml').readAsStringSync();
        final from = xml.indexOf('name="DecoyLaunchTheme"');
        expect(from, greaterThanOrEqualTo(0), reason: dir);
        final decoy = xml.substring(from);
        expect(decoy, isNot(contains('splash_logo')), reason: dir);
        expect(decoy, isNot(contains('splash_icon')), reason: dir);
        expect(decoy, isNot(contains('launch_background')), reason: dir);
        expect(decoy, contains('@color/decoy_background'), reason: dir);
      }
      final v31 = File('$_res/values-v31/styles.xml').readAsStringSync();
      expect(
        v31,
        contains('name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_notes<'),
      );
      final colors = File('$_res/values/colors.xml').readAsStringSync();
      expect(colors, contains('name="decoy_background">#fffdf7<'));
      expect(colors, contains('name="ic_notes_background">#f5b82e<'));
    });

    test('Kotlin channel names match the Dart side and the aliases', () {
      const dir = 'android/app/src/main/kotlin/org/motherofallvpns/moavdeploy';
      final channel = File('$dir/DecoyChannel.kt').readAsStringSync();
      expect(channel, contains('"org.motherofallvpns.moavdeploy/decoy"'));
      expect(channel, contains('org.motherofallvpns.moavdeploy.MoavLauncher'));
      expect(channel, contains('org.motherofallvpns.moavdeploy.NotesLauncher'));
      expect(channel, contains('DONT_KILL_APP'));
      expect(File('$dir/DecoyActivity.kt').readAsStringSync(),
          contains('class DecoyActivity : MainActivity()'));
      expect(File('$dir/MainActivity.kt').readAsStringSync(),
          contains('open class MainActivity'));
    });

    test('Notes icons exist at every density and scale together', () {
      final adaptive = File('$_res/mipmap-anydpi-v26/ic_notes.xml')
          .readAsStringSync();
      expect(adaptive, contains('@color/ic_notes_background'));
      expect(adaptive, contains('@drawable/ic_notes_foreground'));
      expect(File('$_res/mipmap-anydpi-v26/ic_notes_round.xml').existsSync(),
          isTrue);
      for (final MapEntry(key: density, value: scale) in _densities.entries) {
        final legacy = (48 * scale).round();
        expect(_pngSize('$_res/mipmap-$density/ic_notes.png'),
            (legacy, legacy), reason: density);
        expect(_pngSize('$_res/mipmap-$density/ic_notes_round.png'),
            (legacy, legacy), reason: density);
        final fg = (108 * scale).round();
        expect(_pngSize('$_res/drawable-$density/ic_notes_foreground.png'),
            (fg, fg), reason: density);
      }
    });
  });

  group('iOS', () {
    test('NotesIcon alternate icon is compiled into the app', () {
      final pbx =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(
        'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = NotesIcon;'
            .allMatches(pbx)
            .length,
        3,
        reason: 'Debug, Release and Profile of the Runner target',
      );
      expect(
        'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES;'
            .allMatches(pbx)
            .length,
        3,
      );
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('"org.motherofallvpns.moavdeploy/decoy"'));
      expect(swift, contains('static let notesIcon = "NotesIcon"'));
      expect(swift, contains('setAlternateIconName'));
      expect(swift, contains('"renameLauncher": false'));
    });

    test('NotesIcon.appiconset mirrors AppIcon sizes with real files', () {
      const dir = 'ios/Runner/Assets.xcassets';
      final app = jsonDecode(
          File('$dir/AppIcon.appiconset/Contents.json').readAsStringSync());
      final notes = jsonDecode(
          File('$dir/NotesIcon.appiconset/Contents.json').readAsStringSync());
      final appImages = (app['images'] as List).cast<Map<String, Object?>>();
      final notesImages =
          (notes['images'] as List).cast<Map<String, Object?>>();
      expect(notesImages, hasLength(appImages.length));
      for (final image in notesImages) {
        final pt = double.parse((image['size'] as String).split('x').first);
        final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
        final px = (pt * scale).round();
        final file = '$dir/NotesIcon.appiconset/${image['filename']}';
        expect(File(file).existsSync(), isTrue, reason: file);
        expect(_pngSize(file), (px, px), reason: file);
      }
    });
  });

  test('the Notes master icon is a brand-new asset, not the MoaV mark', () {
    expect(_pngSize('assets/icon/notes-icon-1024.png'), (1024, 1024));
    final notes = File('assets/icon/notes-icon-1024.png').readAsBytesSync();
    final moav = File('assets/icon/icon-1024.png').readAsBytesSync();
    expect(notes, isNot(moav));
  });
}
