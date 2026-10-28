import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/ssh_connection.dart';

// Regression for the service start/stop crash:
// `type 'Utf8Decoder' is not a subtype of type
// 'StreamTransformer<Uint8List, String>'`. dartssh2's session streams are
// `Stream<Uint8List>`, which `.transform(utf8.decoder)` rejects at runtime.
Stream<Uint8List> _chunks(List<List<int>> parts) =>
    Stream<Uint8List>.fromIterable([for (final p in parts) Uint8List.fromList(p)]);

void main() {
  test('the old pattern fails on a Uint8List stream (what the device saw)', () {
    final Stream<List<int>> s = _chunks([utf8.encode('x')]);
    expect(() => s.transform(const Utf8Decoder()), throwsA(isA<TypeError>()));
  });

  test('decodeUtf8 accepts a Uint8List stream and yields text chunks', () async {
    final out = <String>[];
    await SshConnection.decodeUtf8(_chunks([
      utf8.encode('Stopping sing-box ... '),
      utf8.encode('done\n'),
    ])).forEach(out.add);
    expect(out.join(), 'Stopping sing-box ... done\n');
  });

  test('a multi-byte character split across chunks decodes intact', () async {
    final bytes = utf8.encode('✓ wireguard stopped');
    final out = <String>[];
    await SshConnection.decodeUtf8(_chunks([
      bytes.sublist(0, 2), // half of the check mark
      bytes.sublist(2),
    ])).forEach(out.add);
    expect(out.join(), '✓ wireguard stopped');
  });

  test('malformed bytes are replaced, never thrown', () async {
    final out = await SshConnection.decodeUtf8(_chunks([
      [0x61, 0xff, 0x62],
    ])).join();
    expect(out, 'a�b');
  });

  test('live output drains stdout and stderr the way run() does', () async {
    // Mirrors SshConnection.run's onOutput path with a Uint8List source.
    final stdout = StringBuffer();
    final seen = <String>[];
    Future<void> drain(Stream<List<int>> s, StringBuffer into) =>
        SshConnection.decodeUtf8(s).forEach((chunk) {
          into.write(chunk);
          seen.add(chunk);
        });
    await Future.wait([
      drain(_chunks([utf8.encode('a'), utf8.encode('b')]), stdout),
      drain(_chunks([utf8.encode('warn\n')]), StringBuffer()),
    ]);
    expect(stdout.toString(), 'ab');
    expect(seen, containsAll(['a', 'b', 'warn\n']));
  });
}
