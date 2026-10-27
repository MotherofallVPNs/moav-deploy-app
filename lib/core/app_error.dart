import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../security/redactor.dart';
import 'ssh_connection.dart';

/// The MoaV CLI release line the text parsers in `moav_cli.dart` were
/// verified against. Shown to users when the server answers in an unexpected
/// format; bump it here when the parsers are re-verified against a newer CLI.
const testedMoavVersion = 'v2.2.x';

/// What went wrong, in terms the UI can act on.
enum AppErrorKind {
  /// This device has no usable network.
  offline,

  /// DNS failure, connection refused, no route: the host cannot be reached.
  unreachable,

  /// The server or a command did not answer in time.
  timeout,

  /// SSH rejected the key or password.
  auth,

  /// The stored key could not be decoded (corrupt, or a passphrase-protected
  /// key was imported without its passphrase).
  credential,

  /// The SSH transport failed after connecting (handshake, disconnect).
  transport,

  /// A remote command exited non-zero.
  commandFailed,

  /// The CLI answered, but not in a shape this app understands.
  unexpectedOutput,

  /// Client-side validation.
  invalidInput,

  /// Anything else. Message is scrubbed and truncated.
  unknown,
}

/// A user-presentable error: one short sentence, an optional hint on what to
/// do, and optional scrubbed detail for the curious. Never a stack trace,
/// never a secret.
class AppError implements Exception {
  const AppError(
    this.kind,
    this.message, {
    this.hint,
    this.detail,
    this.cause,
  });

  final AppErrorKind kind;
  final String message;
  final String? hint;

  /// Extra context (e.g. the last lines of a failed command), already
  /// scrubbed and truncated. Shown collapsed in the UI.
  final String? detail;

  /// The original exception, for `rethrow`-style flows. Never displayed.
  final Object? cause;

  /// Whether a plain "Retry" is a sensible next step.
  bool get retryable => switch (kind) {
        AppErrorKind.auth || AppErrorKind.credential || AppErrorKind.invalidInput => false,
        _ => true,
      };

  /// `message` plus the hint, for snackbars.
  String get summary => hint == null ? message : '$message $hint';

  @override
  String toString() => message;

  /// Maximum length of [detail] and of scrubbed unknown messages.
  static const maxDetail = 300;

  /// Classifies any thrown object. Idempotent on [AppError].
  static AppError from(Object e, {String? host, int? port}) {
    if (e is AppError) return e;

    // Plain strings are already user-facing messages from our own code.
    if (e is String) return AppError(AppErrorKind.unknown, _clip(e, 400));

    if (e is TimeoutException) {
      return AppError(
        AppErrorKind.timeout,
        'The server did not respond in time.',
        hint: 'Check the connection and try again. Long commands such as '
            'moav doctor or a service restart can take a minute or more.',
        cause: e,
      );
    }

    if (e is SocketException) return _fromSocket(e, host: host, port: port);

    if (e is SSHAuthFailError || e is SSHAuthAbortError) {
      return AppError(
        AppErrorKind.auth,
        'Authentication failed.',
        hint: 'The server rejected the key or password. Check the username, '
            'or re-install the key from the add-server screen.',
        cause: e,
      );
    }

    if (e is SSHKeyDecodeError) {
      return AppError(
        AppErrorKind.credential,
        'The stored key could not be read.',
        hint: 'If the key has a passphrase, import the unencrypted key or '
            'generate a new one. Otherwise remove the server and add it again.',
        cause: e,
      );
    }

    if (e is SSHHostkeyError) {
      return AppError(
        AppErrorKind.transport,
        'The server presented an unexpected host key.',
        hint: 'Try again. If it persists, verify the server from another '
            'channel before trusting it.',
        cause: e,
      );
    }

    if (e is SSHError) {
      return AppError(
        AppErrorKind.transport,
        'The SSH connection dropped.',
        hint: 'Try again. The session is re-opened automatically.',
        detail: _shortType(e),
        cause: e,
      );
    }

    if (e is SftpStatusError) {
      return AppError(
        AppErrorKind.commandFailed,
        'The file could not be read from the server.',
        detail: _clip(e.message),
        cause: e,
      );
    }

    if (e is SshCommandException) {
      return AppError(
        AppErrorKind.commandFailed,
        'The command failed on the server (exit ${e.output.exitCode}).',
        hint: 'Expand the details, or run it over SSH to see the full output.',
        detail: _clip(e.output.combined),
        cause: e,
      );
    }

    if (e is FormatException) {
      return AppError(
        AppErrorKind.unexpectedOutput,
        'The server answered in a format this app does not understand.',
        hint: 'The moav version on the server may be newer or older than '
            'this app was tested with ($testedMoavVersion).',
        detail: _clip(e.message),
        cause: e,
      );
    }

    if (e is ArgumentError) {
      return AppError(
        AppErrorKind.invalidInput,
        _clip(e.message?.toString() ?? 'Invalid input.', 200),
        cause: e,
      );
    }

    if (e is StateError) {
      // Our own guard-rail messages ("No stored credential…", "User still
      // exists after revoke…"). Already human-readable; scrub anyway.
      return AppError(AppErrorKind.unknown, _clip(e.message, 200), cause: e);
    }

    if (e is UnimplementedError) {
      return AppError(
        AppErrorKind.unknown,
        'This is not supported yet.',
        cause: e,
      );
    }

    final text = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
    return AppError(
      AppErrorKind.unknown,
      'Something went wrong.',
      detail: _clip(text, 200),
      cause: e,
    );
  }

  static AppError _fromSocket(SocketException e, {String? host, int? port}) {
    final msg = e.message.toLowerCase();
    final os = e.osError?.message.toLowerCase() ?? '';
    final where = host == null ? 'the server' : (port == null ? host : '$host:$port');
    if (msg.contains('host lookup') || os.contains('nodename nor servname') ||
        os.contains('name or service not known') || os.contains('no address associated')) {
      return AppError(
        AppErrorKind.unreachable,
        'Could not find $where.',
        hint: 'Check the hostname and that this device is online.',
        cause: e,
      );
    }
    if (os.contains('network is unreachable') || os.contains('no route to host') ||
        os.contains('network is down') || msg.contains('network is unreachable')) {
      return AppError(
        AppErrorKind.offline,
        'No network connection.',
        hint: 'Connect to Wi-Fi or mobile data and try again.',
        cause: e,
      );
    }
    if (os.contains('connection refused') || msg.contains('connection refused')) {
      return AppError(
        AppErrorKind.unreachable,
        'Connection refused by $where.',
        hint: 'Is SSH listening on that port? Firewalls in front of the box '
            'can also reset the connection.',
        cause: e,
      );
    }
    if (os.contains('timed out') || msg.contains('timed out')) {
      return AppError(
        AppErrorKind.timeout,
        'Connecting to $where timed out.',
        hint: 'The host may be down, or the port may be filtered.',
        cause: e,
      );
    }
    if (os.contains('connection reset') || os.contains('broken pipe')) {
      return AppError(
        AppErrorKind.transport,
        'The connection to $where was reset.',
        hint: 'Try again. Some networks reset SSH sessions after a while.',
        cause: e,
      );
    }
    return AppError(
      AppErrorKind.unreachable,
      'Could not reach $where.',
      hint: 'Check the address, the port, and your network.',
      detail: _clip(e.osError?.message ?? e.message),
      cause: e,
    );
  }

  static String _shortType(Object e) =>
      e.runtimeType.toString().replaceFirst(RegExp(r'^SSH'), '').replaceFirst(RegExp(r'Error$'), '');

  static String _clip(String s, [int max = maxDetail]) {
    final t = Redactor.scrub(SshConnection.stripAnsi(s)).trim();
    if (t.length <= max) return t;
    return '…${t.substring(t.length - max)}';
  }
}

/// Riverpod 3 retries failed providers with exponential backoff by default.
/// For an SSH tool every connection attempt is a network signal and a
/// potential auth lockout, so retries are always explicit (the Retry button
/// or the deploy poller), never implicit. Install on the root ProviderScope.
Duration? noProviderRetry(int retryCount, Object error) => null;
