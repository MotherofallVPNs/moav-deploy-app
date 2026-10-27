/// Scrubs secret material out of free text before it can reach a log line,
/// an error surface, a crash handler, or a bug report.
///
/// This is the last line of defence. Code paths are written so that secrets
/// never enter error strings in the first place; the redactor exists for the
/// cases nobody anticipated (a library exception that echoes its input, a
/// pasted config in a form error, an uncaught `toString()`).
///
/// It is deliberately over-eager: a redacted hostname is an annoyance, a
/// leaked private key or share link can get someone arrested.
class Redactor {
  Redactor._();

  static const keyMarker = '[redacted private key]';
  static const valueMarker = '[redacted]';

  /// Words that mark a `key=value` / `"key": "value"` / `key: value` pair as
  /// secret. Matched case-insensitively as a substring of the key name.
  static const secretKeyWords = <String>[
    'password',
    'passphrase',
    'passwd',
    'secret',
    'token',
    'private_key',
    'privatekey',
    'presharedkey',
    'preshared_key',
    'psk',
    'uuid',
    'api_key',
    'apikey',
    'auth_str',
    'short_id',
  ];

  /// URI schemes whose payload is a client credential (MoaV share links).
  static const linkSchemes = <String>[
    'vless',
    'vmess',
    'trojan',
    'ss',
    'ssr',
    'hysteria',
    'hysteria2',
    'hy2',
    'tuic',
    'anytls',
    'naive+https',
    'socks',
    'socks5',
    'tg',
    'wireguard',
    'wg',
    'sing-box',
    'clash',
  ];

  // PEM / OpenSSH private key blocks, with or without their END line (a
  // truncated error message must not leak the first 200 chars of a key).
  static final _pemBlock = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----\r?\n?|$)',
  );

  // key = value   |  key: value  |  KEY="value"  (shell, properties, YAML)
  static final _keyValue = RegExp(
    '\\b([A-Za-z0-9_.-]*(?:${secretKeyWords.join('|')})[A-Za-z0-9_.-]*)'
    r'''(\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s,;]+)''',
    caseSensitive: false,
  );

  // "key": "value"  (JSON: sing-box, xray, moav --json output)
  static final _jsonValue = RegExp(
    '("[A-Za-z0-9_.-]*(?:${secretKeyWords.join('|')})[A-Za-z0-9_.-]*"\\s*:\\s*)'
    r'("(?:[^"\\]|\\.)*"|[0-9A-Za-z+/=._-]+)',
    caseSensitive: false,
  );

  // Share links whose scheme carries the credential.
  static final _shareLink = RegExp(
    '\\b(${linkSchemes.map(RegExp.escape).join('|')})://\\S+',
    caseSensitive: false,
  );

  // MTProxy links.
  static final _mtproxy = RegExp(r'https?://t\.me/proxy\?\S+', caseSensitive: false);

  // Subscription URLs carry a per-user token in the path.
  static final _subscription = RegExp(
    r'https?://\S*/(?:sub|subscribe|subscription)\b\S*',
    caseSensitive: false,
  );

  // Long unbroken base64 runs are key material more often than not (an
  // OpenSSH key body is >200 chars; a wire-format ed25519 pubkey is 68).
  static final _base64Run = RegExp(r'(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{120,}={0,2}');

  /// Returns [text] with every recognisable secret replaced by a marker.
  static String scrub(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    var out = text;
    out = out.replaceAll(_pemBlock, keyMarker);
    out = out.replaceAllMapped(_shareLink, (m) => '[redacted ${m[1]!.toLowerCase()} link]');
    out = out.replaceAll(_mtproxy, '[redacted mtproxy link]');
    out = out.replaceAll(_subscription, '[redacted subscription link]');
    out = out.replaceAllMapped(_jsonValue, (m) => '${m[1]}"$valueMarker"');
    out = out.replaceAllMapped(_keyValue, (m) => '${m[1]}${m[2]}$valueMarker');
    out = out.replaceAll(_base64Run, keyMarker);
    return out;
  }

  /// True when [text] still looks like it carries a secret after scrubbing.
  /// Used by tests and by [AppLog] as a belt-and-braces check.
  static bool looksSecret(String text) =>
      _pemBlock.hasMatch(text) ||
      _shareLink.hasMatch(text) ||
      _mtproxy.hasMatch(text) ||
      _base64Run.hasMatch(text);
}
