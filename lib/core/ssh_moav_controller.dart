import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import 'moav_controller.dart';
import 'server_profile.dart';
import 'ssh_connection.dart';

/// Resolves the secret needed to authenticate a [ServerProfile].
///
/// Kept as a callback so this class never touches the secure store directly
/// and stays trivially testable.
typedef SecretResolver = Future<String?> Function(ServerProfile profile);

/// Phase 1 [MoavController]: drives the `moav` CLI over SSH using dartssh2.
///
/// Every method documents the exact CLI invocation it runs. Output parsing
/// prefers JSON (`--json`) where the CLI supports it; where it does not, the
/// gap is tracked in docs/MOAV-CLI-GAPS.md.
///
/// One SSH client is kept open lazily and re-opened transparently after the
/// app was suspended and the transport dropped.
class SshMoavController implements MoavController {
  SshMoavController({
    required this.profile,
    required SecretResolver secretResolver,
    this.connectTimeout = const Duration(seconds: 15),
  }) : _secretResolver = secretResolver;

  final ServerProfile profile;
  final SecretResolver _secretResolver;
  final Duration connectTimeout;

  SSHClient? _client;

  /// Where the detached installer writes its log on the server.
  static const deployLogPath = '.moav-deploy/deploy.log';

  /// Opens an SSH session and runs `echo __ok__; moav --version` to report
  /// reachability, whether auth works, and the installed MoaV version.
  @override
  Future<ConnectionCheck> ping() async {
    try {
      final client = await _connected();
      final out = await SshConnection.run(
        client,
        pingCommand,
        allowFailure: true,
        timeout: connectTimeout,
      );
      return parsePing(out.combined);
    } on Object catch (e) {
      _dropClient();
      return ConnectionCheck(reachable: false, error: describeError(e));
    }
  }

  static const pingCommand = 'echo __ok__; '
      'if command -v moav >/dev/null 2>&1; then moav --version 2>/dev/null | head -3; '
      'elif [ -x /opt/moav/moav.sh ]; then /opt/moav/moav.sh --version 2>/dev/null | head -3; '
      'else echo __nomoav__; fi';

  static ConnectionCheck parsePing(String raw) {
    final text = SshConnection.stripAnsi(raw);
    if (!text.contains('__ok__')) {
      return const ConnectionCheck(
        reachable: true,
        error: 'Connected, but the shell did not respond as expected',
      );
    }
    if (text.contains('__nomoav__')) {
      return const ConnectionCheck(reachable: true, moavInstalled: false);
    }
    final m = RegExp(r'MoaV\s+v?([0-9][^\s]*)').firstMatch(text);
    return ConnectionCheck(
      reachable: true,
      moavInstalled: true,
      moavVersion: m?.group(1),
    );
  }

  /// M2: uploads a detached, idempotent install job and returns its PID.
  @override
  Future<InstallHandle> install(InstallSpec spec) {
    throw UnimplementedError('install: M2');
  }

  /// M2: `kill -0 <pid>; tail` the deploy log.
  @override
  Future<InstallStatus> installStatus(InstallHandle handle) {
    throw UnimplementedError('installStatus: M2');
  }

  /// `moav doctor --json` (falls back to parsing text output).
  @override
  Future<DoctorReport> doctor() {
    throw UnimplementedError('doctor: M4');
  }

  /// `moav user list --json`.
  @override
  Future<List<MoavUser>> listUsers() {
    throw UnimplementedError('listUsers: M3');
  }

  /// `moav user add <name>`.
  @override
  Future<MoavUser> addUser(String name) {
    throw UnimplementedError('addUser: M3');
  }

  /// `moav user revoke <name>`.
  @override
  Future<void> removeUser(String name) {
    throw UnimplementedError('removeUser: M3');
  }

  /// Locates the user's bundle directory and pulls each config over SFTP.
  @override
  Future<Bundle> getBundle(String user) {
    throw UnimplementedError('getBundle: M3');
  }

  /// `moav test <name>`.
  @override
  Future<TestMatrix> testUser(String name) {
    throw UnimplementedError('testUser: M3');
  }

  /// `moav start|stop|restart [service]` or `moav regenerate-users`.
  @override
  Future<void> service(ServiceAction action) {
    throw UnimplementedError('service: M4');
  }

  /// Reads the Grafana URL from `moav doctor`/config and headline numbers from
  /// the local Prometheus metrics endpoint.
  @override
  Future<Monitoring> monitoring() {
    throw UnimplementedError('monitoring: M4');
  }

  /// Closes the cached SSH client, if any.
  void dispose() => _dropClient();

  // ---------------------------------------------------------------------------

  Future<SSHClient> _connected() async {
    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;
    final secret = await _secretResolver(profile);
    if (secret == null || secret.isEmpty) {
      throw StateError('No stored credential for ${profile.label}');
    }
    final usePassword = profile.authMethod == SshAuthMethod.password;
    final client = await SshConnection.open(
      host: profile.host,
      port: profile.port,
      username: profile.username,
      privateKeyPem: usePassword ? null : secret,
      password: usePassword ? secret : null,
      timeout: connectTimeout,
    );
    _client = client;
    return client;
  }

  void _dropClient() {
    final c = _client;
    _client = null;
    if (c != null && !c.isClosed) c.close();
  }

  /// Error text safe to surface. Never includes credentials.
  static String describeError(Object e) {
    if (e is TimeoutException) return 'Connection timed out';
    if (e is SSHAuthFailError || e is SSHAuthAbortError) {
      return 'Authentication failed';
    }
    final text = e.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}
