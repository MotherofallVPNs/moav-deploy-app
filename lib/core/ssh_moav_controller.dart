import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../security/app_log.dart';
import 'app_error.dart';
import 'install_script.dart';
import 'moav_cli.dart';
import 'moav_controller.dart';
import 'moav_services.dart';
import 'server_profile.dart';
import 'ssh_connection.dart';
import 'ssh_tunnel.dart';
import 'update_script.dart';

/// Resolves the secret needed to authenticate a [ServerProfile].
///
/// Kept as a callback so this class never touches the secure store directly
/// and stays trivially testable.
typedef SecretResolver = Future<String?> Function(ServerProfile profile);

/// Runs one remote command; tests inject one to exercise the JSON/text
/// fallback without SSH.
typedef CommandRunner = Future<SshOutput> Function(
  String command, {
  bool allowFailure,
  Duration timeout,
});

/// Uploads one file to the server; tests inject one to capture the scripts
/// [startUpdate] ships without SSH.
typedef FileWriter = Future<void> Function(
  String path,
  String content, {
  String mode,
});

/// [MoavController] that drives the `moav` CLI over SSH using dartssh2.
///
/// Every method documents the exact CLI invocation it runs. Output parsing
/// prefers JSON (`--json`, MoaV 2.3+) and falls back to the 2.2.x text
/// parsers; commands without `--json` are tracked in docs/MOAV-CLI-GAPS.md.
///
/// One SSH client is kept open lazily and re-opened transparently after the
/// app was suspended and the transport dropped.
class SshMoavController implements MoavController {
  SshMoavController({
    required this.profile,
    required SecretResolver secretResolver,
    this.connectTimeout = const Duration(seconds: 15),
    CommandRunner? runner,
    FileWriter? fileWriter,
  })  : _secretResolver = secretResolver,
        _runner = runner,
        _fileWriter = fileWriter;

  final ServerProfile profile;
  final SecretResolver _secretResolver;
  final Duration connectTimeout;
  final CommandRunner? _runner;
  final FileWriter? _fileWriter;

  SSHClient? _client;

  /// The handshake in progress, shared by every caller that arrives while
  /// it runs, so concurrent first fetches never open parallel sessions.
  Future<SSHClient>? _connecting;

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
      final failure = AppError.from(e, host: profile.host, port: profile.port);
      return ConnectionCheck(
        reachable: false,
        error: failure.summary,
        failure: failure,
      );
    }
  }

  // TODO(#8): `moav --version` has no machine-readable form; regex on text.
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

  /// Uploads [InstallScript] and its spec file to `~/.moav-deploy/`, then
  /// launches it with `setsid nohup … &` so it survives the SSH session and
  /// the app being backgrounded. Returns the PID as the job id.
  ///
  /// Idempotent on the server side (see [InstallScript]); if a job is still
  /// running its handle is returned instead of starting a second one.
  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    final client = await _connected();
    await SshConnection.writeFile(
      client,
      InstallScript.scriptPath,
      InstallScript.script,
      mode: '700',
    );
    await SshConnection.writeFile(
      client,
      InstallScript.specPath,
      InstallScript.spec(spec),
    );
    final out = await SshConnection.run(client, InstallScript.launch);
    final m = RegExp(r'^(STARTED|RUNNING) (\d+)', multiLine: true)
        .firstMatch(out.stdout);
    if (m == null) {
      throw StateError('Could not start install: ${out.combined.trim()}');
    }
    return InstallHandle(jobId: m.group(2)!, logPath: InstallScript.logPath);
  }

  /// `kill -0 <pid>; tail -n 400 ~/.moav-deploy/deploy.log`.
  ///
  /// Phase is derived from the terminal `[moav-deploy] exit=` marker first,
  /// then process liveness; progress from the latest `step N/5` marker.
  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async {
    final client = await _connected();
    final out = await SshConnection.run(
      client,
      InstallScript.status(handle.jobId),
      allowFailure: true,
    );
    return parseInstallStatus(out.stdout);
  }

  static InstallStatus parseInstallStatus(
    String raw, {
    int totalSteps = InstallScript.totalSteps,
  }) {
    final idx = raw.indexOf('__LOG__');
    final head = idx < 0 ? raw : raw.substring(0, idx);
    final alive = head.contains('ALIVE');
    final log = idx < 0 ? '' : raw.substring(idx + '__LOG__'.length);
    final lines = SshConnection.stripAnsi(log)
        .split('\n')
        .map((l) => l.trimRight())
        .toList();
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    int? exitCode;
    int step = 0;
    String? stepTitle;
    for (final l in lines) {
      if (l.startsWith(InstallScript.exitMarker)) {
        exitCode = int.tryParse(l.substring(InstallScript.exitMarker.length).trim());
      } else if (l.startsWith(InstallScript.stepMarker)) {
        final m = RegExp(r'step (\d+)/\d+: (.*)').firstMatch(l);
        if (m != null) {
          step = int.parse(m.group(1)!);
          stepTitle = m.group(2);
        }
      }
    }
    final progress = step == 0 ? null : step / totalSteps;

    if (exitCode != null) {
      return InstallStatus(
        phase: exitCode == 0 ? InstallPhase.succeeded : InstallPhase.failed,
        logTail: lines,
        progress: exitCode == 0 ? 1.0 : progress,
        message: exitCode == 0
            ? 'Install finished'
            : 'Install failed (exit $exitCode)',
      );
    }
    if (alive) {
      return InstallStatus(
        phase: step == 0 ? InstallPhase.pending : InstallPhase.running,
        logTail: lines,
        progress: progress,
        message: stepTitle,
      );
    }
    if (lines.isEmpty) {
      return const InstallStatus(
        phase: InstallPhase.unknown,
        message: 'No install log found on the server',
      );
    }
    return InstallStatus(
      phase: InstallPhase.failed,
      logTail: lines,
      progress: progress,
      message: 'Install process ended without reporting a result',
    );
  }

  /// `moav doctor --json` (exits non-zero when a check fails); a 2.2.x box
  /// rejects the flag with usage text, so `moav doctor` is run instead.
  @override
  Future<DoctorReport> doctor() async {
    const timeout = Duration(minutes: 3);
    var out = await _run(MoavCli.doctorJson, allowFailure: true, timeout: timeout);
    var report = MoavCli.parseDoctorJson(out.stdout);
    if (report != null) {
      _logFormat('doctor', CliFormat.json);
    } else {
      _logFormat('doctor', CliFormat.text);
      out = await _run(MoavCli.doctor, allowFailure: true, timeout: timeout);
      report = MoavCli.parseDoctor(out.stdout);
    }
    if (report.checks.isEmpty) {
      throw StateError('moav doctor produced no checks: ${_short(out.combined)}');
    }
    return report;
  }

  /// `moav user list --json`; 2.2.x ignores the flag and prints the sectioned
  /// text, which is parsed from the same output (re-run only if neither).
  @override
  Future<List<MoavUser>> listUsers() async {
    var out = await _run(MoavCli.userListJson, allowFailure: true);
    var parsed = MoavCli.parseUserListAny(out.stdout);
    if (parsed.format == CliFormat.text &&
        !MoavCli.looksLikeUserListText(out.stdout)) {
      out = await _run(MoavCli.userList);
      parsed = MoavCli.parseUserListAny(out.stdout);
    }
    _logFormat('user list', parsed.format);
    return parsed.users;
  }

  /// `moav user add <name> --json`; 2.2.x rejects the flag before creating
  /// anything, so the text form is run instead. Name is validated locally.
  @override
  Future<MoavUser> addUser(String name) async {
    _validateName(name);
    const timeout = Duration(minutes: 3);
    var out = await _run(MoavCli.userAddJson(name),
        allowFailure: true, timeout: timeout);
    final result = MoavCli.parseUserAction(out.stdout, user: name);
    String text;
    if (result != null) {
      _logFormat('user add', CliFormat.json);
      if (!result.ok && !result.alreadyExists) {
        throw StateError(
            'moav user add failed: ${result.error ?? _short(out.stderr)}');
      }
      text = out.stderr;
    } else {
      _logFormat('user add', CliFormat.text);
      out = await _run(MoavCli.userAdd(name), timeout: timeout);
      text = SshConnection.stripAnsi(out.stdout);
      if (RegExp(r'\b(error|failed)\b', caseSensitive: false).hasMatch(text) &&
          !text.contains('already exists')) {
        throw StateError('moav user add reported a problem: ${_short(text)}');
      }
    }
    final users = await listUsers();
    return users.firstWhere(
      (u) => u.name == name,
      orElse: () => throw StateError(
        "User '$name' is not listed after 'moav user add': ${_short(text)}",
      ),
    );
  }

  /// `moav user remove <name> --json`, falling back to `moav user revoke`
  /// (always exits 0). Either way success is confirmed by re-listing users.
  @override
  Future<void> removeUser(String name) async {
    _validateName(name);
    const timeout = Duration(minutes: 3);
    var out = await _run(MoavCli.userRemoveJson(name),
        allowFailure: true, timeout: timeout);
    final result = MoavCli.parseUserAction(out.stdout, user: name);
    String text;
    if (result != null) {
      _logFormat('user remove', CliFormat.json);
      text = result.error ?? out.stderr;
    } else {
      _logFormat('user remove', CliFormat.text);
      out = await _run(MoavCli.userRevoke(name),
          allowFailure: true, timeout: timeout);
      text = SshConnection.stripAnsi(out.stdout);
    }
    final users = await listUsers();
    if (users.any((u) => u.name == name)) {
      throw StateError("User '$name' still exists after revoke: ${_short(text)}");
    }
  }

  /// One shell round trip that prints every text config in
  /// `/opt/moav/outputs/bundles/<user>` base64-framed (see
  /// [MoavCli.bundleDump]). Images, the HTML guide and zips are skipped
  /// server-side, as are files over [maxBundleFileBytes].
  ///
  /// The previous SFTP walk cost four serial round trips per file (open,
  /// stat, read, close) on top of the directory listing, which on a mobile
  /// link made a 20-file bundle take tens of seconds.
  @override
  Future<Bundle> getBundle(String user) async {
    _validateName(user);
    final out = await _run(MoavCli.bundleDump(user),
        allowFailure: true, timeout: bundleTimeout);
    final files = MoavCli.parseBundleDump(out.stdout);
    if (files == null) {
      throw StateError(
        "No bundle found for '$user'. Add the user again or run "
        "'moav regenerate-users' on the server.",
      );
    }
    final entries = <BundleEntry>[];
    for (final f in files) {
      final entry = MoavCli.bundleEntry(f.name, f.content);
      if (entry != null) entries.add(entry);
    }
    entries.sort(MoavCli.compareEntries);
    return Bundle(
      user: user,
      entries: entries,
      fetchedAt: DateTime.now(),
      path: '${MoavCli.bundlesDir}/$user',
    );
  }

  /// Bundle files larger than this are configs we never render (safety cap).
  static const maxBundleFileBytes = MoavCli.maxBundleFileBytes;

  /// A bundle is a few dozen small files; base64 on the box is instant.
  static const bundleTimeout = Duration(seconds: 60);

  // TODO(#8): no `--json` for these; only the exit code signals failure.
  /// `moav start|stop|restart [service]` or `moav regenerate-users`.
  ///
  /// Enable/disable first write the service's `ENABLE_*` flag(s) to `.env`
  /// (see [MoavCli.setEnableFlags]), then run `moav start` / `moav stop`
  /// for it, so a failure names the step that broke.
  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    final svc = action.service;
    if (svc != null) _validateName(svc);
    if (action.kind.perService) {
      if (svc == null) {
        throw ArgumentError('${action.kind.name} needs a service name');
      }
      final toggle = MoavServices.toggleFor(svc);
      if (toggle == null) {
        throw StateError(
            "'$svc' has no ENABLE_* flag of its own; it follows the protocols it serves.");
      }
      final enabled = action.kind == ServiceActionKind.enable;
      await _run(MoavCli.setEnableFlags(toggle.flags(enabled: enabled)),
          timeout: flagsTimeout, onOutput: onOutput);
      await _run(
        MoavCli.service(ServiceAction(
          enabled ? ServiceActionKind.start : ServiceActionKind.stop,
          service: svc,
        )),
        timeout: const Duration(minutes: 10),
        onOutput: onOutput,
      );
      return;
    }
    await _run(MoavCli.service(action),
        timeout: const Duration(minutes: 10), onOutput: onOutput);
  }

  /// `PORT_ADMIN`, `ENABLE_ADMIN_UI` and `ADMIN_PASSWORD` from `.env` (see
  /// [MoavCli.adminPanel]). The command never fails and its output is
  /// parsed here only, so the password cannot end up in an error or a log.
  @override
  Future<AdminPanelAccess> adminPanelAccess() async {
    final out = await _run(MoavCli.adminPanel,
        allowFailure: true, timeout: flagsTimeout);
    final access = MoavCli.parseAdminPanel(out.stdout);
    if (access == null) {
      throw StateError('Could not read the admin dashboard settings from .env');
    }
    return access;
  }

  /// `ssh -L` through the cached session to `127.0.0.1:[remotePort]` on
  /// the server. Close the tunnel when the view that uses it goes away.
  @override
  Future<ServerTunnel> openTunnel(int remotePort) async {
    final client = await _connected();
    try {
      return await SshTunnel.open(client, remotePort);
    } on Object catch (e) {
      throw AppError.from(e, host: profile.host, port: profile.port);
    }
  }

  /// `PORT_GRAFANA`, `ENABLE_MONITORING`, the answering scheme and
  /// `ADMIN_PASSWORD` from `.env` (see [MoavCli.grafanaPanel]); handled
  /// exactly like [adminPanelAccess] so the password never reaches a log.
  @override
  Future<GrafanaAccess> grafanaAccess() async {
    final out = await _run(MoavCli.grafanaPanel,
        allowFailure: true, timeout: flagsTimeout);
    final access = MoavCli.parseGrafanaPanel(out.stdout);
    if (access == null) {
      throw StateError('Could not read the Grafana settings from .env');
    }
    return access;
  }

  // TODO(#8): Prometheus is not published on the host and there is no
  // `moav metrics`; range queries go through `docker exec` as well.
  /// Time series for the native charts (see [MoavCli.prometheusRange]).
  @override
  Future<ChartsSnapshot> metricSeries() async {
    final out = await _run(MoavCli.prometheusRange,
        allowFailure: true, timeout: metricsTimeout);
    return MoavCli.parseMetricSeries(out.stdout);
  }

  /// A `grep` over `.env`; see [MoavCli.serviceFlags].
  static const flagsTimeout = Duration(seconds: 30);

  // TODO(#8): no `moav profiles --json`; `.env` is read directly.
  /// `ENABLE_*` toggles and `DEFAULT_PROFILES` from `/opt/moav/.env`.
  @override
  Future<ServiceFlags> serviceFlags() async {
    final out = await _run(MoavCli.serviceFlags,
        allowFailure: true, timeout: flagsTimeout);
    return MoavCli.parseServiceFlags(out.stdout);
  }

  /// `moav status --json`; 2.2.x ignores the flag and prints the box-drawn
  /// table, which is parsed from the same output (re-run only if neither).
  @override
  Future<ServiceStatusReport> status() async {
    const timeout = Duration(minutes: 2);
    var out = await _run(MoavCli.statusJson, allowFailure: true, timeout: timeout);
    var parsed = MoavCli.parseStatusAny(out.stdout);
    if (parsed.format == CliFormat.text && parsed.report.services.isEmpty) {
      out = await _run(MoavCli.status, allowFailure: true, timeout: timeout);
      parsed = MoavCli.parseStatusAny(out.stdout);
    }
    _logFormat('status', parsed.format);
    if (parsed.report.services.isEmpty) {
      throw StateError('moav status listed no services: ${_short(out.combined)}');
    }
    return parsed.report;
  }

  /// Dashboard URLs from `.env` and Grafana `/api/health` only; cheap, so it
  /// gets the default timeout (see [MoavCli.monitoring]).
  @override
  Future<Monitoring> monitoring() async {
    final out = await _run(MoavCli.monitoring,
        allowFailure: true, timeout: monitoringTimeout);
    return MoavCli.parseMonitoring(out.stdout);
  }

  // TODO(#8): Prometheus is not published on the host and there is no
  // `moav metrics`; this stays a text/shell path.
  /// Headline metrics from Prometheus via `docker exec`
  /// (see [MoavCli.prometheus]). Slow on a loaded box, hence [metricsTimeout].
  @override
  Future<MetricsSnapshot> metrics() async {
    final out = await _run(MoavCli.prometheus,
        allowFailure: true, timeout: metricsTimeout);
    final parsed = MoavCli.parseMonitoring(out.stdout);
    return MetricsSnapshot(
      metrics: parsed.metrics,
      collectedAt: parsed.collectedAt ?? DateTime.now(),
    );
  }

  /// Grafana health and dashboard URLs; a quick shell snippet.
  static const monitoringTimeout = Duration(seconds: 30);

  /// Prometheus queries through `docker exec` on a possibly swapping box.
  static const metricsTimeout = Duration(seconds: 90);

  /// `/proc` reads plus `moav --version`; includes a one-second CPU sample.
  static const serverInfoTimeout = Duration(seconds: 45);

  /// `moav doctor updates` asks GitHub with a five-second curl limit.
  static const updateCheckTimeout = Duration(seconds: 60);

  // TODO(#8): no `--json` for host metrics or `moav --version`; text path.
  /// CPU, RAM, swap, disk and uptime from `/proc` and `df`, plus the
  /// `moav --version` banner and component table (see [MoavCli.hostInfo]).
  @override
  Future<ServerInfo> serverInfo() async {
    final out = await _run(MoavCli.hostInfo,
        allowFailure: true, timeout: serverInfoTimeout);
    final info = MoavCli.parseHostInfo(out.stdout);
    if (info.host.isEmpty && info.version.moavVersion == null) {
      throw StateError(
          'The server returned no host metrics: ${_short(out.combined)}');
    }
    return info;
  }

  /// `moav doctor updates --json` (exits non-zero when an update exists); a
  /// 2.2.x box rejects the flag, so `moav doctor updates` is run instead.
  @override
  Future<UpdateCheck> checkForUpdates() async {
    var out = await _run(MoavCli.doctorUpdatesJson,
        allowFailure: true, timeout: updateCheckTimeout);
    var check = MoavCli.parseUpdateCheck(out.stdout);
    if (check != null && MoavCli.decodeJsonDocument(out.stdout) != null) {
      _logFormat('doctor updates', CliFormat.json);
    } else {
      _logFormat('doctor updates', CliFormat.text);
      out = await _run(MoavCli.doctorUpdates,
          allowFailure: true, timeout: updateCheckTimeout);
      check = MoavCli.parseUpdateCheck(out.stdout);
    }
    if (check == null) {
      throw StateError(
          'moav doctor updates gave no version: ${_short(out.combined)}');
    }
    return check;
  }

  /// Uploads [UpdateScript] to `~/.moav-deploy/update.sh` and launches it
  /// with `setsid nohup`. A job still running is left alone (idempotent).
  @override
  Future<void> startUpdate() async {
    await _writeFile(UpdateScript.scriptPath, UpdateScript.body, mode: '700');
    final out = await _run(UpdateScript.launch);
    if (!RegExp(r'^(STARTED|RUNNING) \d+', multiLine: true)
        .hasMatch(out.stdout)) {
      throw StateError('Could not start the update: ${_short(out.combined)}');
    }
  }

  /// `kill -0 $(cat update.pid); tail -n 400 ~/.moav-deploy/update.log`.
  @override
  Future<InstallStatus?> updateStatus() async {
    final out = await _run(UpdateScript.status(), allowFailure: true);
    if (out.stdout.contains('NOJOB') || !out.stdout.contains('__LOG__')) {
      return null;
    }
    return parseInstallStatus(out.stdout, totalSteps: UpdateScript.totalSteps);
  }

  static void _logFormat(String command, CliFormat format) =>
      AppLog.info('moav-cli', '$command via ${format.name}');

  Future<void> _writeFile(String path, String content,
      {String mode = '600'}) async {
    final writer = _fileWriter;
    if (writer != null) return writer(path, content, mode: mode);
    final client = await _connected();
    await SshConnection.writeFile(client, path, content, mode: mode);
  }

  Future<SshOutput> _run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
    OutputSink? onOutput,
  }) async {
    final runner = _runner;
    if (runner != null) {
      // Injected runners answer in one go; replay the output so views that
      // stream it see the same text.
      final out =
          await runner(command, allowFailure: allowFailure, timeout: timeout);
      onOutput?.call(out.combined);
      return out;
    }
    final client = await _connected();
    try {
      return await SshConnection.run(
        client,
        command,
        allowFailure: allowFailure,
        timeout: timeout,
        onOutput: onOutput,
      );
    } on SshCommandException {
      rethrow; // the session is fine; the command just failed
    } on Object catch (e) {
      // Timeouts, socket and transport errors leave the cached client in an
      // unknown state; drop it so the next call reconnects.
      _dropClient();
      throw AppError.from(e, host: profile.host, port: profile.port);
    }
  }

  static void _validateName(String name) {
    if (!MoavUser.validName.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Use only letters, numbers, underscores and hyphens',
      );
    }
  }

  static String _short(String s) {
    final t = SshConnection.stripAnsi(s).trim();
    return t.length > 300 ? '…${t.substring(t.length - 300)}' : t;
  }

  /// Closes the cached SSH client, if any, and refuses to reopen one.
  void dispose() {
    _disposed = true;
    _dropClient();
  }

  // ---------------------------------------------------------------------------

  Future<SSHClient> _connected() {
    final existing = _client;
    if (existing != null && !existing.isClosed) return Future.value(existing);
    final pending = _connecting;
    if (pending != null) return pending;
    final f = _open();
    _connecting = f;
    return f.whenComplete(() {
      if (identical(_connecting, f)) _connecting = null;
    });
  }

  Future<SSHClient> _open() async {
    final secret = await _secretResolver(profile);
    if (secret == null || secret.isEmpty) {
      throw StateError('No stored credential for ${profile.label}');
    }
    final usePassword = profile.authMethod == SshAuthMethod.password;
    try {
      final client = await SshConnection.open(
        host: profile.host,
        port: profile.port,
        username: profile.username,
        privateKeyPem: usePassword ? null : secret,
        password: usePassword ? secret : null,
        timeout: connectTimeout,
      );
      // dispose() may have run meanwhile; never keep a session nobody owns.
      if (_disposed) {
        client.close();
        throw StateError('Controller for ${profile.label} was disposed');
      }
      _client = client;
      return client;
    } on Object catch (e) {
      throw AppError.from(e, host: profile.host, port: profile.port);
    }
  }

  bool _disposed = false;

  void _dropClient() {
    final c = _client;
    _client = null;
    if (c != null && !c.isClosed) c.close();
  }

  /// One-line error text safe to surface. Never includes credentials or a
  /// stack trace. Prefer [AppError.from] when the UI can show a hint too.
  static String describeError(Object e) => AppError.from(e).message;
}
