/// Normalises a pasted connect string (`ssh://root@host:22/`, `[::1]:22`,
/// stray whitespace) into the bare host the resolver understands.
class SshEndpoint {
  const SshEndpoint({required this.host, this.port, this.username});

  /// Bare hostname or IP literal, lower-cased, no brackets.
  final String host;

  /// Port found in the input, if any.
  final int? port;

  /// Username found in the input, if any.
  final String? username;

  static final _hostname = RegExp(
    r'^(?=.{1,253}$)[a-z0-9_]([a-z0-9_-]{0,62}[a-z0-9_])?'
    r'(\.[a-z0-9_]([a-z0-9_-]{0,62}[a-z0-9_])?)*\.?$',
  );
  static final _ipv6 = RegExp(r'^[0-9a-f:]+(%[a-z0-9]+)?$');
  static final _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);

  /// Parses [raw]. Returns null when no usable host remains.
  static SshEndpoint? tryParse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(_scheme, '');
    // Drop a trailing path such as the "/" a browser-style paste carries.
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);

    String? username;
    final at = s.lastIndexOf('@');
    if (at >= 0) {
      username = s.substring(0, at).trim();
      s = s.substring(at + 1);
      if (username.isEmpty) username = null;
    }

    int? port;
    String host;
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      if (close < 0) return null;
      host = s.substring(1, close);
      final rest = s.substring(close + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) return null;
        port = _port(rest.substring(1));
        if (port == null) return null;
      }
    } else {
      final colons = ':'.allMatches(s).length;
      if (colons == 1) {
        final i = s.indexOf(':');
        host = s.substring(0, i);
        port = _port(s.substring(i + 1));
        if (port == null) return null;
      } else {
        // Zero colons: plain host. Two or more: an unbracketed IPv6 literal.
        host = s;
      }
    }

    host = host.trim().toLowerCase();
    if (host.isEmpty || host.contains(RegExp(r'\s'))) return null;
    if (!_hostname.hasMatch(host) && !_ipv6.hasMatch(host)) return null;
    return SshEndpoint(host: host, port: port, username: username);
  }

  /// The cleaned host, or [raw] trimmed when unparseable (validation reports it).
  static String normalizeHost(String raw) => tryParse(raw)?.host ?? raw.trim();

  static int? _port(String s) {
    final p = int.tryParse(s.trim());
    return p == null || p < 1 || p > 65535 ? null : p;
  }

  @override
  String toString() =>
      '${username == null ? '' : '$username@'}$host${port == null ? '' : ':$port'}';
}
