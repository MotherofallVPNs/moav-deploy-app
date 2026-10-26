import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_endpoint.dart';

/// Thin helpers over dartssh2 shared by the controller and the key installer.
class SshConnection {
  SshConnection._();

  /// Opens a socket and authenticates with either a private key PEM or a
  /// password. Throws on connect/auth failure; never logs the secret.
  static Future<SSHClient> open({
    required String host,
    required int port,
    required String username,
    String? privateKeyPem,
    String? password,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (privateKeyPem == null && password == null) {
      throw StateError('No credential available for $username@$host');
    }
    // Last line of defence: the resolver only understands a bare name or IP.
    final target = SshEndpoint.normalizeHost(host);
    final socket = await SSHSocket.connect(target, port, timeout: timeout);
    final client = SSHClient(
      socket,
      username: username,
      identities: privateKeyPem == null ? null : SSHKeyPair.fromPem(privateKeyPem),
      onPasswordRequest: password == null ? null : () => password,
    );
    try {
      await client.authenticated.timeout(timeout);
    } on Object {
      client.close();
      rethrow;
    }
    return client;
  }

  /// Runs [command] and returns its combined output as text.
  ///
  /// Throws [SshCommandException] when the exit code is non-zero and
  /// [allowFailure] is false.
  static Future<SshOutput> run(
    SSHClient client,
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await client.runWithResult(command).timeout(timeout);
    final out = SshOutput(
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
      exitCode: result.exitCode ?? -1,
    );
    if (!allowFailure && out.exitCode != 0) {
      throw SshCommandException(command, out);
    }
    return out;
  }

  /// Writes [content] to [path] on the server through stdin (so the payload
  /// never appears in `ps` or shell history) with mode 0600 and parent dirs
  /// created 0700.
  static Future<void> writeFile(
    SSHClient client,
    String path,
    String content, {
    String mode = '600',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final q = shellQuote(path);
    final session = await client.execute(
      'umask 077 && mkdir -p "\$(dirname $q)" && cat > $q && chmod $mode $q',
    );
    session.stdin.add(utf8.encode(content));
    await session.stdin.close();
    await session.done.timeout(timeout);
    if (session.exitCode != 0) {
      throw SshCommandException(
        'write $path',
        SshOutput(stdout: '', stderr: '', exitCode: session.exitCode ?? -1),
      );
    }
  }

  /// Single-quotes [value] for POSIX shells.
  static String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');

  /// Strips ANSI colour/cursor sequences from CLI output.
  static String stripAnsi(String text) => text.replaceAll(_ansi, '');
}

class SshOutput {
  const SshOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;

  String get combined => stderr.isEmpty ? stdout : '$stdout\n$stderr';
}

class SshCommandException implements Exception {
  SshCommandException(this.command, this.output);

  final String command;
  final SshOutput output;

  @override
  String toString() {
    final detail = output.combined.trim();
    final short = detail.length > 300 ? '${detail.substring(0, 300)}…' : detail;
    return 'Remote command failed (exit ${output.exitCode})'
        '${short.isEmpty ? '' : ': $short'}';
  }
}
