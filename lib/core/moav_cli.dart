import 'dart:convert';

import 'moav_controller.dart';
import 'ssh_connection.dart';

/// The exact `moav` CLI invocations the SSH controller runs, plus the parsers
/// that turn their output into models.
///
/// Verified against MoaV v2.2.2. Every text parser here is a stop-gap until
/// the CLI grows `--json` (tracked in docs/MOAV-CLI-GAPS.md); `moav test`
/// already has it.
class MoavCli {
  MoavCli._();

  static const root = '/opt/moav';
  static const bundlesDir = '$root/outputs/bundles';

  /// `cd` into the checkout and resolve the CLI even when `moav` is not on
  /// the non-login shell's PATH.
  static const prelude = 'cd $root 2>/dev/null; '
      'M="\$(command -v moav 2>/dev/null || echo $root/moav.sh)"; ';

  static const userList = '$prelude"\$M" user list 2>&1';
  static String userAdd(String name) =>
      '$prelude"\$M" user add ${SshConnection.shellQuote(name)} 2>&1';
  static String userRevoke(String name) =>
      '$prelude"\$M" user revoke ${SshConnection.shellQuote(name)} 2>&1';
  static String test(String name) =>
      '$prelude"\$M" test ${SshConnection.shellQuote(name)} --json 2>/dev/null';
  static const doctor = '$prelude"\$M" doctor 2>&1';
  static const status = '$prelude"\$M" status 2>&1';

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

  /// Emits marker-delimited sections: dashboard URLs derived exactly like
  /// `get_grafana_url` in `lib/common.sh`, the Grafana `/api/health` body, and
  /// one Prometheus instant query per headline metric (via `docker exec`, as
  /// Prometheus is not published on the host).
  static const monitoring = '''
cd $root 2>/dev/null || exit 0
ev() { grep -E "^\$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/[[:space:]]+#.*\$//; s/^"//; s/"\$//; s/^'"'"'//; s/'"'"'\$//' | tr -d '[:space:]'; }
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
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx moav-prometheus; then
  PP=\$(docker inspect -f '{{join .Args " "}}' moav-prometheus 2>/dev/null | grep -oE 'listen-address=[^ ]*:[0-9]+' | grep -oE '[0-9]+\$'); PP=\${PP:-9090}
  q() { echo "__Q__ \$1"; docker exec moav-prometheus wget -qO- -T 5 "http://127.0.0.1:\$PP/api/v1/query?query=\$2" 2>/dev/null; echo; }
  q targets_up 'count(up%3D%3D1)'
  q load1 'node_load1'
  q mem_available_bytes 'node_memory_MemAvailable_bytes'
  q mem_total_bytes 'node_memory_MemTotal_bytes'
  q rx_bytes_per_s 'sum(rate(node_network_receive_bytes_total%7Bdevice!~%22lo%7Cveth.*%7Cbr-.*%7Cdocker.*%22%7D%5B5m%5D))'
  q tx_bytes_per_s 'sum(rate(node_network_transmit_bytes_total%7Bdevice!~%22lo%7Cveth.*%7Cbr-.*%7Cdocker.*%22%7D%5B5m%5D))'
  q disk_free_bytes 'node_filesystem_avail_bytes%7Bmountpoint%3D%22/%22%7D'
fi
echo "__END__"
''';

  // ---------------------------------------------------------------------------
  // moav user list
  // ---------------------------------------------------------------------------

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
        final stateText = rm.group(2)!.toLowerCase();
        final state = stateText.contains('running')
            ? ServiceState.running
            : stateText.contains('exited')
                ? ServiceState.exited
                : stateText.contains('never')
                    ? ServiceState.never
                    : stateText.contains('stopped') || stateText.contains('created')
                        ? ServiceState.stopped
                        : ServiceState.unknown;
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

  static String _tail(String s) {
    final t = s.trim();
    return t.length > 300 ? '…${t.substring(t.length - 300)}' : t;
  }
}
