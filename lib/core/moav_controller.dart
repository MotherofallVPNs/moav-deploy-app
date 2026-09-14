/// The seam between the UI and whatever transport talks to a MoaV server.
///
/// Phase 1 ships [SshMoavController] (drives the `moav` CLI over SSH).
/// Phase 2 adds `ApiMoavController` (MoaV control API over HTTPS) without any
/// UI changes. See docs/ARCHITECTURE.md.
library;

/// Every server operation the app can perform, expressed once.
abstract class MoavController {
  /// Is the server reachable, and is `moav` installed on it?
  Future<ConnectionCheck> ping();

  /// Kick off a MoaV install **detached** on the server and return a handle
  /// that can be polled with [installStatus], even after the app was
  /// suspended and reconnected.
  Future<InstallHandle> install(InstallSpec spec);

  /// Current progress of a detached install.
  Future<InstallStatus> installStatus(InstallHandle handle);

  /// Per-check health report (`moav doctor`).
  Future<DoctorReport> doctor();

  Future<List<MoavUser>> listUsers();

  Future<MoavUser> addUser(String name);

  Future<void> removeUser(String name);

  /// A user's client configs and QR payloads.
  Future<Bundle> getBundle(String user);

  /// Per-protocol connectivity test for a user (`moav test <user>`).
  Future<TestMatrix> testUser(String name);

  /// Start / stop / restart services, or regenerate all users.
  Future<void> service(ServiceAction action);

  /// Grafana URL plus a few headline metrics.
  Future<Monitoring> monitoring();
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Result of [MoavController.ping].
class ConnectionCheck {
  const ConnectionCheck({
    required this.reachable,
    this.moavInstalled,
    this.moavVersion,
    this.error,
  });

  /// TCP/SSH reachability.
  final bool reachable;

  /// `null` when unknown (e.g. reachable but not authenticated yet).
  final bool? moavInstalled;

  final String? moavVersion;

  /// Human-readable failure reason, if any.
  final String? error;

  @override
  String toString() =>
      'ConnectionCheck(reachable: $reachable, moavInstalled: $moavInstalled, '
      'version: $moavVersion, error: $error)';
}

/// Inputs the MoaV installer prompts for.
class InstallSpec {
  const InstallSpec({
    required this.domain,
    required this.email,
    required this.adminPassword,
    this.extraEnv = const {},
  });

  final String domain;
  final String email;

  /// Never logged. Passed to the installer via env or PTY answer only.
  final String adminPassword;

  /// Additional `KEY=value` pairs for the installer environment.
  final Map<String, String> extraEnv;

  @override
  String toString() => 'InstallSpec(domain: $domain, email: $email)';
}

/// Identifies a detached install job on the server.
class InstallHandle {
  const InstallHandle({required this.jobId, required this.logPath});

  /// Opaque server-side id (e.g. a PID or tmux session name).
  final String jobId;

  /// Log file being tailed for progress, e.g. `/opt/moav/.deploy.log`.
  final String logPath;

  Map<String, Object?> toJson() => {'jobId': jobId, 'logPath': logPath};

  factory InstallHandle.fromJson(Map<String, Object?> json) => InstallHandle(
        jobId: json['jobId'] as String,
        logPath: json['logPath'] as String,
      );
}

enum InstallPhase { pending, running, succeeded, failed, unknown }

class InstallStatus {
  const InstallStatus({
    required this.phase,
    this.logTail = const [],
    this.progress,
    this.message,
  });

  final InstallPhase phase;

  /// Most recent log lines, oldest first.
  final List<String> logTail;

  /// 0.0–1.0 when derivable from the log, else `null`.
  final double? progress;

  final String? message;

  bool get isTerminal =>
      phase == InstallPhase.succeeded || phase == InstallPhase.failed;
}

enum CheckResult { pass, warn, fail, skip }

class DoctorCheck {
  const DoctorCheck({
    required this.name,
    required this.result,
    this.detail,
  });

  final String name;
  final CheckResult result;
  final String? detail;
}

class DoctorReport {
  const DoctorReport({required this.checks, required this.collectedAt});

  final List<DoctorCheck> checks;
  final DateTime collectedAt;

  bool get healthy => checks.every((c) => c.result != CheckResult.fail);
}

class MoavUser {
  const MoavUser({required this.name, this.createdAt, this.enabled = true});

  final String name;
  final DateTime? createdAt;
  final bool enabled;

  @override
  bool operator ==(Object other) => other is MoavUser && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A single client config inside a [Bundle].
class BundleEntry {
  const BundleEntry({
    required this.protocol,
    required this.fileName,
    required this.content,
    this.qrPayload,
  });

  /// e.g. `wireguard`, `vless`, `hysteria2`.
  final String protocol;
  final String fileName;

  /// Raw config file contents.
  final String content;

  /// String to encode as a QR code, when the protocol supports it.
  final String? qrPayload;
}

class Bundle {
  const Bundle({
    required this.user,
    required this.entries,
    required this.fetchedAt,
  });

  final String user;
  final List<BundleEntry> entries;
  final DateTime fetchedAt;
}

class ProtocolTest {
  const ProtocolTest({
    required this.protocol,
    required this.result,
    this.detail,
    this.latency,
  });

  final String protocol;
  final CheckResult result;
  final String? detail;
  final Duration? latency;
}

class TestMatrix {
  const TestMatrix({
    required this.user,
    required this.results,
    required this.ranAt,
  });

  final String user;
  final List<ProtocolTest> results;
  final DateTime ranAt;

  bool get allPass => results.every((r) => r.result == CheckResult.pass);
}

enum ServiceActionKind { start, stop, restart, regenerateUsers }

class ServiceAction {
  const ServiceAction(this.kind, {this.service});

  final ServiceActionKind kind;

  /// Optional specific service name; `null` means all services.
  final String? service;

  static const start = ServiceAction(ServiceActionKind.start);
  static const stop = ServiceAction(ServiceActionKind.stop);
  static const restart = ServiceAction(ServiceActionKind.restart);
  static const regenerateUsers = ServiceAction(ServiceActionKind.regenerateUsers);
}

class Metric {
  const Metric({required this.name, required this.value, this.unit});

  final String name;
  final String value;
  final String? unit;
}

class Monitoring {
  const Monitoring({
    required this.grafanaUrl,
    this.metrics = const [],
    this.collectedAt,
  });

  final Uri? grafanaUrl;
  final List<Metric> metrics;
  final DateTime? collectedAt;
}
