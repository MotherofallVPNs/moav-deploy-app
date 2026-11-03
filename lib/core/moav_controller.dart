/// The seam between the UI and whatever transport talks to a MoaV server.
///
/// Today that is [SshMoavController], which drives the `moav` CLI over SSH.
/// An API-backed controller can be added without UI changes.
/// See docs/ARCHITECTURE.md.
library;

import 'dart:typed_data';

import 'app_error.dart';
import 'dns_check.dart';
import 'donate.dart';
import 'moav_services.dart';

/// Every server operation the app can perform, expressed once.
abstract class MoavController {
  /// Is the server reachable, and is `moav` installed on it?
  Future<ConnectionCheck> ping();

  /// The server's public IPv4 as the internet sees it (what the DNS records
  /// for a domain install must point at), or `null` when it cannot be told.
  Future<String?> publicIp();

  /// Looks up the records a domain install needs (see `DnsRecords`) from
  /// the server and reports each one. Guidance only: never gates [install].
  Future<DnsCheckReport> checkDns({
    required String domain,
    required String serverIp,
  });

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

  /// The user's whole bundle directory zipped on the server, or `null` when
  /// the box cannot produce one; the app then zips the fetched entries
  /// itself (`encodeBundleZip`).
  Future<Uint8List?> getBundleArchive(String user);

  /// Start / stop / restart services, enable / disable one in `.env`, or
  /// regenerate all users. [onOutput] receives command output as it streams.
  Future<void> service(ServiceAction action, {OutputSink? onOutput});

  /// Per-service state (`moav status`) plus the dashboard URLs it prints.
  Future<ServiceStatusReport> status();

  /// The `ENABLE_*` toggles and `DEFAULT_PROFILES` from the server's `.env`.
  Future<ServiceFlags> serviceFlags();

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

  /// Port and password of the admin dashboard, read from the server's `.env`.
  /// The password is handed over in memory only and never stored or logged.
  Future<AdminPanelAccess> adminPanelAccess();

  /// Opens a loopback listener on this device that forwards to [remotePort]
  /// on the server, so a server-local web UI can be loaded in a webview.
  Future<ServerTunnel> openTunnel(int remotePort);

  /// Port, scheme and admin password of Grafana, read from the server's
  /// `.env`. Same in-memory contract as [adminPanelAccess].
  Future<GrafanaAccess> grafanaAccess();

  /// Time series for the native charts (Prometheus range queries). Slow,
  /// like [metrics], and cached independently of it.
  Future<ChartsSnapshot> metricSeries();

  /// Whether `MAHSANET_API_KEY` is set in the server's `.env`, plus the
  /// donation settings. Presence only: the key itself is never read.
  Future<DonateEnv> donateEnv();

  /// `moav donate status`: MahsaNet totals, Conduit and Snowflake state.
  Future<DonationStatus> donateStatus();

  /// `moav donate list`: the donated configs' state, share links dropped.
  Future<List<DonatedConfig>> donateList();

  /// Saves a MahsaNet API key through `moav donate setup`, which validates
  /// it and writes it to `.env`. The key reaches the server in a mode-0600
  /// file only and is never logged. [onOutput] streams setup's output.
  Future<void> saveMahsaNetKey(String key, {OutputSink? onOutput});

  /// `moav donate submit`: creates [count] donate-mode users and submits
  /// their configs to MahsaNet. [onOutput] streams the run's output.
  Future<DonateResult> donateConfigs({
    required int count,
    String prefix,
    bool force,
    OutputSink? onOutput,
  });
}

/// Receives chunks of command output as they arrive.
typedef OutputSink = void Function(String text);

/// A local port forwarded to the server; see [MoavController.openTunnel].
abstract class ServerTunnel {
  int get localPort;

  /// `https://127.0.0.1:<localPort>/` by default.
  Uri uri({String scheme = 'https', String path = '/'});

  bool get isOpen;

  Future<void> close();
}

/// What the app needs to open the admin dashboard through the SSH session.
class AdminPanelAccess {
  const AdminPanelAccess({
    required this.port,
    this.enabled = true,
    this.password,
  });

  /// Host port the panel is published on (`PORT_ADMIN`, default 9443).
  final int port;

  /// `ENABLE_ADMIN_UI` as written in `.env` (unset counts as enabled).
  final bool enabled;

  /// `ADMIN_PASSWORD` from `.env`, or `null` when unset. Memory only: never
  /// persisted, never logged, and deliberately left out of [toString].
  final String? password;

  @override
  String toString() =>
      'AdminPanelAccess(port: $port, enabled: $enabled, '
      'password: ${password == null ? 'absent' : 'present'})';
}

/// What the app needs to open Grafana through the SSH session.
class GrafanaAccess {
  const GrafanaAccess({
    required this.port,
    this.enabled = true,
    this.scheme = 'https',
    this.password,
  });

  /// Host port Grafana is published on (`PORT_GRAFANA`, default 9444).
  final int port;

  /// `ENABLE_MONITORING` as written in `.env` (unset counts as enabled).
  final bool enabled;

  /// `https` when the Grafana entrypoint found a certificate, else `http`.
  final String scheme;

  /// `ADMIN_PASSWORD` from `.env` (Grafana's `GF_SECURITY_ADMIN_PASSWORD`),
  /// or `null` when unset. Memory only, like [AdminPanelAccess.password].
  final String? password;

  @override
  String toString() =>
      'GrafanaAccess(port: $port, enabled: $enabled, scheme: $scheme, '
      'password: ${password == null ? 'absent' : 'present'})';
}

/// One Prometheus series: a query's samples over the charted window.
class MetricSeries {
  const MetricSeries({
    required this.key,
    required this.points,
    this.label,
  });

  /// The query name from the snippet (`cpu_percent`, `users_singbox`, ...).
  final String key;

  /// A distinguishing label (e.g. the `job`) when one query yields several
  /// series; `null` for a scalar query.
  final String? label;
  final List<SeriesPoint> points;

  double? get last => points.isEmpty ? null : points.last.value;
}

class SeriesPoint {
  const SeriesPoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// Time series for the native charts, fetched separately from
/// [MetricsSnapshot].
class ChartsSnapshot {
  const ChartsSnapshot({
    required this.series,
    required this.collectedAt,
    this.window = const Duration(hours: 1),
  });

  final List<MetricSeries> series;
  final DateTime collectedAt;

  /// How far back the range queries reached.
  final Duration window;

  List<MetricSeries> named(String key) =>
      [for (final s in series) if (s.key == key) s];
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
    this.profiles = MoavProfiles.defaults,
  });

  final String domain;
  final String email;

  /// Never logged. Reaches the server only inside the mode-0600 spec file.
  final String adminPassword;

  /// Additional `KEY=value` pairs for the installer environment.
  final Map<String, String> extraEnv;

  /// Compose profiles to build and start (`DEFAULT_PROFILES`), in the order
  /// given. Defaults to [MoavProfiles.defaults], i.e. upstream's own set.
  final List<String> profiles;

  @override
  String toString() =>
      'InstallSpec(domain: $domain, email: $email, profiles: $profiles)';
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
    this.step,
    this.totalSteps,
  });

  final InstallPhase phase;

  /// Most recent log lines, oldest first.
  final List<String> logTail;

  /// 0.0–1.0 when derivable from the log, else `null`. Coarse: the latest
  /// step over the step count. `InstallProgress` refines it over time.
  final double? progress;

  final String? message;

  /// Latest `[moav-deploy] step N/M` marker seen, when any.
  final int? step;
  final int? totalSteps;

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
    'anytls': 'AnyTLS',
    'snell': 'Snell',
    'cdn': 'VLESS over CDN',
    'xhttp': 'VLESS XHTTP',
    'telegram': 'Telegram MTProxy',
    'subscription': 'Subscription (v2rayNG / Streisand)',
    'wireguard': 'WireGuard',
    'wireguard-wstunnel': 'WireGuard over wstunnel',
    'amneziawg': 'AmneziaWG',
    'trusttunnel': 'TrustTunnel',
    'xdns': 'XDNS',
    'dnstt': 'dnstt',
    'slipstream': 'Slipstream',
    'masterdns': 'MasterDNS',
    'gooserelay': 'GooseRelay',
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

enum ServiceActionKind {
  start,
  stop,
  restart,
  regenerateUsers,

  /// Sets the service's `ENABLE_*` flag(s) to `true` in `.env`, then starts it.
  enable,

  /// Sets the service's `ENABLE_*` flag(s) to `false` in `.env`, then stops it.
  disable;

  /// Needs a [ServiceAction.service]; `all` makes no sense for a flag.
  bool get perService => this == enable || this == disable;
}

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

/// `ENABLE_*` toggles and `DEFAULT_PROFILES` as written in `/opt/moav/.env`.
class ServiceFlags {
  const ServiceFlags({
    required this.values,
    required this.collectedAt,
    this.defaultProfiles = const [],
  });

  /// Raw `ENABLE_*` values, unquoted; an empty string means "unset".
  final Map<String, String> values;
  final List<String> defaultProfiles;
  final DateTime collectedAt;

  /// Whether [key] is on, using upstream's default when it is unset.
  bool isOn(String key) {
    final v = values[key];
    if (v == null || v.isEmpty) return MoavServices.flagDefault(key);
    return v == 'true';
  }

  /// Whether [service] is enabled in `.env`: `null` when the service has no
  /// flag of its own. A multi-flag service counts as enabled if any flag is.
  bool? serviceEnabled(String service) {
    final t = MoavServices.toggleFor(service);
    if (t == null) return null;
    return t.allFlags.any(isOn);
  }
}
