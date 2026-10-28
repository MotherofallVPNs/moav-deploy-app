import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/bundle_zip.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';

import '../support/fake_box.dart';

/// "Share .zip": the whole bundle directory zipped on the box in one shell
/// round trip, with a client-side zip of the fetched configs as fallback.

String _framed(List<int> zip) => '__ZIP__\n${base64.encode(zip)}\n__END__\n';

Bundle _bundle() => Bundle(
      user: 'alice',
      fetchedAt: DateTime(2026),
      path: '/opt/moav/outputs/bundles/alice',
      entries: const [
        BundleEntry(
          protocol: 'reality',
          fileName: 'reality.txt',
          content: 'vless://alice@h:443\n',
          qrPayload: 'vless://alice@h:443',
        ),
        BundleEntry(
          protocol: 'wireguard',
          fileName: 'alice-wg.conf',
          content: '[Interface]\nPrivateKey = FAKE=\n',
          qrPayload: '[Interface]\nPrivateKey = FAKE=',
        ),
        BundleEntry(
          protocol: 'trusttunnel',
          fileName: 'trusttunnel.toml',
          content: '# tt\n',
        ),
      ],
    );

void main() {
  group('bundleArchive command', () {
    test('zips the quoted bundle dir to stdout with graceful bail-outs', () {
      final cmd = MoavCli.bundleArchive('alice');
      expect(cmd, contains("cd '/opt/moav/outputs/bundles/alice'"));
      expect(cmd, contains('__NOBUNDLE__'));
      expect(cmd, contains('command -v zip >/dev/null 2>&1 || { echo "__NOZIP__"'));
      expect(cmd, contains('-gt ${MoavCli.maxBundleArchiveKb} ] && { echo "__TOOBIG__"'));
      expect(cmd, contains('zip -qr - . | base64 | tr -d'));
      expect(cmd, contains(r"tr -d '\n'"));
      expect(cmd, contains('echo "__ZIP__"'));
      expect(cmd, contains('echo "__END__"'));
    });

    test('refuses names that are not a plain user name', () {
      expect(() => MoavCli.bundleArchive(r'$(id)'), throwsArgumentError);
      expect(() => MoavCli.bundleArchive('../etc'), throwsArgumentError);
    });
  });

  group('parseBundleArchive', () {
    final zip = [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0];

    test('decodes the framed base64 blob', () {
      expect(MoavCli.parseBundleArchive(_framed(zip)), zip);
    });

    test('is null whenever the box bailed out or the transfer was cut', () {
      expect(MoavCli.parseBundleArchive('__NOBUNDLE__\n'), isNull);
      expect(MoavCli.parseBundleArchive('__NOZIP__\n'), isNull);
      expect(MoavCli.parseBundleArchive('__TOOBIG__\n'), isNull);
      expect(MoavCli.parseBundleArchive(''), isNull);
      // Lost the __END__ line: the base64 may be incomplete.
      expect(MoavCli.parseBundleArchive('__ZIP__\n${base64.encode(zip)}\n'),
          isNull);
      expect(MoavCli.parseBundleArchive('__ZIP__\n!!notbase64\n__END__\n'),
          isNull);
      expect(MoavCli.parseBundleArchive('__ZIP__\n\n__END__\n'), isNull);
    });
  });

  group('getBundleArchive', () {
    test('runs one command and returns the server zip bytes', () async {
      final zip = ZipEncoder().encodeBytes(
          Archive()..add(ArchiveFile.string('README.html', '<html>')));
      final box = FakeBox.always(_framed(zip));
      final bytes = await box.controller.getBundleArchive('alice');
      expect(box.ran, hasLength(1));
      expect(box.ran.single, MoavCli.bundleArchive('alice'));
      expect(bytes, zip);
      final files = ZipDecoder().decodeBytes(bytes!).files;
      expect(files.map((f) => f.name), ['README.html']);
    });

    test('a box without zip answers null so the app falls back', () async {
      final box = FakeBox.always('__NOZIP__\n');
      expect(await box.controller.getBundleArchive('alice'), isNull);
    });

    test('user names are validated before anything runs', () async {
      final box = FakeBox.always('');
      await expectLater(
          box.controller.getBundleArchive('a;rm -rf /'), throwsArgumentError);
      expect(box.ran, isEmpty);
    });
  });

  group('encodeBundleZip', () {
    test('zips every fetched entry under its bundle file name', () {
      final Uint8List bytes = encodeBundleZip(_bundle());
      final files = ZipDecoder().decodeBytes(bytes).files;
      expect(files.map((f) => f.name),
          ['reality.txt', 'alice-wg.conf', 'trusttunnel.toml']);
      final wg = files.firstWhere((f) => f.name == 'alice-wg.conf');
      expect(utf8.decode(wg.readBytes()!), '[Interface]\nPrivateKey = FAKE=\n');
    });

    test('the shared file is named after the user', () {
      expect(bundleZipFileName('alice'), 'alice-moav-bundle.zip');
    });
  });
}
