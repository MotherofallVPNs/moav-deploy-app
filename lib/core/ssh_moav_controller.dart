import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import 'moav_controller.dart';
import 'server_profile.dart';

/// Resolves the secret needed to authenticate a [ServerProfile].
///
/// Kept as a callback so this class never touches the secure store directly
/// and stays trivially testable.
typedef SecretResolver = Future<String?> Function(ServerProfile profile);

/// Phase 1 [MoavController]: drives the `moav` CLI over SSH using dartssh2.
///
/// Every method documents the exact CLI invocation it will run. Output
/// parsing prefers JSON (`--json`) where the CLI supports it; where it does
/// not, the gap is tracked in docs/MOAV-CLI-GAPS.md.
///
/// M0/M1: all operations are stubs except [ping], which only checks TCP
/// reachability. Real SSH sessions land in M2+.
class SshMoavController implements MoavController {
  SshMoavController({
    required this.profile,
    required SecretResolver secretResolver,
    this.connectTimeout = const Duration(seconds: 10),
  }) : _secretResolver = secretResolver;

  final ServerProfile profile;
  final SecretResolver _secretResolver;
  final Duration connectTimeout;

  /// Where the detached installer writes its log on the server.
  static const deployLogPath = '/opt/moav/.deploy.log';

  /// M1 stub: TCP-level reachability only.
  ///
  /// Final behaviour: open an SSH session and run
  /// `command -v moav && moav --version` to fill in `moavInstalled` and
  /// `moavVersion`.
  @override
  Future<ConnectionCheck> ping() async {
    try {
      final socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: connectTimeout,
      );
      await socket.close();
      return const ConnectionCheck(reachable: true, moavInstalled: null);
    } on Object catch (e) {
      return ConnectionCheck(reachable: false, error: _describe(e));
    }
  }

  /// Runs the upstream installer **detached** so the session can drop:
  ///
  /// ```
  /// nohup env MOAV_DOMAIN=… MOAV_EMAIL=… MOAV_ADMIN_PASSWORD=… \
  ///   bash -c 'curl -fsSL <install.sh> | bash' > /opt/moav/.deploy.log 2>&1 &
  /// echo $!
  /// ```
  ///
  /// Returns the PID as the job id. If MoaV's installer does not accept env
  /// input yet, answers are fed over a PTY as a stopgap (see CLI gaps doc).
  @override
  Future<InstallHandle> install(InstallSpec spec) {
    throw UnimplementedError('install: M2');
  }

  /// Polls a detached install:
  /// `kill -0 <pid>; tail -n 50 /opt/moav/.deploy.log`.
  ///
  /// Phase is derived from process liveness plus a terminal marker line in
  /// the log.
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

  /// `moav user remove <name>` (non-interactive / `--yes`).
  @override
  Future<void> removeUser(String name) {
    throw UnimplementedError('removeUser: M3');
  }

  /// Locates the user's bundle directory (`moav user show <name>` or the
  /// conventional output path) and pulls each config over SFTP.
  @override
  Future<Bundle> getBundle(String user) {
    throw UnimplementedError('getBundle: M3');
  }

  /// `moav test <name> --json`.
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
  /// the local Prometheus metrics endpoint via `curl -s localhost:9090/…`.
  @override
  Future<Monitoring> monitoring() {
    throw UnimplementedError('monitoring: M4');
  }

  // ---------------------------------------------------------------------------

  /// Resolves the secret for [profile]. Used by later milestones when opening
  /// a real session; referenced here so the resolver is wired from day one.
  Future<String?> resolveSecret() => _secretResolver(profile);

  /// Error text safe to surface. Never includes credentials.
  static String _describe(Object e) {
    if (e is TimeoutException) return 'Connection timed out';
    final text = e.toString();
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}
