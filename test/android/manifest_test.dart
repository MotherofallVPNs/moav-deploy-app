import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Debug and profile manifests add INTERNET for the Flutter tool; release
/// builds only get what main declares. v0.2.0 shipped without it.
void main() {
  test('main AndroidManifest declares INTERNET for release builds', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });
}
