import 'dart:io';

/// Reads a text fixture under `test/fixtures/`.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Reads a MoaV 2.3.x `--json` capture under `test/fixtures/json/`.
String jsonFixture(String name) => fixture('json/$name');
