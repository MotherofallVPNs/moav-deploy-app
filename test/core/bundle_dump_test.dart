import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// The bundle is fetched with one shell round trip (`MoavCli.bundleDump`)
/// instead of an SFTP walk that cost four round trips per file.
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

class _Box {
  _Box(this.stdout);

  final String stdout;
  final ran = <String>[];

  Future<SshOutput> run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    ran.add(command);
    return SshOutput(stdout: stdout, stderr: '', exitCode: 0);
  }
}

SshMoavController _controller(_Box box) => SshMoavController(
      profile: const ServerProfile(
        id: 't',
        label: 't',
        host: 'h',
        port: 22,
        username: 'root',
        authMethod: SshAuthMethod.importedKey,
      ),
      secretResolver: (_) async => throw StateError('no ssh in unit tests'),
      runner: box.run,
    );

void main() {
  group('bundleDump command', () {
    test('targets the quoted bundle dir and skips images, guide and zips', () {
      final cmd = MoavCli.bundleDump('alice');
      expect(cmd, contains("cd '/opt/moav/outputs/bundles/alice'"));
      expect(cmd, contains('__NOBUNDLE__'));
      expect(cmd, contains('*.png|*.PNG|*.html|*.HTML|*.zip|*.ZIP) continue'));
      expect(cmd, contains('-gt ${MoavCli.maxBundleFileBytes}'));
      // printf must receive a literal backslash-n, not a newline.
      expect(cmd, contains(r"printf '__FILE__ %s\n'"));
      expect(cmd, contains(r"tr -d '\n'"));
    });

    test('refuses names that are not a plain user name', () {
      expect(() => MoavCli.bundleDump(r'$(id)'), throwsArgumentError);
      expect(() => MoavCli.bundleDump('../etc'), throwsArgumentError);
    });
  });

  group('parseBundleDump', () {
    test('decodes every framed file of the fixture', () {
      final files = MoavCli.parseBundleDump(_fixture('bundle_dump.txt'))!;
      expect(files.map((f) => f.name), [
        'alice-awg.conf',
        'alice-wg.conf',
        'alice-wgws.conf',
        'dnstt.txt',
        'hysteria2.txt',
        'reality.txt',
        'shadowsocks.txt',
        'snell.txt',
        'subscription.txt',
        'telegram-proxy-link.txt',
        'trojan.txt',
        'trusttunnel.toml',
        'xhttp-vless.txt',
      ]);
      final wg = files.firstWhere((f) => f.name == 'alice-wg.conf');
      expect(wg.content, startsWith('[Interface]\nPrivateKey = FAKEPRIVATEKEY=\n'));
      expect(wg.content, contains('Endpoint = 203.0.113.10:51820'));
      final sub = files.firstWhere((f) => f.name == 'subscription.txt');
      expect(sub.content.trim(), 'https://vpn.example.com/sub/alice?token=faketoken');
    });

    test('a missing bundle directory is null, an empty one is empty', () {
      expect(MoavCli.parseBundleDump('__NOBUNDLE__\n'), isNull);
      expect(MoavCli.parseBundleDump('__END__\n'), isEmpty);
    });

    test('a truncated dump keeps the files that arrived whole', () {
      final full = _fixture('bundle_dump.txt').split('\n');
      final cut = full.take(5).join('\n'); // two files, then a lone header
      final files = MoavCli.parseBundleDump(cut)!;
      expect(files.map((f) => f.name), ['alice-awg.conf', 'alice-wg.conf']);
    });

    test('non-UTF-8 bytes do not throw', () {
      final files = MoavCli.parseBundleDump('__FILE__ x.conf\n/w==\n__END__\n')!;
      expect(files.single.content, '�');
    });
  });

  group('getBundle', () {
    test('runs one command and maps files to sorted bundle entries', () async {
      final box = _Box(_fixture('bundle_dump.txt'));
      final bundle = await _controller(box).getBundle('alice');
      expect(box.ran, hasLength(1));
      expect(box.ran.single, MoavCli.bundleDump('alice'));
      expect(bundle.path, '/opt/moav/outputs/bundles/alice');
      expect(bundle.entries.map((e) => e.protocol), [
        'subscription',
        'reality',
        'hysteria2',
        'trojan',
        'shadowsocks',
        'xhttp',
        'wireguard',
        'amneziawg',
        'wireguard-wstunnel',
        'telegram',
        'trusttunnel',
        'dnstt',
        'snell',
      ]);
      expect(bundle.withQr.map((e) => e.protocol), isNot(contains('snell')));
      expect(bundle.withQr.map((e) => e.protocol), contains('wireguard'));
    });

    test('no bundle directory is a clear error, not an empty bundle', () async {
      final box = _Box('__NOBUNDLE__\n');
      await expectLater(
        _controller(box).getBundle('alice'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains("No bundle found for 'alice'"))),
      );
    });

    test('user names are validated before anything runs', () async {
      final box = _Box('');
      await expectLater(
          _controller(box).getBundle('a;rm -rf /'), throwsArgumentError);
      expect(box.ran, isEmpty);
    });
  });
}
