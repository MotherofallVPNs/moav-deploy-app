@Tags(['live'])
library;

import 'dart:io' show pid;

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

import '../support/live_env.dart';

/// Live checks: user lifecycle and bundle fetch against a real MoaV box.
///
/// Additive only: creates one user named `zzmoavdeploytest<pid>`, reads its
/// bundle, then revokes it. Pre-existing users are never touched; a
/// `tearDownAll` revokes the test user even if an assertion failed.
///
///   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root \
///     flutter test test/live/live_users_test.dart
void main() {
  final live = LiveEnv.fromEnvironment();
  final enabled = live != null;
  final skip = live == null ? LiveEnv.skipReason : null;

  final testUser = 'zzmoavdeploytest${pid % 100000}';
  late final SshMoavController controller;
  late final List<MoavUser> before;
  var created = false;

  // add/revoke trigger async regeneration, so the list is briefly inconsistent
  // on a busy box; poll until it settles (see docs/MOAV-CLI-GAPS.md).
  Future<List<MoavUser>> settleUsers(
    bool Function(List<MoavUser>) done, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var users = await controller.listUsers();
    while (!done(users) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      users = await controller.listUsers();
    }
    return users;
  }

  setUpAll(() async {
    if (live == null) return;
    controller = live.controller();
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
      // Test user gone, every pre-existing user still present. Other live files
      // may hold their own users, so this is a subset check, not an exact set.
      final after =
          await settleUsers((u) => !u.any((e) => e.name == testUser));
      final names = after.map((u) => u.name).toSet();
      expect(names.contains(testUser), isFalse);
      expect(names.containsAll(before.map((u) => u.name)), isTrue,
          reason: 'a pre-existing user disappeared');
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

    final listed = await settleUsers((u) => u.any((e) => e.name == testUser));
    expect(listed.map((u) => u.name), contains(testUser));
    expect(listed.map((u) => u.name).toSet().containsAll(before.map((u) => u.name)),
        isTrue);

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
    final after = await settleUsers((u) => !u.any((e) => e.name == testUser));
    expect(after.any((u) => u.name == testUser), isFalse);
    expect(after.map((u) => u.name).toSet().containsAll(before.map((u) => u.name)),
        isTrue, reason: 'a pre-existing user disappeared');
    await expectLater(controller.getBundle(testUser), throwsStateError);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));

  test('invalid names are rejected before reaching the shell', () async {
    await expectLater(controller.addUser('bad name; rm'), throwsArgumentError);
    await expectLater(controller.removeUser('../x'), throwsArgumentError);
    await expectLater(controller.getBundle(r'$(id)'), throwsArgumentError);
  }, skip: skip);
}
