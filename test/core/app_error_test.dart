import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/security/redactor.dart';

void main() {
  group('AppError.from', () {
    test('timeout', () {
      final e = AppError.from(TimeoutException('x'));
      expect(e.kind, AppErrorKind.timeout);
      expect(e.retryable, isTrue);
      expect(e.hint, isNotNull);
    });

    test('DNS failure → unreachable with host in message', () {
      final e = AppError.from(
        const SocketException('Failed host lookup: \'nope.example\'',
            osError: OSError('nodename nor servname provided', 8)),
        host: 'nope.example',
        port: 22,
      );
      expect(e.kind, AppErrorKind.unreachable);
      expect(e.message, 'Could not find nope.example:22.');
    });

    test('network down → offline', () {
      final e = AppError.from(const SocketException('x',
          osError: OSError('Network is unreachable', 51)));
      expect(e.kind, AppErrorKind.offline);
    });

    test('refused / timed out / reset', () {
      expect(
        AppError.from(const SocketException('x', osError: OSError('Connection refused', 61))).kind,
        AppErrorKind.unreachable,
      );
      expect(
        AppError.from(const SocketException('x', osError: OSError('Operation timed out', 60))).kind,
        AppErrorKind.timeout,
      );
      expect(
        AppError.from(const SocketException('x', osError: OSError('Connection reset by peer', 54))).kind,
        AppErrorKind.transport,
      );
    });

    test('auth failures are not retryable and carry a hint', () {
      final e = AppError.from(SSHAuthFailError('denied'));
      expect(e.kind, AppErrorKind.auth);
      expect(e.retryable, isFalse);
      expect(e.message, 'Authentication failed.');
      expect(AppError.from(SSHAuthAbortError('abort')).kind, AppErrorKind.auth);
    });

    test('undecodable key → credential', () {
      final e = AppError.from(SSHKeyDecodeError('bad pem'));
      expect(e.kind, AppErrorKind.credential);
      expect(e.retryable, isFalse);
    });

    test('other SSH errors → transport', () {
      expect(AppError.from(SSHHandshakeError('x')).kind, AppErrorKind.transport);
      expect(AppError.from(SSHStateError('x')).kind, AppErrorKind.transport);
    });

    test('non-zero exit → commandFailed with scrubbed, clipped detail', () {
      final e = AppError.from(SshCommandException(
        'moav user add x',
        SshOutput(
          stdout: 'writing ADMIN_PASSWORD="pw"\n${'x' * 500}',
          stderr: 'vless://u@h:443',
          exitCode: 2,
        ),
      ));
      expect(e.kind, AppErrorKind.commandFailed);
      expect(e.message, 'The command failed on the server (exit 2).');
      expect(e.detail, isNot(contains('"pw"')));
      expect(e.detail, isNot(contains('vless://u')));
      expect(e.detail!.length, lessThanOrEqualTo(AppError.maxDetail + 1));
    });

    test('JSON / text parse failure → unexpectedOutput', () {
      final e = AppError.from(const FormatException('moav test did not return JSON: garbage'));
      expect(e.kind, AppErrorKind.unexpectedOutput);
      expect(e.detail, contains('garbage'));
    });

    test('ArgumentError → invalidInput, StateError keeps its message', () {
      expect(AppError.from(ArgumentError.value('a b', 'name', 'Use letters')).kind,
          AppErrorKind.invalidInput);
      final s = AppError.from(StateError('No stored credential for York'));
      expect(s.message, 'No stored credential for York');
    });

    test('unknown errors never expose a key, a stack, or the type name', () {
      final pem = '-----BEGIN OPENSSH PRIVATE KEY-----\n${'QUFB' * 80}\n-----END OPENSSH PRIVATE KEY-----';
      final e = AppError.from(Exception('parse $pem failed'));
      expect(e.kind, AppErrorKind.unknown);
      expect(e.message, 'Something went wrong.');
      expect(e.detail, contains(Redactor.keyMarker));
      expect(e.detail, isNot(contains('QUFBQUFB')));
      expect(e.detail, isNot(contains('Exception')));
      expect(e.toString(), isNot(contains('#0')));
    });

    test('idempotent and describeError delegates', () {
      const a = AppError(AppErrorKind.offline, 'No network connection.');
      expect(identical(AppError.from(a), a), isTrue);
      expect(SshMoavController.describeError(a), 'No network connection.');
      expect(SshMoavController.describeError(TimeoutException('t')),
          'The server did not respond in time.');
    });
  });
}
