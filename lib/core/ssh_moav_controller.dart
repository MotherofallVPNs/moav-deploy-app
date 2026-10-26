import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'app_error.dart';
import 'install_script.dart';
import 'moav_cli.dart';
import 'moav_controller.dart';
import 'server_profile.dart';
import 'ssh_connection.dart';

/// Resolves the secret needed to authenticate a [ServerProfile].
///
/// Kept as a callback so this class never touches the secure store directly
/// and stays trivially testable.
typedef SecretResolver = Future<String?> Function(ServerProfile profile);

/// [MoavController] that drives the `moav` CLI over SSH using dartssh2.
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

  static InstallStatus parseInstallStatus(String raw) {
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
    final progress = step == 0 ? null : step / InstallScript.totalSteps;

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

  /// `moav doctor`, grouped per check. Text-only today (no `--json`).
  @override
  Future<DoctorReport> doctor() async {
    final out = await _run(MoavCli.doctor,
        allowFailure: true, timeout: const Duration(minutes: 3));
    final report = MoavCli.parseDoctor(out.stdout);
    if (report.checks.isEmpty) {
      throw StateError('moav doctor produced no checks: ${_short(out.combined)}');
    }
    return report;
  }

  /// `moav user list` (sectioned text; no `--json` yet).
  @override
  Future<List<MoavUser>> listUsers() async {
    final out = await _run(MoavCli.userList);
    return MoavCli.parseUserList(out.stdout);
  }

  /// `moav user add <name>`. Name is validated locally with the same rule the
  /// CLI enforces, so a bad name never reaches the shell.
  @override
  Future<MoavUser> addUser(String name) async {
    _validateName(name);
    final out = await _run(MoavCli.userAdd(name), timeout: const Duration(minutes: 3));
    final text = SshConnection.stripAnsi(out.stdout);
    if (RegExp(r'\b(error|failed)\b', caseSensitive: false).hasMatch(text) &&
        !text.contains('already exists')) {
      throw StateError('moav user add reported a problem: ${_short(text)}');
    }
    final users = await listUsers();
    return users.firstWhere(
      (u) => u.name == name,
      orElse: () => throw StateError(
        "User '$name' is not listed after 'moav user add': ${_short(text)}",
      ),
    );
  }

  /// `moav user revoke <name>`. The CLI always exits 0 here (it loops with
  /// `|| true`), so success is confirmed by re-listing users.
  @override
  Future<void> removeUser(String name) async {
    _validateName(name);
    final out = await _run(MoavCli.userRevoke(name),
        allowFailure: true, timeout: const Duration(minutes: 3));
    final text = SshConnection.stripAnsi(out.stdout);
    final users = await listUsers();
    if (users.any((u) => u.name == name)) {
      throw StateError("User '$name' still exists after revoke: ${_short(text)}");
    }
  }

  /// Lists `/opt/moav/outputs/bundles/<user>` over SFTP and reads every
  /// text config (images, HTML guide and zips are skipped).
  @override
  Future<Bundle> getBundle(String user) async {
    _validateName(user);
    final client = await _connected();
    final dir = '${MoavCli.bundlesDir}/$user';
    final sftp = await client.sftp().timeout(connectTimeout);
    try {
      final List<SftpName> names;
      try {
        names = await sftp.listdir(dir).timeout(connectTimeout);
      } on SftpStatusError {
        throw StateError(
          "No bundle found for '$user'. Add the user again or run "
          "'moav regenerate-users' on the server.",
        );
      }
      final entries = <BundleEntry>[];
      for (final n in names) {
        if (n.filename == '.' || n.filename == '..') continue;
        if (n.attr.isDirectory) continue;
        if (MoavCli.classifyBundleFile(n.filename) == null) continue;
        if ((n.attr.size ?? 0) > maxBundleFileBytes) continue;
        final f = await sftp.open('$dir/${n.filename}');
        try {
          final bytes = await f.readBytes().timeout(connectTimeout);
          final entry = MoavCli.bundleEntry(
            n.filename,
            utf8.decode(bytes, allowMalformed: true),
          );
          if (entry != null) entries.add(entry);
        } finally {
          await f.close();
        }
      }
      entries.sort(MoavCli.compareEntries);
      return Bundle(
        user: user,
        entries: entries,
        fetchedAt: DateTime.now(),
        path: dir,
      );
    } finally {
      await sftp.close();
    }
  }

  /// Bundle files larger than this are configs we never render (safety cap).
  static const maxBundleFileBytes = 256 * 1024;

  /// `moav test <name> --json`. Builds a client image on first run, so this
  /// can take minutes; the JSON document is the tail of stdout.
  @override
  Future<TestMatrix> testUser(String name) async {
    _validateName(name);
    final out = await _run(MoavCli.test(name),
        allowFailure: true, timeout: testTimeout);
    return MoavCli.parseTest(name, out.stdout);
  }

  static const testTimeout = Duration(minutes: 15);

  /// `moav start|stop|restart [service]` or `moav regenerate-users`.
  @override
  Future<void> service(ServiceAction action) async {
    if (action.service != null) _validateName(action.service!);
    await _run(MoavCli.service(action), timeout: const Duration(minutes: 10));
  }

  /// `moav status` (box-drawn table; parsed as text).
  @override
  Future<ServiceStatusReport> status() async {
    final out = await _run(MoavCli.status,
        allowFailure: true, timeout: const Duration(minutes: 2));
    final report = MoavCli.parseStatus(out.stdout);
    if (report.services.isEmpty) {
      throw StateError('moav status listed no services: ${_short(out.combined)}');
    }
    return report;
  }

  /// Dashboard URLs from `.env`, Grafana `/api/health`, and headline metrics
  /// from Prometheus via `docker exec` (see [MoavCli.monitoring]).
  @override
  Future<Monitoring> monitoring() async {
    final out = await _run(MoavCli.monitoring,
        allowFailure: true, timeout: const Duration(minutes: 1));
    return MoavCli.parseMonitoring(out.stdout);
  }

  Future<SshOutput> _run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = await _connected();
    try {
      return await SshConnection.run(
        client,
        command,
        allowFailure: allowFailure,
        timeout: timeout,
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
    try {
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
    } on Object catch (e) {
      throw AppError.from(e, host: profile.host, port: profile.port);
    }
  }

  void _dropClient() {
    final c = _client;
    _client = null;
    if (c != null && !c.isClosed) c.close();
  }

  /// One-line error text safe to surface. Never includes credentials or a
  /// stack trace. Prefer [AppError.from] when the UI can show a hint too.
  static String describeError(Object e) => AppError.from(e).message;
}
