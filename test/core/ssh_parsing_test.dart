import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

void main() {
  group('parsePing', () {
    test('installed with version (ANSI-coloured)', () {
      final c = SshMoavController.parsePing(
        '__ok__\n\n\x1b[0;36mMoaV\x1b[0m v2.2.2\n\x1b[1;37m━━━\x1b[0m\n',
      );
      expect(c.reachable, isTrue);
      expect(c.moavInstalled, isTrue);
      expect(c.moavVersion, '2.2.2');
      expect(c.error, isNull);
    });

    test('not installed', () {
      final c = SshMoavController.parsePing('__ok__\n__nomoav__\n');
      expect(c.moavInstalled, isFalse);
      expect(c.moavVersion, isNull);
    });

    test('unexpected shell', () {
      final c = SshMoavController.parsePing('garbage');
      expect(c.reachable, isTrue);
      expect(c.moavInstalled, isNull);
      expect(c.error, isNotNull);
    });
  });

  test('shellQuote and stripAnsi', () {
    expect(SshConnection.shellQuote("a'b"), "'a'\\''b'");
    expect(SshConnection.stripAnsi('\x1b[1;32m✓\x1b[0m done'), '✓ done');
  });

  test('describeError hides internals', () {
    expect(
      SshMoavController.describeError(
        Exception('x' * 500),
      ).length,
      lessThanOrEqualTo(201),
    );
  });
}
