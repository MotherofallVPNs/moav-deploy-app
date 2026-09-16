import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// `flutter drive` host side: receives screenshots taken by
/// `integration_test/screenshots_test.dart` and writes them to `shots/`.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('shots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('screenshot → ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
