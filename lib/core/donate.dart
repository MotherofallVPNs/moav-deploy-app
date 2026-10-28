/// Models for the Donate screen: what `moav donate` reports and what the
/// app asks it to do. The CLI side lives in `donate_cli.dart`.
library;

/// What `.env` says about donations, read in one round trip.
///
/// Only the *presence* of the MahsaNet API key is reported; the value itself
/// never leaves the server (see `DonateCli.env`).
class DonateEnv {
  const DonateEnv({
    required this.mahsaNetKeyPresent,
    required this.collectedAt,
    this.protocols = const [],
    this.pool,
    this.conduitEnabled = true,
    this.snowflakeEnabled = true,
  });

  /// `MAHSANET_API_KEY` is set and non-empty.
  final bool mahsaNetKeyPresent;

  /// `MAHSANET_PROTOCOLS`, split on whitespace; upstream's default when unset.
  final List<String> protocols;

  /// `MAHSANET_POOL`, or `null` when unset (upstream defaults to `mahsa`).
  final String? pool;

  /// `ENABLE_CONDUIT` / `ENABLE_SNOWFLAKE`; unset counts as enabled upstream.
  final bool conduitEnabled;
  final bool snowflakeEnabled;
  final DateTime collectedAt;

  @override
  String toString() =>
      'DonateEnv(mahsaNetKey: ${mahsaNetKeyPresent ? 'present' : 'absent'}, '
      'protocols: $protocols, pool: $pool, conduit: $conduitEnabled, '
      'snowflake: $snowflakeEnabled)';
}

/// MahsaNet totals as printed by `moav donate status`.
class MahsaNetStats {
  const MahsaNetStats({
    required this.configured,
    this.total,
    this.active,
    this.inactive,
    this.statsError,
  });

  /// An API key is configured in `.env`.
  final bool configured;

  /// Configs donated so far, per MahsaNet; `null` when not fetched.
  final int? total;
  final int? active;
  final int? inactive;

  /// The key is configured but MahsaNet could not be reached.
  final String? statsError;

  bool get hasStats => total != null;
}

/// One bandwidth donation service (Psiphon Conduit or Tor Snowflake).
class BandwidthDonation {
  const BandwidthDonation({
    required this.enabled,
    required this.running,
    this.bandwidthMbps,
    this.maxClients,
    this.connected,
    this.served,
    this.uploaded,
    this.downloaded,
  });

  final bool enabled;
  final bool running;

  /// `CONDUIT_BANDWIDTH` / `SNOWFLAKE_BANDWIDTH` in Mbps.
  final int? bandwidthMbps;

  /// `CONDUIT_MAX_COMMON_CLIENTS` / `SNOWFLAKE_CAPACITY`.
  final int? maxClients;

  /// Conduit: clients connected right now.
  final int? connected;

  /// Snowflake: people served since the exporter started counting.
  final int? served;

  /// Human-formatted totals as printed (`1.2 GB`); `null` when unavailable.
  final String? uploaded;
  final String? downloaded;

  bool get hasTraffic => uploaded != null || downloaded != null;
}

/// Everything `moav donate status` prints, parsed.
class DonationStatus {
  const DonationStatus({
    required this.mahsaNet,
    required this.conduit,
    required this.snowflake,
    required this.collectedAt,
  });

  final MahsaNetStats mahsaNet;
  final BandwidthDonation conduit;
  final BandwidthDonation snowflake;
  final DateTime collectedAt;
}

/// One row of `moav donate list`, without the share link it was printed
/// with (the link is a client credential and stays on the server).
class DonatedConfig {
  const DonatedConfig({
    required this.index,
    required this.scheme,
    required this.active,
    this.healthPercent,
    this.used = 0,
  });

  final int index;

  /// Link scheme, e.g. `vless`, `hysteria2`, `trojan`.
  final String scheme;
  final bool active;

  /// MahsaNet's health score, `null` when it printed none.
  final int? healthPercent;

  /// How many times MahsaNet handed the config out.
  final int used;
}

/// Status plus the donated list, fetched together for the Donate screen.
class DonateOverview {
  const DonateOverview({required this.status, this.configs = const []});

  final DonationStatus status;

  /// Empty when MahsaNet is not configured or the list could not be read.
  final List<DonatedConfig> configs;
}

/// The summary `moav donate submit` prints at the end of a run.
class DonateResult {
  const DonateResult({
    required this.usersCreated,
    required this.donated,
    this.skipped = 0,
    this.failed = 0,
    this.quotaHit = false,
  });

  final int usersCreated;
  final int donated;
  final int skipped;
  final int failed;

  /// MahsaNet's submission quota stopped the run early; a later run resumes.
  final bool quotaHit;

  @override
  String toString() =>
      'DonateResult(users: $usersCreated, donated: $donated, '
      'skipped: $skipped, failed: $failed, quotaHit: $quotaHit)';
}
