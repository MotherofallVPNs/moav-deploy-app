@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// M3 live checks: user lifecycle + bundle fetch against a real MoaV box.
///
/// Additive only: creates one user named `zzmoavdeploytest<pid>`, reads its
/// bundle, then revokes it. Pre-existing users are never touched; a
/// `tearDownAll` revokes the test user even if an assertion failed.
///
///   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root \
///     flutter test test/live/live_users_test.dart
void main() {
  final env = Platform.environment;
  final host = env['MOAV_TEST_HOST'];
  final user = env['MOAV_TEST_USER'];
  var keyPath = env['MOAV_TEST_SSH_KEY'];
  final enabled = host != null && user != null && keyPath != null;
  if (keyPath != null && keyPath.startsWith('~/')) {
    keyPath = '${env['HOME']}/${keyPath.substring(2)}';
  }
  final port = int.tryParse(env['MOAV_TEST_PORT'] ?? '') ?? 22;
  final skip = enabled ? null : 'MOAV_TEST_* env not set';

  final testUser = 'zzmoavdeploytest${pid % 100000}';
  late final SshMoavController controller;
  late final List<MoavUser> before;
  var created = false;

  setUpAll(() async {
    if (!enabled) return;
    final keyPem = File(keyPath!).readAsStringSync();
    controller = SshMoavController(
      profile: ServerProfile(
        id: 'live',
        label: host,
        host: host,
        port: port,
        username: user,
        authMethod: SshAuthMethod.importedKey,
      ),
      secretResolver: (_) async => keyPem,
    );
    before = await controller.listUsers();
  });

  tearDownAll(() async {
    if (!enabled) return;
    try {
      if (created) {
        final now = await controller.listUsers();
        if (now.any((u) => u.name == testUser)) {
          await controller.removeUser(testUser);
        }
      }
      // Pre-existing users must be exactly as we found them.
      final after = await controller.listUsers();
      expect(after.map((u) => u.name).toSet(), before.map((u) => u.name).toSet());
    } finally {
      controller.dispose();
    }
  });

  test('listUsers parses the live user list', () async {
    // ignore: avoid_print
    print('existing users: ${before.length}');
    expect(before.any((u) => u.name == testUser), isFalse,
        reason: 'stale test user present; clean up manually');
    for (final u in before) {
      expect(MoavUser.validName.hasMatch(u.name), isTrue);
    }
  }, skip: skip);

  test('add user, fetch bundle with QR payloads, revoke', () async {
    final added = await controller.addUser(testUser);
    created = true;
    expect(added.name, testUser);
    expect(added.bundleReady, isTrue,
        reason: 'moav user add should generate the bundle directory');

    final listed = await controller.listUsers();
    expect(listed.map((u) => u.name), contains(testUser));
    expect(listed.length, before.length + 1);

    final bundle = await controller.getBundle(testUser);
    // ignore: avoid_print
    print('bundle files: ${bundle.entries.map((e) => e.fileName).join(', ')}');
    expect(bundle.user, testUser);
    expect(bundle.entries, isNotEmpty);
    expect(bundle.withQr, isNotEmpty);
    expect(bundle.entries.any((e) => e.fileName.endsWith('.png')), isFalse);
    for (final e in bundle.entries) {
      expect(e.content, isNotEmpty, reason: e.fileName);
    }
    final reality = bundle.entries.where((e) => e.protocol == 'reality');
    if (reality.isNotEmpty) {
      expect(reality.first.qrPayload, startsWith('vless://'));
    }
    final wg = bundle.entries.where((e) => e.protocol == 'wireguard');
    if (wg.isNotEmpty) {
      expect(wg.first.qrPayload, contains('[Interface]'));
    }

    await controller.removeUser(testUser);
    created = false;
    final after = await controller.listUsers();
    expect(after.any((u) => u.name == testUser), isFalse);
    expect(after.length, before.length);
    await expectLater(controller.getBundle(testUser), throwsStateError);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));

  test('invalid names are rejected before reaching the shell', () async {
    await expectLater(controller.addUser('bad name; rm'), throwsArgumentError);
    await expectLater(controller.removeUser('../x'), throwsArgumentError);
    await expectLater(controller.getBundle(r'$(id)'), throwsArgumentError);
  }, skip: skip);
}
