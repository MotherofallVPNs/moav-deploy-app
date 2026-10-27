/// The seam between the UI and whatever transport talks to a MoaV server.
///
/// Today that is [SshMoavController], which drives the `moav` CLI over SSH.
/// An API-backed controller can be added without UI changes.
/// See docs/ARCHITECTURE.md.
library;

import 'app_error.dart';

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

  /// Per-service state (`moav status`) plus the dashboard URLs it prints.
  Future<ServiceStatusReport> status();

  /// Grafana URL and its health, plus the dashboard URLs. Fast.
  Future<Monitoring> monitoring();

  /// Headline metrics from Prometheus. Slow on a busy box, so it is fetched
  /// and refreshed independently of [monitoring].
  Future<MetricsSnapshot> metrics();

  /// Host CPU, RAM and disk plus the MoaV and component versions.
  Future<ServerInfo> serverInfo();

  /// Asks the server whether a newer MoaV release exists.
  Future<UpdateCheck> checkForUpdates();

  /// Starts the MoaV self-update **detached** on the server. Re-attaches to a
  /// job that is still running instead of starting a second one.
  Future<void> startUpdate();

  /// Progress of the detached update job; `null` when none was ever started.
  Future<InstallStatus?> updateStatus();
}

// --- Models ---

/// Result of [MoavController.ping].
class ConnectionCheck {
  const ConnectionCheck({
    required this.reachable,
    this.moavInstalled,
    this.moavVersion,
    this.error,
    this.failure,
  });

  /// TCP/SSH reachability.
  final bool reachable;

  /// `null` when unknown (e.g. reachable but not authenticated yet).
  final bool? moavInstalled;

  final String? moavVersion;

  /// Human-readable failure reason, if any.
  final String? error;

  /// The classified failure behind [error], when the connection failed.
  final AppError? failure;

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

  /// Never logged. Reaches the server only inside the mode-0600 spec file.
  final String adminPassword;

  /// Additional `KEY=value` pairs for the installer environment.
  final Map<String, String> extraEnv;

  @override
  String toString() => 'InstallSpec(domain: $domain, email: $email)';
}

/// Identifies a detached install job on the server.
class InstallHandle {
  const InstallHandle({required this.jobId, required this.logPath});

  /// Opaque server-side id (the PID of the detached job).
  final String jobId;

  /// Log file being tailed for progress, e.g. `.moav-deploy/deploy.log`.
  final String logPath;

  Map<String, Object?> toJson() => {'jobId': jobId, 'logPath': logPath};

  factory InstallHandle.fromJson(Map<String, Object?> json) => InstallHandle(
        jobId: json['jobId'] as String,
        logPath: json['logPath'] as String,
      );
}

enum InstallPhase { pending, running, succeeded, failed, unknown }

/// Progress of a detached server-side job (the install or the self-update).
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
  const MoavUser({
    required this.name,
    this.createdAt,
    this.enabled = true,
    this.bundleReady = false,
    this.protocols = const [],
  });

  final String name;
  final DateTime? createdAt;
  final bool enabled;

  /// A client bundle directory exists for this user on the server.
  final bool bundleReady;

  /// Which server-side user stores list this name (e.g. `sing-box`,
  /// `wireguard`, `xray`). Empty when unknown.
  final List<String> protocols;

  /// Usernames the `moav` CLI accepts.
  static final validName = RegExp(r'^[a-zA-Z0-9_-]+$');

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

  /// Human title, e.g. `Hysteria2`.
  String get title => BundleEntry.titles[protocol] ?? protocol;

  static const titles = <String, String>{
    'reality': 'VLESS Reality',
    'trojan': 'Trojan',
    'hysteria2': 'Hysteria2',
    'shadowsocks': 'Shadowsocks',
    'xhttp': 'VLESS XHTTP',
    'telegram': 'Telegram MTProxy',
    'subscription': 'Subscription (v2rayNG / Streisand)',
    'wireguard': 'WireGuard',
    'wireguard-wstunnel': 'WireGuard over wstunnel',
    'amneziawg': 'AmneziaWG',
    'trusttunnel': 'TrustTunnel',
    'xdns': 'XDNS',
    'dnstt': 'dnstt',
  };
}

class Bundle {
  const Bundle({
    required this.user,
    required this.entries,
    required this.fetchedAt,
    this.path,
  });

  final String user;
  final List<BundleEntry> entries;
  final DateTime fetchedAt;

  /// Server-side directory the bundle was read from.
  final String? path;

  Iterable<BundleEntry> get withQr => entries.where((e) => e.qrPayload != null);
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
    this.overall,
  });

  final String user;
  final List<ProtocolTest> results;
  final DateTime ranAt;

  /// The CLI's own verdict (`pass` / `fail` / `warn`), when reported.
  final CheckResult? overall;

  /// Every protocol that was actually tested passed (skips ignored).
  bool get allPass => results.every(
        (r) => r.result == CheckResult.pass || r.result == CheckResult.skip,
      );

  int count(CheckResult r) => results.where((t) => t.result == r).length;
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
    this.grafanaCdnUrl,
    this.adminUrl,
    this.grafanaHealthy,
    this.grafanaVersion,
    this.metrics = const [],
    this.collectedAt,
  });

  final Uri? grafanaUrl;

  /// Grafana behind the CDN subdomain, when configured.
  final Uri? grafanaCdnUrl;
  final Uri? adminUrl;

  /// `null` when the health probe could not run (e.g. monitoring disabled).
  final bool? grafanaHealthy;
  final String? grafanaVersion;
  final List<Metric> metrics;
  final DateTime? collectedAt;
}

/// Headline Prometheus metrics, fetched separately from [Monitoring].
class MetricsSnapshot {
  const MetricsSnapshot({required this.metrics, required this.collectedAt});

  final List<Metric> metrics;
  final DateTime collectedAt;
}

/// CPU, RAM, swap and disk of the host, read from `/proc` and `df`.
class HostMetrics {
  const HostMetrics({
    this.cpuCount,
    this.cpuUsage,
    this.load1,
    this.load5,
    this.load15,
    this.memTotalBytes,
    this.memAvailableBytes,
    this.swapTotalBytes,
    this.swapFreeBytes,
    this.diskTotalBytes,
    this.diskAvailableBytes,
    this.uptime,
  });

  final int? cpuCount;

  /// 0.0 to 1.0 over a one-second sample, `null` when not sampled.
  final double? cpuUsage;
  final double? load1;
  final double? load5;
  final double? load15;
  final int? memTotalBytes;
  final int? memAvailableBytes;
  final int? swapTotalBytes;
  final int? swapFreeBytes;
  final int? diskTotalBytes;
  final int? diskAvailableBytes;
  final Duration? uptime;

  static double? _used(int? total, int? free) {
    if (total == null || free == null || total <= 0) return null;
    return ((total - free) / total).clamp(0, 1);
  }

  /// Fraction of RAM in use (1 minus available), `null` when unknown.
  double? get memUsage => _used(memTotalBytes, memAvailableBytes);
  double? get swapUsage => _used(swapTotalBytes, swapFreeBytes);
  double? get diskUsage => _used(diskTotalBytes, diskAvailableBytes);

  bool get isEmpty =>
      cpuUsage == null &&
      load1 == null &&
      memTotalBytes == null &&
      diskTotalBytes == null;
}

/// One row of the `moav --version` component table.
class ComponentVersion {
  const ComponentVersion({
    required this.name,
    required this.version,
    this.source,
  });

  final String name;
  final String version;
  final String? source;
}

/// What `moav --version` and the git checkout say about the install.
class VersionInfo {
  const VersionInfo({
    this.moavVersion,
    this.branch,
    this.commit,
    this.components = const [],
  });

  /// e.g. `2.3.0`.
  final String? moavVersion;
  final String? branch;
  final String? commit;
  final List<ComponentVersion> components;
}

class ServerInfo {
  const ServerInfo({
    required this.host,
    required this.version,
    required this.collectedAt,
  });

  final HostMetrics host;
  final VersionInfo version;
  final DateTime collectedAt;
}

/// Result of `moav doctor updates`.
class UpdateCheck {
  const UpdateCheck({
    required this.updateAvailable,
    required this.checkedAt,
    this.currentVersion,
    this.latestVersion,
    this.message,
  });

  final bool updateAvailable;
  final DateTime checkedAt;
  final String? currentVersion;

  /// Newest published release, `null` when the server could not look it up.
  final String? latestVersion;

  /// The check's own wording, e.g. `Up to date (v2.3.1)`.
  final String? message;

  /// The lookup itself failed (no internet on the box, GitHub unreachable).
  bool get unknown => latestVersion == null;
}

enum ServiceState {
  running,
  unhealthy,
  starting,
  exited,
  stopped,
  never,
  unknown;

  /// The container is up (healthy or not); `moav status --json` splits these.
  bool get isUp => this == running || this == unhealthy || this == starting;
}

/// One row of `moav status`.
class ServiceStatus {
  const ServiceStatus({
    required this.name,
    required this.state,
    this.lastRun,
    this.uptime,
    this.ports = const [],
  });

  final String name;
  final ServiceState state;
  final String? lastRun;
  final String? uptime;
  final List<String> ports;
}

class ServiceStatusReport {
  const ServiceStatusReport({
    required this.services,
    required this.collectedAt,
    this.version,
    this.adminUrl,
    this.grafanaUrl,
    this.grafanaCdnUrl,
    this.defaultProfiles = const [],
  });

  final List<ServiceStatus> services;
  final DateTime collectedAt;

  /// e.g. `2.2.2`.
  final String? version;
  final Uri? adminUrl;
  final Uri? grafanaUrl;
  final Uri? grafanaCdnUrl;
  final List<String> defaultProfiles;

  int get runningCount => services.where((s) => s.state.isUp).length;
}
