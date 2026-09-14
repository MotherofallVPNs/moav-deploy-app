import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_connection.dart';
import 'app_error.dart';

/// "Install my public key": appends a public key line to the remote user's
/// `authorized_keys` over a password-authenticated session, then proves the
/// key works by opening a second session with it.
///
/// SSH-only by nature, so it lives outside [MoavController].
class SshKeyInstaller {
  const SshKeyInstaller({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  /// Idempotent: the line is added only if not already present.
  ///
  /// Authenticates with [password] (the normal first-contact path; used once,
  /// never stored) or with [authPrivateKeyPem] (an already-trusted key).
  Future<void> install({
    required String host,
    required int port,
    required String username,
    String? password,
    String? authPrivateKeyPem,
    required String publicKeyLine,
    required String privateKeyPem,
  }) async {
    final line = publicKeyLine.trim();
    if (!RegExp(r'^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9._@-]+)?$')
        .hasMatch(line)) {
      throw ArgumentError('Not an ssh-ed25519 public key line');
    }

    final client = await SshConnection.open(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPem: authPrivateKeyPem,
      timeout: timeout,
    );
    try {
      final session = await client.execute(script);
      session.stdin.add(utf8.encode('$line\n'));
      await session.stdin.close();
      await session.done.timeout(timeout);
      if (session.exitCode != 0) {
        throw StateError(
          'Could not update authorized_keys (exit ${session.exitCode})',
        );
      }
    } finally {
      client.close();
    }

    await verify(
      host: host,
      port: port,
      username: username,
      privateKeyPem: privateKeyPem,
    );
  }

  /// Opens a session with the private key and runs `echo ok`.
  Future<void> verify({
    required String host,
    required int port,
    required String username,
    required String privateKeyPem,
  }) async {
    SSHClient client;
    try {
      client = await SshConnection.open(
        host: host,
        port: port,
        username: username,
        privateKeyPem: privateKeyPem,
        timeout: timeout,
      );
    } on Object catch (e) {
      throw AppError(
        AppErrorKind.auth,
        'The key was installed but the server still rejected it.',
        hint: 'Check that PubkeyAuthentication is enabled in sshd_config and '
            'that the home directory is not group-writable. '
            '(${AppError.from(e).message})',
        cause: e,
      );
    }
    try {
      final out = await SshConnection.run(client, 'echo ok', timeout: timeout);
      if (out.stdout.trim() != 'ok') {
        throw StateError('Unexpected response from server');
      }
    } finally {
      client.close();
    }
  }

  /// Reads the key line from stdin so it never appears in `ps`.
  static const script = r'''
umask 077
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
KEY=$(cat)
if grep -qxF -- "$KEY" "$HOME/.ssh/authorized_keys"; then
  echo "already present"
else
  printf '%s\n' "$KEY" >> "$HOME/.ssh/authorized_keys" && echo "added"
fi
''';
}
