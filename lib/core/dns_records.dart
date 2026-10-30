import 'package:clock/clock.dart';

/// One DNS record a domain-mode install needs before `install.sh` can ask
/// Let's Encrypt for a certificate.
class DnsRecord {
  const DnsRecord({
    required this.name,
    required this.type,
    required this.value,
    required this.comment,
    this.optional = false,
  });

  /// Fully qualified owner name without the trailing dot, e.g. `t.example.org`.
  final String name;

  /// `A` or `NS`.
  final String type;

  /// The IPv4 for an `A` record, the nameserver host for an `NS` record.
  final String value;

  /// Upstream's one-line description of the record.
  final String comment;

  /// Needed only by an opt-in service (XDNS); a miss is a warning, not a fail.
  final bool optional;

  /// The BIND line as `generate_dns_zone_file` writes it (TTL 1, tabs).
  String get zoneLine => '$name.\t1\tIN\t$type\t'
      '${type == 'NS' ? '$value.' : value}';

  @override
  String toString() => '$type $name -> $value';
}

/// The records MoaV expects for a domain and the `dns-records.txt` text
/// upstream's `lib/dns.sh::generate_dns_zone_file` writes for them.
class DnsRecords {
  DnsRecords._();

  static const fileName = 'dns-records.txt';

  /// Upstream's default DNS-tunnel subdomains, in zone-file order.
  static const tunnelSubdomains = ['t', 's', 'm', 'x'];

  /// Hostnames the installer and the DNS tools accept: labels of letters,
  /// digits and hyphens joined by dots, at least one dot.
  static final _hostname = RegExp(
    r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$',
  );

  /// Lowercases, trims and drops a trailing dot, a scheme and a path, so
  /// `HTTPS://VPN.Example.org/` becomes `vpn.example.org`.
  static String normalizeDomain(String input) {
    var d = input.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    final slash = d.indexOf('/');
    if (slash >= 0) d = d.substring(0, slash);
    while (d.endsWith('.')) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  static bool isValidDomain(String domain) => _hostname.hasMatch(domain);

  /// The nameserver host for the DNS tunnels, `dns.<domain>`.
  static String nameserver(String domain) => 'dns.$domain';

  /// The six records, main domain first, then the nameserver and the four
  /// tunnel delegations.
  static List<DnsRecord> forDomain(String domain, String serverIp) {
    final ns = nameserver(domain);
    return [
      DnsRecord(
        name: domain,
        type: 'A',
        value: serverIp,
        comment: 'Main domain: points to your server (DNS only, NOT proxied)',
      ),
      DnsRecord(
        name: ns,
        type: 'A',
        value: serverIp,
        comment: 'DNS tunnel nameserver: required for NS delegation '
            '(DNS only, NOT proxied)',
      ),
      DnsRecord(
        name: 't.$domain',
        type: 'NS',
        value: ns,
        comment: 'dnstt KCP+Noise DNS tunnel',
      ),
      DnsRecord(
        name: 's.$domain',
        type: 'NS',
        value: ns,
        comment: 'Slipstream QUIC-over-DNS tunnel',
      ),
      DnsRecord(
        name: 'm.$domain',
        type: 'NS',
        value: ns,
        comment: 'MasterDNS ARQ DNS tunnel (MahsaNG v16 native)',
      ),
      DnsRecord(
        name: 'x.$domain',
        type: 'NS',
        value: ns,
        comment: 'XDNS mKCP DNS tunnel: opt-in, shares port 53 via dns-router',
        optional: true,
      ),
    ];
  }

  /// `outputs/dns-records.txt` as upstream generates it: a BIND zone
  /// fragment Cloudflare's "Import and Upload" accepts. [now] defaults to
  /// the current UTC time.
  static String zoneFile(String domain, String serverIp, {DateTime? now}) {
    final at = (now ?? clock.now()).toUtc();
    final stamp = '${at.year.toString().padLeft(4, '0')}-'
        '${_two(at.month)}-${_two(at.day)} '
        '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)} UTC';
    final records = forDomain(domain, serverIp);
    final buf = StringBuffer()
      ..writeln(';;')
      ..writeln(';; MoaV DNS Records for $domain')
      ..writeln(';; Generated: $stamp')
      ..writeln(';;')
      ..writeln(';; Import into Cloudflare: DNS > Records > Import and Upload')
      ..writeln(';; Or manually create these records at your DNS provider.')
      ..writeln(';;')
      ..writeln()
      ..writeln(';; ${records[0].comment}')
      ..writeln(records[0].zoneLine)
      ..writeln()
      ..writeln(';; ${records[1].comment}')
      ..writeln(records[1].zoneLine)
      ..writeln()
      ..writeln(';; DNS tunnel NS delegations')
      ..writeln(';; All four DNS tunnels share port 53 via dns-router '
          '(dnstt/Slipstream/MasterDNS on by default; XDNS opt-in)');
    for (final r in records.skip(2)) {
      buf
        ..writeln(';; ${r.comment}')
        ..writeln(r.zoneLine);
    }
    return buf.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// IPv4 helpers for picking the server's public address out of command
/// output such as `curl ifconfig.me` or `hostname -I`.
class PublicIp {
  PublicIp._();

  static final _v4 = RegExp(r'(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])');

  /// True for a well-formed dotted-quad IPv4 literal.
  static bool isLiteralV4(String s) {
    final m = _v4.firstMatch(s.trim());
    return m != null && m.group(0) == s.trim() && _octets(m) != null;
  }

  /// True when [ip] is routable on the public internet: not loopback,
  /// link-local, RFC 1918, CGNAT, multicast or reserved.
  static bool isPublicV4(String ip) {
    final m = _v4.firstMatch(ip);
    if (m == null || m.group(0) != ip) return false;
    final o = _octets(m);
    if (o == null) return false;
    final (a, b, _, _) = (o[0], o[1], o[2], o[3]);
    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a == 100 && b >= 64 && b <= 127) return false;
    return true;
  }

  /// The first public IPv4 found anywhere in [text], or `null`.
  static String? firstPublicV4(String text) {
    for (final m in _v4.allMatches(text)) {
      final ip = m.group(0)!;
      if (isPublicV4(ip)) return ip;
    }
    return null;
  }

  static List<int>? _octets(RegExpMatch m) {
    final out = <int>[];
    for (var i = 1; i <= 4; i++) {
      final v = int.parse(m.group(i)!);
      if (v > 255) return null;
      out.add(v);
    }
    return out;
  }
}
