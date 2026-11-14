// `flutter drive` host side for store_shots.dart: serves `GET /shot?name=<n>`
// and grabs the whole device screen, status bar included.
// Env: MOAV_SHOT_CAPTURE=simctl:<udid>|adb:<serial>, MOAV_SHOT_DIR, MOAV_SHOT_PORT.
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final env = Platform.environment;
  final capture = env['MOAV_SHOT_CAPTURE'];
  final dir = env['MOAV_SHOT_DIR'];
  final port = int.parse(env['MOAV_SHOT_PORT'] ?? '45055');
  if (capture == null || dir == null) {
    stderr.writeln('MOAV_SHOT_CAPTURE and MOAV_SHOT_DIR are required');
    exit(64);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.listen((req) async {
    try {
      final name = req.uri.queryParameters['name'];
      if (req.uri.path != '/shot' || name == null || !_safeName.hasMatch(name)) {
        req.response.statusCode = HttpStatus.notFound;
      } else {
        final file = File('$dir/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(await _grab(capture));
        stdout.writeln('screenshot → ${file.path}');
      }
    } on Object catch (e) {
      stderr.writeln('capture failed: $e');
      req.response.statusCode = HttpStatus.internalServerError;
    }
    await req.response.close();
  });

  try {
    await integrationDriver();
  } finally {
    await server.close(force: true);
  }
}

final _safeName = RegExp(r'^[a-z0-9-]+$');

Future<List<int>> _grab(String capture) async {
  final sep = capture.indexOf(':');
  final kind = sep < 0 ? capture : capture.substring(0, sep);
  final device = capture.substring(sep + 1);
  switch (kind) {
    case 'simctl':
      // CoreSimulator may not be allowed to write to an external volume, so
      // the file goes through the system temp directory.
      final tmp = File('${Directory.systemTemp.path}/moav-store-shot-$pid.png');
      try {
        final r = await Process.run(
          'xcrun',
          ['simctl', 'io', device, 'screenshot', '--type=png', tmp.path],
        );
        if (r.exitCode != 0) throw StateError('simctl screenshot: ${r.stderr}');
        return await tmp.readAsBytes();
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    case 'adb':
      final r = await Process.run(
        'adb',
        ['-s', device, 'exec-out', 'screencap', '-p'],
        stdoutEncoding: null,
      );
      if (r.exitCode != 0) throw StateError('adb screencap: ${r.stderr}');
      return r.stdout as List<int>;
    default:
      throw ArgumentError('MOAV_SHOT_CAPTURE must be simctl:<udid> or adb:<serial>');
  }
}
