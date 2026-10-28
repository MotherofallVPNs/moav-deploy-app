import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// `flutter drive` host side: receives screenshots taken by
/// `integration_test/screenshots_test.dart` and writes them to `shots/`.
Future<void> main() async {
  await integrationDriver(
    // A failed run still gets build/integration_response_data.json, so a
    // live e2e that breaks midway keeps the step results it did collect.
    writeResponseOnFailure: true,
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('shots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('screenshot → ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
