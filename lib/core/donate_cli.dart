import '../security/redactor.dart';
import 'donate.dart';
import 'moav_cli.dart';
import 'ssh_connection.dart';

/// The `moav donate` invocations the SSH controller runs and the parsers for
/// their output.
///
/// Verified against the MoaV 2.3.1 sources (`lib/donate.sh`): none of the
/// `donate` subcommands has `--json`, so every parser here works on the
/// coloured text. `donate submit` (alias `donate`) has existed since 2.2.4;
/// `setup` and `submit` read their answers from stdin, which is how the app
/// drives them without a terminal. `confirm()` takes its default under
/// `MOAV_NONINTERACTIVE=1`. See docs/MOAV-CLI-GAPS.md.
class DonateCli {
  DonateCli._();

  /// `.env` variable `moav donate setup` writes and every MahsaNet command
  /// reads. The app checks that it is set; it never reads the value.
  static const apiKeyVar = 'MAHSANET_API_KEY';

  /// Where donors manage their configs and API keys.
  static const mahsaNetDashboardUrl = 'https://www.mahsaserver.com/login';
  static const mahsaNetApiKeyUrl = 'https://www.mahsaserver.com/user/api';

  /// Bounds `cmd_donate_mahsanet_donate` enforces on the user count.
  static const minCount = 1;
  static const maxCount = 50;

  /// Upstream's default username prefix; users become `mahsa01`, `mahsa02`...
  static const defaultPrefix = 'mahsa';

  /// Prefix characters upstream accepts.
  static final validPrefix = RegExp(r'^[a-zA-Z0-9_-]+$');

  /// Upstream's default `MAHSANET_PROTOCOLS` (lib/donate.sh).
  static const defaultProtocols = ['reality', 'hysteria2'];

  /// Mode-0600 file the API key is uploaded to for `setup`, relative to the
  /// login shell's home like `InstallScript.specPath`. Deleted right after.
  static const keyFile = '.moav-deploy/mahsanet.key';

  // TODO(#8): no `moav donate status --json`; the presence check reads `.env`.
  /// Prints whether [apiKeyVar] is set plus the donation settings, between
  /// markers. Deliberately echoes `present`/`absent` and never the key.
  static const env = '''
${MoavCli.envReader}
echo "__DONATE__"
if [ -n "\$(ev $apiKeyVar)" ]; then echo "mahsanet_key=present"; else echo "mahsanet_key=absent"; fi
echo "protocols=\$(grep -E '^MAHSANET_PROTOCOLS=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')"
echo "pool=\$(ev MAHSANET_POOL)"
echo "conduit_enabled=\$(ev ENABLE_CONDUIT)"
echo "snowflake_enabled=\$(ev ENABLE_SNOWFLAKE)"
echo "__END__"
''';

  // TODO(#8): `donate status|list` print coloured text only.
  /// `moav donate status`: MahsaNet totals (when a key is set), Conduit and
  /// Snowflake state with their metrics.
  static const status =
      '${MoavCli.prelude}MOAV_NONINTERACTIVE=1 "\$M" donate status 2>&1';

  /// `moav donate list`: one row per donated config. Exits 1 without a key.
  static const list =
      '${MoavCli.prelude}MOAV_NONINTERACTIVE=1 "\$M" donate list 2>&1';

  /// `moav donate setup`, answering `1` (MahsaNet) and then the key, which
  /// is read from [keyFile] so it never appears in the command or `ps`.
  /// Upstream validates the key against the API, writes [apiKeyVar] to
  /// `.env` and recreates the admin container. The file is removed whether
  /// or not setup succeeded, and the exit code is preserved.
  static const setupMahsaNet = '${MoavCli.prelude}'
      'K="\$HOME/$keyFile"; '
      '{ echo 1; cat "\$K"; } | MOAV_NONINTERACTIVE=1 "\$M" donate setup 2>&1; '
      'rc=\$?; rm -f "\$K"; exit \$rc';

  /// `moav donate submit`: creates [count] donate-mode users named
  /// `<prefix>01`..`<prefix>NN` and submits their configs to MahsaNet.
  /// The count and prefix answer the two `read` prompts; `Proceed?` takes
  /// its default (yes) under `MOAV_NONINTERACTIVE=1`. [force] re-donates
  /// configs already in the ledger.
  static String submit({
    required int count,
    String prefix = defaultPrefix,
    bool force = false,
  }) {
    final countError = validateCount('$count');
    if (countError != null) throw ArgumentError.value(count, 'count', countError);
    final prefixError = validatePrefix(prefix);
    if (prefixError != null) {
      throw ArgumentError.value(prefix, 'prefix', prefixError);
    }
    final flag = force ? ' --force' : '';
    return "${MoavCli.prelude}printf '%s\\n%s\\n' $count "
        '${SshConnection.shellQuote(prefix)} | '
        'MOAV_NONINTERACTIVE=1 "\$M" donate submit$flag 2>&1';
  }

  /// Form validation shared with the screen; `null` when [text] is fine.
  static String? validateCount(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < minCount || n > maxCount) {
      return 'Enter a number from $minCount to $maxCount';
    }
    return null;
  }

  static String? validatePrefix(String text) {
    if (text.isEmpty) return 'Enter a prefix';
    if (!validPrefix.hasMatch(text)) {
      return 'Use only letters, numbers, underscores and hyphens';
    }
    return null;
  }

  // --- Parsers ---

  /// Parses [env] output; `null` when the markers are missing.
  static DonateEnv? parseEnv(String raw, {DateTime? now}) {
    final text = SshConnection.stripAnsi(raw);
    final start = text.indexOf('__DONATE__');
    final end = text.indexOf('__END__');
    if (start < 0 || end < 0 || end < start) return null;
    var present = false;
    var protocols = defaultProtocols;
    String? pool;
    var conduit = true;
    var snowflake = true;
    for (final line in text.substring(start + 10, end).split('\n')) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      switch (key) {
        case 'mahsanet_key':
          present = value == 'present';
        case 'protocols':
          final v = value.replaceFirst(RegExp(r'\s+#.*$'), '').trim();
          if (v.isNotEmpty) protocols = v.split(RegExp(r'\s+'));
        case 'pool':
          pool = value.isEmpty ? null : value;
        case 'conduit_enabled':
          conduit = value.isEmpty || value == 'true';
        case 'snowflake_enabled':
          snowflake = value.isEmpty || value == 'true';
      }
    }
    return DonateEnv(
      mahsaNetKeyPresent: present,
      protocols: protocols,
      pool: pool,
      conduitEnabled: conduit,
      snowflakeEnabled: snowflake,
      collectedAt: now ?? DateTime.now(),
    );
  }

  static const _mahsaHeader = 'MahsaNet';
  static const _conduitHeader = 'Psiphon Conduit';
  static const _snowflakeHeader = 'Tor Snowflake';

  /// Parses [status] output; `null` when none of the three service headers
  /// is present (an old CLI, or the command never ran).
  static DonationStatus? parseStatus(String raw, {DateTime? now}) {
    final lines = SshConnection.stripAnsi(raw).split('\n');
    final sections = _sections(lines, const [
      _mahsaHeader,
      _conduitHeader,
      _snowflakeHeader,
    ]);
    if (sections.isEmpty) return null;
    final mahsa = sections[_mahsaHeader] ?? '';
    final conduit = sections[_conduitHeader] ?? '';
    final snowflake = sections[_snowflakeHeader] ?? '';
    return DonationStatus(
      mahsaNet: MahsaNetStats(
        configured: !mahsa.contains('Not configured'),
        total: _int(mahsa, r'Total configs:\s*(\d+)'),
        active: _int(mahsa, r'Active:\s*(\d+)'),
        inactive: _int(mahsa, r'Inactive:\s*(\d+)'),
        statsError: _errorLine(mahsa),
      ),
      conduit: _bandwidth(conduit, maxPattern: r'(\d+)\s*max clients'),
      snowflake: _bandwidth(snowflake, maxPattern: r'(\d+)\s*capacity'),
      collectedAt: now ?? DateTime.now(),
    );
  }

  /// Splits [lines] into the text under each header line (trimmed equality).
  static Map<String, String> _sections(List<String> lines, List<String> headers) {
    final out = <String, String>{};
    String? current;
    final buf = StringBuffer();
    void flush() {
      if (current != null) out[current] = buf.toString();
      buf.clear();
    }
    for (final line in lines) {
      final t = line.trim();
      if (headers.contains(t)) {
        flush();
        current = t;
        continue;
      }
      if (current != null) buf.writeln(line);
    }
    flush();
    return out;
  }

  static BandwidthDonation _bandwidth(String text, {required String maxPattern}) {
    final traffic = RegExp(r'Bandwidth:\s*(.+?)\s*↑\s*/\s*(.+?)\s*↓').firstMatch(text);
    return BandwidthDonation(
      enabled: !text.contains('Disabled'),
      running: text.contains('Running'),
      bandwidthMbps: _int(text, r'(\d+)\s*Mbps'),
      maxClients: _int(text, maxPattern),
      connected: _int(text, r'Connected:\s*(\d+)'),
      served: _int(text, r'Served:\s*(\d+)'),
      uploaded: traffic?.group(1)?.trim(),
      downloaded: traffic?.group(2)?.trim(),
    );
  }

  static int? _int(String text, String pattern) {
    final m = RegExp(pattern).firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The first `✗ ...` / `○ Could not ...` line, without its marker.
  static String? _errorLine(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.startsWith('✗') || t.startsWith('○ Could not')) {
        return t.substring(1).trim();
      }
    }
    return null;
  }

  static final _listRow = RegExp(
    r'^\s*(\d+)\s+(\S+)\s+(active|inactive)\s+(\S+)\s+(\d+)\s*$',
    multiLine: true,
  );

  /// Parses [list] output into rows without their links; an empty list for
  /// "No configs donated yet"; `null` when the output is not a listing.
  static List<DonatedConfig>? parseList(String raw) {
    final text = SshConnection.stripAnsi(raw);
    final rows = <DonatedConfig>[];
    for (final m in _listRow.allMatches(text)) {
      final url = m.group(2)!;
      final scheme = RegExp(r'^([a-z0-9+.-]+)://', caseSensitive: false)
          .firstMatch(url)
          ?.group(1)
          ?.toLowerCase();
      rows.add(DonatedConfig(
        index: int.parse(m.group(1)!),
        scheme: scheme ?? 'unknown',
        active: m.group(3) == 'active',
        healthPercent: _int(m.group(4)!, r'(\d+)%'),
        used: int.parse(m.group(5)!),
      ));
    }
    if (rows.isNotEmpty || text.contains('No configs donated yet')) return rows;
    if (RegExp(r'Total:\s*\d+\s*config').hasMatch(text)) return rows;
    return null;
  }

  /// `true` when `moav donate setup` reported the key written to `.env`.
  static bool keySaved(String raw) =>
      SshConnection.stripAnsi(raw).contains('API key saved to .env');

  /// One scrubbed sentence on why setup failed, from its `✗` line.
  static String setupFailure(String raw) {
    final line = _errorLine(SshConnection.stripAnsi(raw));
    return Redactor.scrub(line == null
        ? 'moav donate setup did not save the key'
        : 'MahsaNet rejected the key: $line');
  }

  /// Parses the "Donation Summary" block of [submit] output; `null` when
  /// the run stopped before it.
  static DonateResult? parseSubmit(String raw) {
    final text = SshConnection.stripAnsi(raw);
    final users = _int(text, r'Users created:\s*(\d+)');
    if (users == null) return null;
    return DonateResult(
      usersCreated: users,
      donated: _int(text, r'Configs donated:\s*(\d+)') ?? 0,
      skipped: _int(text, r'Skipped:\s*(\d+)') ?? 0,
      failed: _int(text, r'Failed:\s*(\d+)') ?? 0,
      quotaHit: text.contains('submission quota reached'),
    );
  }

  /// One scrubbed sentence on why a submit run produced no summary.
  static String submitFailure(String raw) {
    final line = _errorLine(SshConnection.stripAnsi(raw));
    return Redactor.scrub(line == null
        ? 'moav donate submit did not finish'
        : 'Donation stopped: $line');
  }
}
