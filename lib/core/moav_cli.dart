import 'dart:convert';

import 'moav_controller.dart';
import 'ssh_connection.dart';

/// Which CLI output format a parser consumed.
enum CliFormat { json, text }

/// Result of `moav user add|remove NAME --json` for one user.
class UserActionResult {
  const UserActionResult({
    required this.ok,
    required this.action,
    this.error,
    this.bundleDir,
  });

  final bool ok;
  final String action;
  final String? error;
  final String? bundleDir;

  /// The JSON path reports an existing user as an error; the app treats it as
  /// done, matching the text path.
  bool get alreadyExists => error == 'already exists';
}

/// The exact `moav` CLI invocations the SSH controller runs, plus the parsers
/// that turn their output into models.
///
/// JSON parsers follow the MoaV 2.3.x `--json` schemas (verified on v2.3.1);
/// the text parsers remain as the 2.2.x fallback. See docs/MOAV-CLI-GAPS.md.
class MoavCli {
  MoavCli._();

  static const root = '/opt/moav';
  static const bundlesDir = '$root/outputs/bundles';

  /// `cd` into the checkout and resolve the CLI even when `moav` is not on
  /// the non-login shell's PATH.
  static const prelude = 'cd $root 2>/dev/null; '
      'M="\$(command -v moav 2>/dev/null || echo $root/moav.sh)"; ';

  // JSON commands keep stderr separate so stdout is exactly one document.
  static const statusJson = '$prelude"\$M" status --json';
  static const doctorJson = '$prelude"\$M" doctor --json';
  static const userListJson = '$prelude"\$M" user list --json';
  static String userAddJson(String name) =>
      '$prelude"\$M" user add ${SshConnection.shellQuote(name)} --json';
  static String userRemoveJson(String name) =>
      '$prelude"\$M" user remove ${SshConnection.shellQuote(name)} --json';
  static String test(String name) =>
      '$prelude"\$M" test ${SshConnection.shellQuote(name)} --json 2>/dev/null';

  // Text commands: the 2.2.x fallback for the JSON ones above.
  static const userList = '$prelude"\$M" user list 2>&1';
  static String userAdd(String name) =>
      '$prelude"\$M" user add ${SshConnection.shellQuote(name)} 2>&1';
  static const doctor = '$prelude"\$M" doctor 2>&1';
  static const status = '$prelude"\$M" status 2>&1';

  // TODO(#8): text path of `user revoke` exits 0 even for an unknown user;
  // only the `--json` form above reports failure.
  static String userRevoke(String name) =>
      '$prelude"\$M" user revoke ${SshConnection.shellQuote(name)} 2>&1';

  // TODO(#8): `start|stop|restart|regenerate-users` have no `--json`; the
  // app relies on the exit code and re-reads `moav status` afterwards.
  static String service(ServiceAction a) {
    final verb = switch (a.kind) {
      ServiceActionKind.start => 'start',
      ServiceActionKind.stop => 'stop',
      ServiceActionKind.restart => 'restart',
      ServiceActionKind.regenerateUsers => 'regenerate-users',
    };
    final target = a.service == null || a.kind == ServiceActionKind.regenerateUsers
        ? ''
        : ' ${SshConnection.shellQuote(a.service!)}';
    return '$prelude"\$M" $verb$target 2>&1';
  }

  /// Shared by [monitoring] and [prometheus]: reads a `.env` value.
  static const _envReader = '''
cd $root 2>/dev/null || exit 0
ev() { grep -E "^\$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/[[:space:]]+#.*\$//; s/^"//; s/"\$//; s/^'"'"'//; s/'"'"'\$//' | tr -d '[:space:]'; }
''';

  /// Emits marker-delimited sections: dashboard URLs derived exactly like
  /// `get_grafana_url` in `lib/common.sh` and the Grafana `/api/health`
  /// body. The Prometheus section is left empty; see [prometheus].
  // TODO(#8): no `moav metrics` upstream; this shell snippet is the text path.
  static const monitoring = '''
$_envReader
DOMAIN=\$(ev DOMAIN); SERVER_IP=\$(ev SERVER_IP); PG=\$(ev PORT_GRAFANA); PA=\$(ev PORT_ADMIN); GS=\$(ev GRAFANA_SUBDOMAIN); CDN=\$(ev ENABLE_CDN); PC=\$(ev PORT_GRAFANA_CDN)
H="\${DOMAIN:-\${SERVER_IP:-localhost}}"
echo "__URLS__"
echo "grafana=https://\$H:\${PG:-9444}"
echo "admin=https://\$H:\${PA:-9443}"
if [ "\$CDN" = "true" ] && [ -n "\$GS" ] && [ -n "\$DOMAIN" ]; then echo "grafana_cdn=https://\$GS.\$DOMAIN:\${PC:-2083}"; fi
echo "__HEALTH__"
curl -sk -m 5 "https://127.0.0.1:\${PG:-9444}/api/health" 2>/dev/null || curl -s -m 5 "http://127.0.0.1:\${PG:-9444}/api/health" 2>/dev/null
echo
echo "__PROM__"
echo "__END__"
''';

  /// One Prometheus instant query per headline metric (via `docker exec`, as
  /// Prometheus is not published on the host). The queries run in parallel
  /// and print in a fixed order, so one slow query costs seconds, not
  /// seconds times seven. Same markers as [monitoring]; URL/health empty.
  // TODO(#8): no `moav metrics` upstream; this shell snippet is the text path.
  static const prometheus = '''
$_envReader
echo "__URLS__"
echo "__HEALTH__"
echo
echo "__PROM__"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx moav-prometheus; then
  PP=\$(docker inspect -f '{{join .Args " "}}' moav-prometheus 2>/dev/null | grep -oE 'listen-address=[^ ]*:[0-9]+' | grep -oE '[0-9]+\$'); PP=\${PP:-9090}
  T=\$(mktemp -d 2>/dev/null || echo "/tmp/moav-deploy-prom.\$\$"); mkdir -p "\$T"
  q() { docker exec moav-prometheus wget -qO- -T 8 "http://127.0.0.1:\$PP/api/v1/query?query=\$2" > "\$T/\$1" 2>/dev/null & }
  q targets_up 'count(up%3D%3D1)'
  q load1 'node_load1'
  q mem_available_bytes 'node_memory_MemAvailable_bytes'
  q mem_total_bytes 'node_memory_MemTotal_bytes'
  q rx_bytes_per_s 'sum(rate(node_network_receive_bytes_total%7Bdevice!~%22lo%7Cveth.*%7Cbr-.*%7Cdocker.*%22%7D%5B5m%5D))'
  q tx_bytes_per_s 'sum(rate(node_network_transmit_bytes_total%7Bdevice!~%22lo%7Cveth.*%7Cbr-.*%7Cdocker.*%22%7D%5B5m%5D))'
  q disk_free_bytes 'node_filesystem_avail_bytes%7Bmountpoint%3D%22/%22%7D'
  wait
  for n in targets_up load1 mem_available_bytes mem_total_bytes rx_bytes_per_s tx_bytes_per_s disk_free_bytes; do
    echo "__Q__ \$n"; cat "\$T/\$n" 2>/dev/null; echo
  done
  rm -rf "\$T"
fi
echo "__END__"
''';

  /// Host metrics and versions, marker-delimited. CPU usage comes from two
  /// `/proc/stat` samples one second apart; `df -Pk` keeps it POSIX so it
  /// also works on an Alpine box.
  // TODO(#8): no `--json` for host metrics or `moav --version`; text path.
  static const hostInfo = '''
$prelude
echo "__LOAD__"; cat /proc/loadavg 2>/dev/null
echo "__NPROC__"; nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null
echo "__CPU1__"; grep '^cpu ' /proc/stat 2>/dev/null
sleep 1
echo "__CPU2__"; grep '^cpu ' /proc/stat 2>/dev/null
echo "__MEM__"; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null
echo "__DISK__"; df -Pk / 2>/dev/null | tail -n 1
echo "__UPTIME__"; cat /proc/uptime 2>/dev/null
echo "__VERSION__"; "\$M" --version 2>/dev/null
echo "__GIT__"; git -C $root rev-parse --abbrev-ref HEAD 2>/dev/null; git -C $root rev-parse --short HEAD 2>/dev/null
echo "__END__"
''';

  /// `moav doctor updates --json` (2.3+) and its 2.2.x text form.
  static const doctorUpdatesJson = '$prelude"\$M" doctor updates --json';
  static const doctorUpdates = '$prelude"\$M" doctor updates 2>&1';

  // ---------------------------------------------------------------------------
  // JSON documents (MoaV >= 2.3.0)
  // ---------------------------------------------------------------------------

  /// Decodes stdout as one JSON document (object or array). Returns `null`
  /// when the output is not JSON, which is how a 2.2.x box answers `--json`.
  static Object? decodeJsonDocument(String raw) {
    final text = SshConnection.stripAnsi(raw).trim();
    if (text.isEmpty) return null;
    // Line-anchored so usage text such as `doctor [check]` is never a document.
    final start = text.indexOf(RegExp(r'^[\[{]', multiLine: true));
    if (start < 0) return null;
    final end = text.lastIndexOf(text[start] == '[' ? ']' : '}');
    if (end <= start) return null;
    try {
      final v = jsonDecode(text.substring(start, end + 1));
      return v is Map || v is List ? v : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?>? _asMap(Object? v) =>
      v is Map ? v.cast<String, Object?>() : null;

  static List<String> _stringList(Object? v) =>
      v is List ? [for (final e in v) e.toString()] : const [];

  // ---------------------------------------------------------------------------
  // moav user list
  // ---------------------------------------------------------------------------

  /// Upstream calls the MTProxy store `telemt`; the text sections and the app
  /// call it `telegram`, so both paths yield the same protocol names.
  static const _serviceAliases = {'telemt': 'telegram'};

  /// `moav user list --json`: `[{user, services: [...], bundle: bool}]`.
  /// Returns `null` when [raw] is not that document.
  static List<MoavUser>? parseUserListJson(String raw) {
    final doc = decodeJsonDocument(raw);
    if (doc is! List) return null;
    final users = <MoavUser>[];
    for (final e in doc) {
      final m = _asMap(e);
      final name = m?['user']?.toString();
      if (m == null || name == null || name.isEmpty) continue;
      final services = _stringList(m['services'])
          .map((s) => _serviceAliases[s] ?? s)
          .toSet()
          .toList()
        ..sort();
      users.add(MoavUser(
        name: name,
        bundleReady: m['bundle'] == true,
        protocols: services,
      ));
    }
    users.sort((a, b) => a.name.compareTo(b.name));
    return users;
  }

  /// Prefers the JSON document, else parses the 2.2.x sectioned text.
  static ({List<MoavUser> users, CliFormat format}) parseUserListAny(
      String raw) {
    final json = parseUserListJson(raw);
    if (json != null) return (users: json, format: CliFormat.json);
    return (users: parseUserList(raw), format: CliFormat.text);
  }

  /// Whether [raw] looks like the 2.2.x text listing (so no re-run is needed).
  static bool looksLikeUserListText(String raw) =>
      SshConnection.stripAnsi(raw).split('\n').any(_sectionRe.hasMatch);

  static const _sectionNames = <String, String>{
    'sing-box': 'sing-box',
    'wireguard': 'wireguard',
    'amneziawg': 'amneziawg',
    'xray': 'xray',
    'trusttunnel': 'trusttunnel',
    'telegram': 'telegram',
    'user bundles': 'bundles',
  };

  static final _sectionRe = RegExp(r'^\s*===\s*(.+?)\s*===\s*$');
  static final _entryRe = RegExp(r'^\s*[•*\-]\s+(\S+)(.*)$');

  /// Parses the sectioned text of `moav user list` into one [MoavUser] per
  /// distinct name, sorted. A user is `bundleReady` when listed under
  /// "User Bundles" or tagged `[bundle ready]`.
  static List<MoavUser> parseUserList(String raw) {
    final text = SshConnection.stripAnsi(raw);
    final protocols = <String, Set<String>>{};
    final bundles = <String>{};
    String? section;
    for (final line in text.split('\n')) {
      final sm = _sectionRe.firstMatch(line);
      if (sm != null) {
        final title = sm.group(1)!.toLowerCase();
        section = null;
        for (final e in _sectionNames.entries) {
          if (title.startsWith(e.key)) {
            section = e.value;
            break;
          }
        }
        continue;
      }
      if (section == null) continue;
      final em = _entryRe.firstMatch(line);
      if (em == null) continue;
      final name = em.group(1)!;
      final rest = em.group(2) ?? '';
      if (name.startsWith('(')) continue; // "(no peers)"
      if (section == 'bundles' || rest.contains('[bundle ready]')) {
        bundles.add(name);
      }
      if (section != 'bundles') {
        protocols.putIfAbsent(name, () => <String>{}).add(section);
      } else {
        protocols.putIfAbsent(name, () => <String>{});
      }
    }
    final names = protocols.keys.toList()..sort();
    return [
      for (final n in names)
        MoavUser(
          name: n,
          bundleReady: bundles.contains(n),
          protocols: protocols[n]!.toList()..sort(),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // moav user add|remove NAME --json
  // ---------------------------------------------------------------------------

  /// `{ok, action, users: [{user, ok, error?, bundle_dir?}]}` or a top-level
  /// `{ok: false, action, error}`. Returns `null` when not JSON (2.2.x).
  static UserActionResult? parseUserAction(String raw, {required String user}) {
    final doc = _asMap(decodeJsonDocument(raw));
    if (doc == null || doc['ok'] is! bool) return null;
    final action = doc['action']?.toString() ?? '';
    final users = doc['users'];
    if (users is List) {
      for (final e in users) {
        final m = _asMap(e);
        if (m == null || m['user']?.toString() != user) continue;
        return UserActionResult(
          ok: m['ok'] == true,
          action: action,
          error: m['error']?.toString(),
          bundleDir: m['bundle_dir']?.toString(),
        );
      }
    }
    return UserActionResult(
      ok: doc['ok'] == true,
      action: action,
      error: doc['error']?.toString() ??
          (doc['ok'] == true ? null : 'no result for $user'),
    );
  }

  // ---------------------------------------------------------------------------
  // Bundles
  // ---------------------------------------------------------------------------

  /// Maps a bundle file to its protocol and whether its content is a QR
  /// payload. Returns `null` for files the app does not surface (images,
  /// HTML guide, zips).
  static ({String protocol, bool qr})? classifyBundleFile(String fileName) {
    final f = fileName.toLowerCase();
    if (f.endsWith('.png') || f.endsWith('.html') || f.endsWith('.zip')) {
      return null;
    }
    if (f == 'reality.txt') return (protocol: 'reality', qr: true);
    if (f == 'trojan.txt') return (protocol: 'trojan', qr: true);
    if (f == 'hysteria2.txt') return (protocol: 'hysteria2', qr: true);
    if (f == 'shadowsocks.txt') return (protocol: 'shadowsocks', qr: true);
    if (f == 'xhttp-vless.txt') return (protocol: 'xhttp', qr: true);
    if (f == 'telegram-proxy-link.txt') return (protocol: 'telegram', qr: true);
    if (f == 'subscription.txt') return (protocol: 'subscription', qr: true);
    if (f.endsWith('-wgws.conf')) {
      return (protocol: 'wireguard-wstunnel', qr: true);
    }
    if (f.endsWith('-wg.conf') || f == 'wireguard.conf') {
      return (protocol: 'wireguard', qr: true);
    }
    if (f.endsWith('-awg.conf') || f == 'amneziawg.conf') {
      return (protocol: 'amneziawg', qr: true);
    }
    if (f.startsWith('trusttunnel.')) return (protocol: 'trusttunnel', qr: false);
    if (f.startsWith('xdns')) return (protocol: 'xdns', qr: false);
    if (f.startsWith('dnstt')) return (protocol: 'dnstt', qr: false);
    if (f.startsWith('shadowsocks')) return (protocol: 'shadowsocks', qr: false);
    if (f.startsWith('amneziawg')) return (protocol: 'amneziawg', qr: false);
    return (protocol: f.split('.').first, qr: false);
  }

  static BundleEntry? bundleEntry(String fileName, String content) {
    final c = classifyBundleFile(fileName);
    if (c == null) return null;
    final trimmed = content.trim();
    return BundleEntry(
      protocol: c.protocol,
      fileName: fileName,
      content: content,
      qrPayload: c.qr && trimmed.isNotEmpty ? trimmed : null,
    );
  }

  /// Sort order for display: phone-friendly links first.
  static const protocolOrder = [
    'subscription',
    'reality',
    'hysteria2',
    'trojan',
    'shadowsocks',
    'xhttp',
    'wireguard',
    'amneziawg',
    'wireguard-wstunnel',
    'telegram',
    'trusttunnel',
    'xdns',
    'dnstt',
  ];

  static int compareEntries(BundleEntry a, BundleEntry b) {
    int rank(String p) {
      final i = protocolOrder.indexOf(p);
      return i < 0 ? protocolOrder.length : i;
    }

    final r = rank(a.protocol).compareTo(rank(b.protocol));
    return r != 0 ? r : a.fileName.compareTo(b.fileName);
  }

  // ---------------------------------------------------------------------------
  // moav test --json
  // ---------------------------------------------------------------------------

  /// `moav test --json` prints Docker build chatter before the JSON document,
  /// so this finds the last top-level `{ … }` that decodes.
  static Map<String, Object?>? extractTrailingJson(String raw) {
    final text = SshConnection.stripAnsi(raw);
    var end = text.lastIndexOf('}');
    while (end >= 0) {
      var start = text.lastIndexOf(RegExp(r'^\{', multiLine: true), end);
      while (start >= 0) {
        try {
          final v = jsonDecode(text.substring(start, end + 1));
          if (v is Map<String, Object?>) return v;
          if (v is Map) return v.cast<String, Object?>();
        } on FormatException {
          // keep widening
        }
        start = start == 0
            ? -1
            : text.lastIndexOf(RegExp(r'^\{', multiLine: true), start - 1);
      }
      end = text.lastIndexOf('}', end - 1);
      if (end < 0) break;
    }
    return null;
  }

  static CheckResult checkResultFrom(String? s) => switch (s?.toLowerCase()) {
        'pass' || 'ok' || 'success' => CheckResult.pass,
        'warn' || 'warning' => CheckResult.warn,
        'fail' || 'error' || 'failed' => CheckResult.fail,
        _ => CheckResult.skip,
      };

  static TestMatrix parseTest(String user, String raw, {DateTime? now}) {
    final json = extractTrailingJson(raw);
    if (json == null) {
      throw FormatException(
        'moav test did not return JSON: ${_tail(SshConnection.stripAnsi(raw))}',
      );
    }
    final tests = json['tests'];
    final results = <ProtocolTest>[];
    if (tests is Map) {
      for (final e in tests.entries) {
        final v = e.value;
        if (v is! Map) continue;
        results.add(ProtocolTest(
          protocol: e.key.toString(),
          result: checkResultFrom(v['status']?.toString()),
          detail: v['detail']?.toString(),
        ));
      }
    }
    final overall = json['overall_status'];
    return TestMatrix(
      user: user,
      results: results,
      ranAt: now ?? DateTime.now(),
      overall: overall == null ? null : checkResultFrom(overall.toString()),
    );
  }

  // ---------------------------------------------------------------------------
  // moav doctor
  // ---------------------------------------------------------------------------

  /// Descriptions from upstream `DOCTOR_CHECKS`; the JSON document carries
  /// only ids, and the UI shows the first detail line as the description.
  static const doctorDescriptions = <String, String>{
    'docker': 'Check Docker and prerequisites',
    'memory': 'Check available RAM',
    'disk': 'Check available disk space',
    'logs': 'Check container log file sizes',
    'dns': 'Check DNS records for enabled protocols',
    'services': 'Check running services vs enabled config',
    'config': 'Check config files and keys from bootstrap',
    'ports': 'Check required ports are available',
    'conflicts': 'Check for conflicting services',
    'reality': 'Check Reality fallback targets resolve and are reachable',
    'net': 'Check BBR/sysctl tuning, packet drops, PMTU, CGNAT and MTU',
    'host': 'Check CPU load, swap pressure and zombie processes',
    'peers': 'Check for duplicate WireGuard/AmneziaWG peer addresses',
    'env': 'Compare .env with .env.example for missing vars',
    'updates': 'Check for MoaV updates',
  };

  /// `moav doctor --json`: `[{id, status: pass|warn|fail, detail}]` where
  /// `detail` joins the check's lines with `; `. Returns `null` if not JSON.
  static DoctorReport? parseDoctorJson(String raw, {DateTime? now}) {
    final doc = decodeJsonDocument(raw);
    if (doc is! List) return null;
    final checks = <DoctorCheck>[];
    for (final e in doc) {
      final m = _asMap(e);
      final id = m?['id']?.toString();
      if (m == null || id == null || id.isEmpty) continue;
      final detail = m['detail']?.toString() ?? '';
      checks.add(DoctorCheck(
        name: id,
        result: checkResultFrom(m['status']?.toString()),
        detail: [
          doctorDescriptions[id] ?? id,
          ...detail.split('; ').where((l) => l.isNotEmpty),
        ].join('\n'),
      ));
    }
    return DoctorReport(checks: checks, collectedAt: now ?? DateTime.now());
  }

  static final _doctorHeaderRe = RegExp(r'^([a-z][a-z0-9_-]*) - (.+)$');

  /// Groups `moav doctor` output by check (`name - description` headers).
  /// A check fails if any of its lines is marked ✗, warns on `!`/`○`, else
  /// passes. The per-check detail keeps the marked lines only.
  static DoctorReport parseDoctor(String raw, {DateTime? now}) {
    final text = SshConnection.stripAnsi(raw);
    final checks = <DoctorCheck>[];
    String? name;
    String? desc;
    var lines = <String>[];
    var result = CheckResult.pass;

    void flush() {
      final n = name;
      if (n == null) return;
      checks.add(DoctorCheck(
        name: n,
        result: result,
        detail: [desc ?? '', ...lines].join('\n'),
      ));
    }

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.contains('Doctor Summary')) break;
      final hm = _doctorHeaderRe.firstMatch(line);
      if (hm != null) {
        flush();
        name = hm.group(1);
        desc = hm.group(2);
        lines = [];
        result = CheckResult.pass;
        continue;
      }
      if (name == null) continue;
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('✗')) {
        result = CheckResult.fail;
      } else if ((t.startsWith('!') || t.startsWith('○')) &&
          result != CheckResult.fail) {
        result = CheckResult.warn;
      }
      lines.add(t);
    }
    flush();
    return DoctorReport(checks: checks, collectedAt: now ?? DateTime.now());
  }

  // ---------------------------------------------------------------------------
  // moav status
  // ---------------------------------------------------------------------------

  /// `moav status --json`: `{version, admin_url, grafana_url, admin_port,
  /// grafana_port, default_profiles, services: [{name, state, uptime, ports}]}`.
  static ServiceStatusReport? parseStatusJson(String raw, {DateTime? now}) {
    final doc = _asMap(decodeJsonDocument(raw));
    final list = doc?['services'];
    if (doc == null || list is! List) return null;
    final services = <ServiceStatus>[];
    for (final e in list) {
      final m = _asMap(e);
      final name = m?['name']?.toString();
      if (m == null || name == null || name.isEmpty) continue;
      final uptime = m['uptime']?.toString() ?? '';
      services.add(ServiceStatus(
        name: name,
        state: serviceStateFrom(m['state']?.toString()),
        uptime: uptime.isEmpty ? null : uptime,
        ports: _stringList(m['ports']),
      ));
    }
    Uri? uri(Object? v) => v is String && v.isNotEmpty ? Uri.tryParse(v) : null;
    return ServiceStatusReport(
      services: services,
      collectedAt: now ?? DateTime.now(),
      version: doc['version']?.toString(),
      adminUrl: uri(doc['admin_url']),
      grafanaUrl: uri(doc['grafana_url']),
      defaultProfiles: _stringList(doc['default_profiles']),
    );
  }

  /// JSON `state` is `running|unhealthy|starting|never` or a raw compose
  /// state; the text table only ever shows the words matched here.
  static ServiceState serviceStateFrom(String? s) {
    final t = (s ?? '').toLowerCase();
    if (t.contains('unhealthy')) return ServiceState.unhealthy;
    if (t.contains('starting')) return ServiceState.starting;
    if (t.contains('running')) return ServiceState.running;
    if (t.contains('exited')) return ServiceState.exited;
    if (t.contains('never')) return ServiceState.never;
    if (t.contains('stopped') || t.contains('created')) {
      return ServiceState.stopped;
    }
    return ServiceState.unknown;
  }

  /// Prefers the JSON document, else parses the 2.2.x box-drawn table.
  static ({ServiceStatusReport report, CliFormat format}) parseStatusAny(
    String raw, {
    DateTime? now,
  }) {
    final json = parseStatusJson(raw, now: now);
    if (json != null) return (report: json, format: CliFormat.json);
    return (report: parseStatus(raw, now: now), format: CliFormat.text);
  }

  static final _statusRowRe = RegExp(r'^\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*$');
  static final _versionRe = RegExp(r'MoaV\s+v?([0-9][^\s)]*)');
  static final _urlLineRe = RegExp(r'^\s*(Admin Dashboard|Grafana \(CDN\)|Grafana):\s*(\S+)');

  static ServiceStatusReport parseStatus(String raw, {DateTime? now}) {
    final text = SshConnection.stripAnsi(raw);
    final services = <ServiceStatus>[];
    Uri? admin;
    Uri? grafana;
    Uri? grafanaCdn;
    String? version;
    var profiles = const <String>[];
    for (final line in text.split('\n')) {
      version ??= _versionRe.firstMatch(line)?.group(1);
      final rm = _statusRowRe.firstMatch(line);
      if (rm != null) {
        final name = rm.group(1)!;
        if (name == 'Service') continue; // header row
        final state = serviceStateFrom(rm.group(2));
        String? dash(String s) => s == '-' ? null : s;
        final ports = rm.group(5)!;
        services.add(ServiceStatus(
          name: name,
          state: state,
          lastRun: dash(rm.group(3)!),
          uptime: dash(rm.group(4)!),
          ports: ports == '-'
              ? const []
              : ports.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList(),
        ));
        continue;
      }
      final um = _urlLineRe.firstMatch(line);
      if (um != null) {
        final uri = Uri.tryParse(um.group(2)!);
        switch (um.group(1)) {
          case 'Admin Dashboard':
            admin = uri;
          case 'Grafana':
            grafana = uri;
          case 'Grafana (CDN)':
            grafanaCdn = uri;
        }
        continue;
      }
      final pm = RegExp(r'Default profiles:\s*(.+)$').firstMatch(line);
      if (pm != null) {
        profiles = pm.group(1)!.trim().split(RegExp(r'\s+'));
      }
    }
    return ServiceStatusReport(
      services: services,
      collectedAt: now ?? DateTime.now(),
      version: version,
      adminUrl: admin,
      grafanaUrl: grafana,
      grafanaCdnUrl: grafanaCdn,
      defaultProfiles: profiles,
    );
  }

  // ---------------------------------------------------------------------------
  // monitoring snippet
  // ---------------------------------------------------------------------------

  static Monitoring parseMonitoring(String raw, {DateTime? now}) {
    final text = SshConnection.stripAnsi(raw);
    String section(String marker, String nextMarkerPattern) {
      final i = text.indexOf(marker);
      if (i < 0) return '';
      final rest = text.substring(i + marker.length);
      final m = RegExp(nextMarkerPattern, multiLine: true).firstMatch(rest);
      return m == null ? rest : rest.substring(0, m.start);
    }

    Uri? grafana;
    Uri? grafanaCdn;
    Uri? admin;
    for (final line in section('__URLS__', r'^__HEALTH__').split('\n')) {
      final i = line.indexOf('=');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final uri = Uri.tryParse(line.substring(i + 1).trim());
      if (uri == null || !uri.hasScheme) continue;
      switch (key) {
        case 'grafana':
          grafana = uri;
        case 'grafana_cdn':
          grafanaCdn = uri;
        case 'admin':
          admin = uri;
      }
    }

    bool? healthy;
    String? version;
    final health = section('__HEALTH__', r'^__PROM__').trim();
    if (health.isNotEmpty) {
      try {
        final j = jsonDecode(health);
        if (j is Map) {
          healthy = j['database'] == 'ok';
          version = j['version']?.toString();
        } else {
          healthy = false;
        }
      } on FormatException {
        healthy = false;
      }
    }

    final metrics = <Metric>[];
    final prom = section('__PROM__', r'^__END__');
    final parts = prom.split('__Q__ ');
    for (final part in parts) {
      final nl = part.indexOf('\n');
      if (nl < 0) continue;
      final name = part.substring(0, nl).trim();
      final body = part.substring(nl + 1).trim();
      if (name.isEmpty || body.isEmpty) continue;
      try {
        final j = jsonDecode(body);
        final result = (j as Map)['data']?['result'];
        if (result is List && result.isNotEmpty) {
          final value = (result.first as Map)['value'];
          if (value is List && value.length == 2) {
            final m = formatMetric(name, value[1].toString());
            if (m != null) metrics.add(m);
          }
        }
      } on Object {
        // Skip metrics that did not decode; the rest still render.
      }
    }

    return Monitoring(
      grafanaUrl: grafana,
      grafanaCdnUrl: grafanaCdn,
      adminUrl: admin,
      grafanaHealthy: healthy,
      grafanaVersion: version,
      metrics: metrics,
      collectedAt: now ?? DateTime.now(),
    );
  }

  /// Turns a raw Prometheus sample into a display metric.
  static Metric? formatMetric(String key, String rawValue) {
    final v = double.tryParse(rawValue);
    if (v == null) return null;
    switch (key) {
      case 'targets_up':
        return Metric(name: 'Exporters up', value: v.toStringAsFixed(0));
      case 'load1':
        return Metric(name: 'Load (1m)', value: v.toStringAsFixed(2));
      case 'mem_available_bytes':
        return Metric(name: 'RAM available', value: _bytes(v));
      case 'mem_total_bytes':
        return Metric(name: 'RAM total', value: _bytes(v));
      case 'rx_bytes_per_s':
        return Metric(name: 'Inbound', value: _bytes(v), unit: '/s');
      case 'tx_bytes_per_s':
        return Metric(name: 'Outbound', value: _bytes(v), unit: '/s');
      case 'disk_free_bytes':
        return Metric(name: 'Disk free', value: _bytes(v));
    }
    return Metric(name: key, value: rawValue);
  }

  static String _bytes(double b) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  // ---------------------------------------------------------------------------
  // host info snippet (TODO(#8): text path)
  // ---------------------------------------------------------------------------

  static const hostMarkers = [
    '__LOAD__',
    '__NPROC__',
    '__CPU1__',
    '__CPU2__',
    '__MEM__',
    '__DISK__',
    '__UPTIME__',
    '__VERSION__',
    '__GIT__',
    '__END__',
  ];

  /// Splits marker-delimited output into `marker -> body` (markers sit alone
  /// on a line). Text before the first marker is dropped.
  static Map<String, String> sections(String raw, List<String> markers) {
    final out = <String, String>{};
    String? current;
    final buf = StringBuffer();
    for (final line in SshConnection.stripAnsi(raw).split('\n')) {
      final t = line.trim();
      if (markers.contains(t)) {
        if (current != null) out[current] = buf.toString();
        current = t;
        buf.clear();
        continue;
      }
      if (current != null) buf.writeln(line);
    }
    if (current != null) out[current] = buf.toString();
    return out;
  }

  static ServerInfo parseHostInfo(String raw, {DateTime? now}) {
    final s = sections(raw, hostMarkers);
    return ServerInfo(
      host: parseHostMetrics(s),
      version: parseVersionInfo(
        s['__VERSION__'] ?? '',
        git: s['__GIT__'] ?? '',
      ),
      collectedAt: now ?? DateTime.now(),
    );
  }

  static HostMetrics parseHostMetrics(Map<String, String> s) {
    final load = (s['__LOAD__'] ?? '').trim().split(RegExp(r'\s+'));
    double? loadAt(int i) => load.length > i ? double.tryParse(load[i]) : null;

    final mem = <String, int>{};
    for (final line in (s['__MEM__'] ?? '').split('\n')) {
      final m = RegExp(r'^(\w+):\s+(\d+)\s*kB').firstMatch(line.trim());
      if (m != null) mem[m.group(1)!] = int.parse(m.group(2)!) * 1024;
    }

    int? diskTotal;
    int? diskAvail;
    final disk = (s['__DISK__'] ?? '').trim().split(RegExp(r'\s+'));
    if (disk.length >= 4) {
      final total = int.tryParse(disk[1]);
      final avail = int.tryParse(disk[3]);
      if (total != null) diskTotal = total * 1024;
      if (avail != null) diskAvail = avail * 1024;
    }

    final up = double.tryParse(
      (s['__UPTIME__'] ?? '').trim().split(RegExp(r'\s+')).first,
    );

    return HostMetrics(
      cpuCount: int.tryParse((s['__NPROC__'] ?? '').trim()),
      cpuUsage: cpuUsageBetween(s['__CPU1__'] ?? '', s['__CPU2__'] ?? ''),
      load1: loadAt(0),
      load5: loadAt(1),
      load15: loadAt(2),
      memTotalBytes: mem['MemTotal'],
      memAvailableBytes: mem['MemAvailable'],
      swapTotalBytes: mem['SwapTotal'],
      swapFreeBytes: mem['SwapFree'],
      diskTotalBytes: diskTotal,
      diskAvailableBytes: diskAvail,
      uptime: up == null ? null : Duration(seconds: up.round()),
    );
  }

  /// Busy fraction between two `cpu ...` lines of `/proc/stat`
  /// (user nice system idle iowait irq softirq steal).
  static double? cpuUsageBetween(String first, String second) {
    List<int>? fields(String line) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 5 || parts.first != 'cpu') return null;
      final v = parts.skip(1).map(int.tryParse).toList();
      return v.any((x) => x == null) ? null : v.cast<int>();
    }

    final a = fields(first);
    final b = fields(second);
    if (a == null || b == null) return null;
    int sum(List<int> v) => v.fold(0, (x, y) => x + y);
    int idle(List<int> v) => v[3] + (v.length > 4 ? v[4] : 0);
    final total = sum(b) - sum(a);
    if (total <= 0) return null;
    final busy = total - (idle(b) - idle(a));
    return (busy / total).clamp(0, 1).toDouble();
  }

  static final _componentRowRe =
      RegExp(r'^\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*(.+?)\s*│\s*$');

  /// `moav --version`: the `MoaV vX.Y.Z` banner plus the box-drawn
  /// component table (`│ name │ version │ source │`).
  static VersionInfo parseVersionInfo(String raw, {String git = ''}) {
    final text = SshConnection.stripAnsi(raw);
    String? version;
    final components = <ComponentVersion>[];
    for (final line in text.split('\n')) {
      version ??= _versionRe.firstMatch(line)?.group(1);
      final m = _componentRowRe.firstMatch(line);
      if (m == null) continue;
      final name = m.group(1)!;
      if (name == 'Component') continue;
      final source = m.group(3)!;
      components.add(ComponentVersion(
        name: name,
        version: m.group(2)!,
        source: source.isEmpty ? null : source,
      ));
    }
    final gitLines = SshConnection.stripAnsi(git)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return VersionInfo(
      moavVersion: version,
      branch: gitLines.isNotEmpty ? gitLines[0] : null,
      commit: gitLines.length > 1 ? gitLines[1] : null,
      components: components,
    );
  }

  // ---------------------------------------------------------------------------
  // moav doctor updates
  // ---------------------------------------------------------------------------

  static final _currentVersionRe =
      RegExp(r'Current version:\s*v?([0-9][^\s;]*)');
  static final _updateAvailableRe =
      RegExp(r'Update available:\s*v?([0-9][^\s;(]*)');
  static final _upToDateRe = RegExp(r'Up to date\s*\(v?([^)]+)\)');
  static final _aheadRe = RegExp(r'ahead of latest release\s*v?([^)]+)\)');

  /// Reads the `updates` check from `doctor updates --json` or the 2.2.x
  /// text; both carry the same sentences. Returns `null` when the output
  /// mentions no version at all (the check did not run).
  static UpdateCheck? parseUpdateCheck(String raw, {DateTime? now}) {
    var text = SshConnection.stripAnsi(raw);
    final doc = decodeJsonDocument(raw);
    if (doc is List) {
      text = [
        for (final e in doc)
          if (_asMap(e)?['id']?.toString() == 'updates')
            _asMap(e)!['detail']?.toString() ?? '',
      ].join('; ');
    }
    final current = _currentVersionRe.firstMatch(text)?.group(1);
    final available = _updateAvailableRe.firstMatch(text)?.group(1);
    final upToDate = _upToDateRe.firstMatch(text)?.group(1);
    final ahead = _aheadRe.firstMatch(text)?.group(1);
    if (current == null && available == null && upToDate == null) return null;
    final at = now ?? DateTime.now();
    if (available != null) {
      return UpdateCheck(
        updateAvailable: true,
        checkedAt: at,
        currentVersion: current,
        latestVersion: available,
        message: 'Update available: v$available',
      );
    }
    if (upToDate != null) {
      return UpdateCheck(
        updateAvailable: false,
        checkedAt: at,
        currentVersion: current ?? upToDate,
        latestVersion: upToDate,
        message: 'Up to date (v$upToDate)',
      );
    }
    if (ahead != null) {
      return UpdateCheck(
        updateAvailable: false,
        checkedAt: at,
        currentVersion: current,
        latestVersion: ahead,
        message: 'Running v$current, ahead of the latest release v$ahead',
      );
    }
    return UpdateCheck(
      updateAvailable: false,
      checkedAt: at,
      currentVersion: current,
      message: text.contains('Could not check')
          ? 'Could not check: the server cannot reach GitHub.'
          : 'Could not read the update check.',
    );
  }

  static String _tail(String s) {
    final t = s.trim();
    return t.length > 300 ? '…${t.substring(t.length - 300)}' : t;
  }
}
