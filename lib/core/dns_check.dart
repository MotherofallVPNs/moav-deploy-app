import 'dns_records.dart';
import 'moav_controller.dart';

/// Outcome of one expected record in a [DnsCheckReport].
class DnsRecordCheck {
  const DnsRecordCheck({
    required this.record,
    required this.result,
    required this.detail,
    this.found = const [],
  });

  final DnsRecord record;

  /// `pass` when the live answer matches, `warn` for an optional miss,
  /// `fail` for a required miss, `skip` when nothing could be queried.
  final CheckResult result;

  /// One short line for the sheet, e.g. `points to 203.0.113.9`.
  final String detail;

  /// What DNS actually answered (IPs or nameservers), normalized.
  final List<String> found;
}

/// Result of `MoavController.checkDns`.
class DnsCheckReport {
  const DnsCheckReport({
    required this.checks,
    required this.checkedAt,
    this.tool,
  });

  final List<DnsRecordCheck> checks;
  final DateTime checkedAt;

  /// Which resolver tool answered (`dig`, `host`, `nslookup`, `getent`),
  /// `null` when the server had none.
  final String? tool;

  /// No lookup could run at all (no tool, or every record was skipped).
  bool get unavailable => checks.every((c) => c.result == CheckResult.skip);

  int get failed => checks.where((c) => c.result == CheckResult.fail).length;
  int get warned => checks.where((c) => c.result == CheckResult.warn).length;
  int get passed => checks.where((c) => c.result == CheckResult.pass).length;

  /// Every required record resolves as expected.
  bool get ready => !unavailable && failed == 0;

  CheckResult get overall {
    if (unavailable) return CheckResult.skip;
    if (failed > 0) return CheckResult.fail;
    if (warned > 0) return CheckResult.warn;
    return CheckResult.pass;
  }

  /// One sentence for the sheet's result banner.
  String get summary {
    if (unavailable) {
      return 'Could not check: the server has no dig, host or nslookup.';
    }
    if (failed == 0 && warned == 0) {
      return 'All ${checks.length} records resolve as expected.';
    }
    if (failed == 0) {
      return 'Required records are in place; $warned optional record '
          '${warned == 1 ? 'is' : 'are'} not set up.';
    }
    return '$failed of ${checks.length} records need attention. '
        'New records can take a few minutes to propagate.';
  }
}

/// The server-side lookup behind `MoavController.checkDns` and the parser for
/// its output.
///
/// The lookups mirror upstream `lib/doctor.sh` (`doctor_lookup_a_records`,
/// `doctor_lookup_ns_records`): `dig` first, then `getent`/`host`/`nslookup`,
/// so a fresh box without `dnsutils` still answers. NS delegations of a
/// subdomain are read from the AUTHORITY section at the parent zone's own
/// nameserver, because a recursive resolver forwards the question to the
/// tunnel server itself, which may not answer NS queries.
class DnsCheck {
  DnsCheck._();

  /// Detects the server's public IPv4: `curl` against the same services
  /// upstream `bootstrap.sh` uses, then `hostname -I` for a box with no
  /// outbound HTTP. The caller picks the first public address out of it.
  static const publicIpCommand =
      'curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null '
      '|| curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null; echo; '
      'hostname -I 2>/dev/null || ip -4 -o addr 2>/dev/null; true';

  static const timeout = Duration(seconds: 45);

  /// Prints one `TOOL <name>` line, then `A <host> <ip,ip>` for the domain
  /// and its nameserver and `NS <host> <ns,ns>` for each tunnel subdomain.
  /// Throws for a domain that is not a plain hostname (nothing is quoted).
  static String command(String domain) {
    if (!DnsRecords.isValidDomain(domain)) {
      throw ArgumentError.value(domain, 'domain', 'Not a valid hostname');
    }
    final subs = DnsRecords.tunnelSubdomains.join(' ');
    return _script.replaceAll('__DOMAIN__', domain).replaceAll('__SUBS__', subs);
  }

  static const _script = r'''
md_tool() {
  for t in dig host nslookup getent; do
    command -v "$t" >/dev/null 2>&1 && { echo "$t"; return 0; }
  done
  return 127
}
md_a() {
  if command -v dig >/dev/null 2>&1; then
    dig +short A "$1" 2>/dev/null | awk '/^[0-9]+\./ { print $1 }'
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$1" 2>/dev/null | awk '{ print $1 }' | sort -u
  elif command -v host >/dev/null 2>&1; then
    host -t A "$1" 2>/dev/null | awk '/ has address / { print $NF }'
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$1" 2>/dev/null | awk '/^Name: / { n=1; next } n && /^Address: / { gsub(/#.*/, "", $2); print $2 }' | awk '/^[0-9]+\./'
  else
    return 127
  fi
}
md_ns() {
  if command -v dig >/dev/null 2>&1; then
    auth=$(dig +short NS "$2" 2>/dev/null | head -1)
    r=""
    [ -n "$auth" ] && r=$(dig NS "$1" "@$auth" 2>/dev/null | awk '/^;; AUTHORITY SECTION:/,/^$/ { if ($4 == "NS") print $5 }')
    [ -z "$r" ] && r=$(dig +short NS "$1" 2>/dev/null)
    printf '%s\n' "$r"
  elif command -v host >/dev/null 2>&1; then
    host -t NS "$1" 2>/dev/null | awk '/ name server / { print $NF }'
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup -type=NS "$1" 2>/dev/null | awk -F' = ' '/nameserver = / { print $2 }'
  else
    return 127
  fi
}
D='__DOMAIN__'
tool=$(md_tool) || { echo "TOOL none"; exit 0; }
echo "TOOL $tool"
for h in "$D" "dns.$D"; do
  v=$(md_a "$h" 2>/dev/null | tr '\n' ',')
  echo "A $h $v"
done
for s in __SUBS__; do
  v=$(md_ns "$s.$D" "$D" 2>/dev/null | tr '\n' ',')
  echo "NS $s.$D $v"
done
''';

  /// Turns the command's output into per-record results for the records
  /// [DnsRecords.forDomain] expects.
  static DnsCheckReport parse(
    String output, {
    required String domain,
    required String serverIp,
    DateTime? now,
  }) {
    final expected = DnsRecords.forDomain(domain, serverIp);
    final at = now ?? DateTime.now();
    String? tool;
    final answers = <String, List<String>>{};
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('TOOL ')) {
        final t = line.substring(5).trim();
        tool = t == 'none' ? null : t;
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2 || (parts[0] != 'A' && parts[0] != 'NS')) continue;
      final key = '${parts[0]} ${_norm(parts[1])}';
      final values = parts.length > 2
          ? parts[2]
              .split(',')
              .map(_norm)
              .where((v) => v.isNotEmpty)
              .toSet()
              .toList()
          : const <String>[];
      answers[key] = values;
    }

    final checks = <DnsRecordCheck>[];
    for (final r in expected) {
      final found = answers['${r.type} ${_norm(r.name)}'];
      final want = _norm(r.value);
      final miss = r.optional ? CheckResult.warn : CheckResult.fail;
      if (tool == null || found == null) {
        checks.add(DnsRecordCheck(
          record: r,
          result: CheckResult.skip,
          detail: tool == null ? 'no DNS tool on the server' : 'not checked',
        ));
      } else if (found.contains(want)) {
        checks.add(DnsRecordCheck(
          record: r,
          result: CheckResult.pass,
          detail: r.type == 'A' ? 'points to $want' : 'delegates to $want',
          found: found,
        ));
      } else if (found.isEmpty) {
        checks.add(DnsRecordCheck(
          record: r,
          result: miss,
          detail: r.type == 'A' ? 'does not resolve' : 'no NS delegation',
        ));
      } else {
        checks.add(DnsRecordCheck(
          record: r,
          result: miss,
          detail: '${r.type == 'A' ? 'points to' : 'delegates to'} '
              '${found.join(', ')}',
          found: found,
        ));
      }
    }
    return DnsCheckReport(checks: checks, checkedAt: at, tool: tool);
  }

  /// Lowercase without a trailing dot, so `DNS.Example.org.` equals
  /// `dns.example.org`.
  static String _norm(String s) {
    var v = s.trim().toLowerCase();
    while (v.endsWith('.')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}
