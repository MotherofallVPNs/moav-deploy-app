@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_key_installer.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/security/key_service.dart';

/// Live, additive-only checks against a real MoaV box. Skipped unless
/// MOAV_TEST_HOST / MOAV_TEST_USER / MOAV_TEST_SSH_KEY are set. Never run in CI.
///
///   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root \
///     flutter test test/live
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

  late final String keyPem;
  late final ServerProfile profile;
  late final SshMoavController controller;

  setUpAll(() {
    if (!enabled) return;
    keyPem = File(keyPath!).readAsStringSync();
    profile = ServerProfile(
      id: 'live',
      label: host,
      host: host,
      port: port,
      username: user,
      authMethod: SshAuthMethod.importedKey,
    );
    controller = SshMoavController(
      profile: profile,
      secretResolver: (_) async => keyPem,
    );
  });

  tearDownAll(() {
    if (enabled) controller.dispose();
  });

  test('ping opens a session and reports moav version', () async {
    final c = await controller.ping();
    // ignore: avoid_print
    print(c);
    expect(c.reachable, isTrue, reason: c.error);
    expect(c.moavInstalled, isTrue);
    expect(c.moavVersion, matches(RegExp(r'^\d+\.\d+')));
  }, skip: skip);

  test('install-public-key helper is additive and verifiable', () async {
    final material = await const KeyService().generateEd25519(
      comment: 'moav-deploy-livetest',
    );
    const installer = SshKeyInstaller();
    await installer.install(
      host: host!,
      port: port,
      username: user!,
      authPrivateKeyPem: keyPem,
      publicKeyLine: material.publicKeyOpenSsh,
      privateKeyPem: material.privateKeyPem,
    );
    // Second install is a no-op.
    await installer.install(
      host: host,
      port: port,
      username: user,
      authPrivateKeyPem: keyPem,
      publicKeyLine: material.publicKeyOpenSsh,
      privateKeyPem: material.privateKeyPem,
    );

    // Clean up only the exact line we added.
    final client = await SshConnection.open(
      host: host,
      port: port,
      username: user,
      privateKeyPem: keyPem,
    );
    try {
      final count = await SshConnection.run(
        client,
        'grep -cxF -- ${SshConnection.shellQuote(material.publicKeyOpenSsh)} '
        '~/.ssh/authorized_keys',
      );
      expect(count.stdout.trim(), '1');
      await SshConnection.run(
        client,
        'grep -vxF -- ${SshConnection.shellQuote(material.publicKeyOpenSsh)} '
        '~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && '
        'cat ~/.ssh/authorized_keys.tmp > ~/.ssh/authorized_keys && '
        'rm -f ~/.ssh/authorized_keys.tmp',
      );
    } finally {
      client.close();
    }
  }, skip: skip);

}
