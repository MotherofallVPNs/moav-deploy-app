import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/security/app_log.dart';

import '../support/fake_box.dart';
import '../support/fixtures.dart';

/// The one-session-per-server contract of [SshMoavController], exercised
/// without a socket: the secret resolver is the first step of a handshake,
/// so gating it shows how many handshakes concurrent callers start.
void main() {
  group('connection reuse', () {
    test('concurrent first calls share one handshake and one failure', () async {
      var resolves = 0;
      final gate = Completer<String?>();
      final c = SshMoavController(
        profile: unitProfile,
        secretResolver: (_) {
          resolves++;
          return gate.future;
        },
      );
      addTearDown(c.dispose);

      final a = c.ping();
      final b = c.ping();
      await Future<void>.delayed(Duration.zero);
      expect(resolves, 1, reason: 'the second caller joins the pending handshake');

      gate.completeError(StateError('vault locked'));
      final ra = await a;
      final rb = await b;
      expect(ra.reachable, isFalse);
      expect(ra.error, contains('vault locked'));
      expect(rb.error, ra.error);
      expect(ra.failure!.kind, AppErrorKind.unknown);
    });

    test('after a failed handshake the next call starts a fresh one', () async {
      var resolves = 0;
      final c = SshMoavController(
        profile: unitProfile,
        secretResolver: (_) async {
          resolves++;
          throw StateError('still locked');
        },
      );
      addTearDown(c.dispose);
      await c.ping();
      await c.ping();
      expect(resolves, 2);
    });

    test('a missing credential is reported by label, never dialled', () async {
      final c = SshMoavController(
        profile: unitProfile,
        secretResolver: (_) async => null,
      );
      addTearDown(c.dispose);
      final r = await c.ping();
      expect(r.reachable, isFalse);
      expect(r.moavInstalled, isNull);
      expect(r.error, 'No stored credential for t');

      final empty = SshMoavController(
        profile: unitProfile,
        secretResolver: (_) async => '',
      );
      addTearDown(empty.dispose);
      expect((await empty.ping()).error, 'No stored credential for t');
    });

    test('an injected runner bypasses the handshake entirely', () async {
      var resolves = 0;
      final box = FakeBox.byTail({tail(MoavCli.statusJson): ok(jsonFixture('status.json'))});
      final c = SshMoavController(
        profile: unitProfile,
        secretResolver: (_) async {
          resolves++;
          return 'pem';
        },
        runner: box.run,
      );
      final s = await c.status();
      expect(s.services, isNotEmpty);
      expect(resolves, 0);
    });
  });

  group('streamed output', () {
    test('service output reaches onOutput as it would from the session', () async {
      final box = FakeBox.containing({
        'stop': ok('Stopping sing-box ...\n', stderr: 'warn: slow\n'),
      });
      final chunks = <String>[];
      await box.controller.service(
        const ServiceAction(ServiceActionKind.stop, service: 'sing-box'),
        onOutput: chunks.add,
      );
      expect(chunks.join(), contains('Stopping sing-box'));
      expect(chunks.join(), contains('warn: slow'));
    });

    test('enable streams both steps: the .env write, then moav start', () async {
      final box = FakeBox.containing({
        'set_env': ok('ENABLE_WIREGUARD=true\n'),
        'start': ok('wireguard started\n'),
      });
      final chunks = <String>[];
      await box.controller.service(
        const ServiceAction(ServiceActionKind.enable, service: 'wireguard'),
        onOutput: chunks.add,
      );
      expect(chunks, ['ENABLE_WIREGUARD=true\n', 'wireguard started\n']);
    });

    test('a failing command surfaces its output as the error detail', () async {
      final box = FakeBox.containing({
        'restart': failed('✗ no such service: nope\n', code: 1),
      });
      Object? thrown;
      try {
        await box.controller.service(
          const ServiceAction(ServiceActionKind.restart, service: 'nope'),
        );
      } on Object catch (e) {
        thrown = e;
      }
      final error = AppError.from(thrown!);
      expect(error.kind, AppErrorKind.commandFailed);
      expect(error.message, contains('exit 1'));
      expect(error.detail, contains('no such service'));
    });
  });

  group('bundle dump', () {
    test('files the shell should have skipped are dropped client-side too',
        () async {
      final box = FakeBox.always(
        '__FILE__ reality.png\n${_b64('png')}\n'
        '__FILE__ guide.html\n${_b64('<html>')}\n'
        '__FILE__ reality.txt\n${_b64('vless://u@h:443#tag')}\n'
        '__FILE__ snell.txt\n${_b64('snell, h, 1234, psk=abc')}\n'
        '__END__\n',
      );
      final b = await box.controller.getBundle('alice');
      expect(b.entries.map((e) => e.fileName), ['reality.txt', 'snell.txt']);
      expect(b.withQr.map((e) => e.protocol), ['reality']);
      expect(b.entries.last.qrPayload, isNull);
      expect(b.path, '/opt/moav/outputs/bundles/alice');
      expect(box.commands.single, contains("'/opt/moav/outputs/bundles/alice'"));
    });

    test('the dump command and the error path never log bundle content',
        () async {
      final lines = <String>[];
      AppLog.sink = lines.add;
      addTearDown(() => AppLog.sink = null);
      final box = FakeBox.always('__NOBUNDLE__\n');
      await expectLater(box.controller.getBundle('bob'), throwsStateError);
      expect(lines, isEmpty);
    });
  });
}

String _b64(String s) => base64Encode(utf8.encode(s));
