/// MoaV's service profiles and the `ENABLE_*` flags behind them.
///
/// Mirrors upstream MoaV v2.3.1: the `select_profiles` menu and the
/// `profile_enabled` / `confirm_disabled_profile` tables in `lib/service.sh`,
/// plus the service-to-profile membership in `docker-compose.yml`. Both the
/// install-time selection and the per-service enable/disable controls read
/// from here, so the app never invents a flag the CLI does not know.
library;

import 'moav_controller.dart';

/// One Compose profile as offered by `moav start <profile>`.
class MoavProfile {
  const MoavProfile({
    required this.name,
    required this.title,
    required this.description,
    required this.onFlags,
    this.offFlags = const [],
    this.recommended = true,
  });

  /// Compose profile name, e.g. `proxy`.
  final String name;
  final String title;
  final String description;

  /// Flags set to `true` when the profile is selected.
  final List<String> onFlags;

  /// Extra opt-in flags that are only ever set to `false` on deselect.
  final List<String> offFlags;

  /// Part of the app's default selection (upstream's stock `.env.example`
  /// defaults, which is what `derive_enabled_profiles` yields on a fresh box).
  final bool recommended;

  List<String> get allFlags => [...onFlags, ...offFlags];
}

class MoavProfiles {
  MoavProfiles._();

  /// Order of upstream `derive_enabled_profiles` (what `DEFAULT_PROFILES`
  /// gets on a non-interactive install), opt-in extras last.
  static const all = <MoavProfile>[
    MoavProfile(
      name: 'proxy',
      title: 'Proxy (sing-box)',
      description: 'Reality, Trojan, Hysteria2, Shadowsocks, Snell (v2ray apps)',
      onFlags: [
        'ENABLE_REALITY',
        'ENABLE_TROJAN',
        'ENABLE_HYSTERIA2',
        'ENABLE_SS',
        'ENABLE_SNELL',
      ],
      offFlags: ['ENABLE_ANYTLS'],
    ),
    MoavProfile(
      name: 'xhttp',
      title: 'VLESS XHTTP',
      description: 'VLESS+XHTTP+Reality (Xray-core)',
      onFlags: ['ENABLE_XHTTP'],
    ),
    MoavProfile(
      name: 'wireguard',
      title: 'WireGuard',
      description: 'WireGuard VPN + WebSocket tunnel',
      onFlags: ['ENABLE_WIREGUARD'],
    ),
    MoavProfile(
      name: 'amneziawg',
      title: 'AmneziaWG',
      description: 'Obfuscated WireGuard',
      onFlags: ['ENABLE_AMNEZIAWG'],
    ),
    MoavProfile(
      name: 'dnstunnel',
      title: 'DNS tunnels',
      description: 'dnstt, Slipstream, MasterDNS, XDNS (needs NS delegation)',
      onFlags: [
        'ENABLE_DNSTT',
        'ENABLE_SLIPSTREAM',
        'ENABLE_MASTERDNS',
        'ENABLE_XDNS',
      ],
    ),
    MoavProfile(
      name: 'trusttunnel',
      title: 'TrustTunnel',
      description: 'HTTP/2 + QUIC VPN (needs a domain)',
      onFlags: ['ENABLE_TRUSTTUNNEL'],
    ),
    MoavProfile(
      name: 'telegram',
      title: 'Telegram MTProxy',
      description: 'Fake-TLS MTProxy',
      onFlags: ['ENABLE_TELEMT'],
    ),
    MoavProfile(
      name: 'admin',
      title: 'Admin dashboard',
      description: 'Stats dashboard on port 9443',
      onFlags: ['ENABLE_ADMIN_UI'],
    ),
    MoavProfile(
      name: 'conduit',
      title: 'Psiphon Conduit',
      description: 'Donate bandwidth via Psiphon',
      onFlags: ['ENABLE_CONDUIT'],
    ),
    MoavProfile(
      name: 'snowflake',
      title: 'Tor Snowflake',
      description: 'Donate bandwidth via Tor',
      onFlags: ['ENABLE_SNOWFLAKE'],
    ),
    MoavProfile(
      name: 'monitoring',
      title: 'Monitoring',
      description: 'Grafana + Prometheus (2 GB+ RAM)',
      onFlags: ['ENABLE_MONITORING'],
      recommended: false,
    ),
    MoavProfile(
      name: 'gooserelay',
      title: 'GooseRelay',
      description: 'SOCKS5 over Google Apps Script (needs client setup)',
      onFlags: ['ENABLE_GOOSERELAY'],
      recommended: false,
    ),
  ];

  /// The app's default selection: what a stock `.env.example` enables, in
  /// the order upstream `derive_enabled_profiles` emits it.
  static const defaults = <String>[
    'proxy',
    'xhttp',
    'wireguard',
    'amneziawg',
    'dnstunnel',
    'trusttunnel',
    'telegram',
    'admin',
    'conduit',
    'snowflake',
  ];

  static final validName = RegExp(r'^[a-z0-9-]+$');

  static MoavProfile? byName(String name) {
    for (final p in all) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// `ENABLE_*` values that make `.env` agree with [selected]: on-flags of
  /// selected profiles become `true`, every flag of a deselected profile
  /// `false`. Unknown names are ignored.
  static Map<String, bool> enableFlagsFor(Iterable<String> selected) {
    final chosen = selected.toSet();
    final out = <String, bool>{};
    for (final p in all) {
      if (chosen.contains(p.name)) {
        for (final f in p.onFlags) {
          out[f] = true;
        }
      } else {
        for (final f in p.allFlags) {
          out[f] = false;
        }
      }
    }
    return out;
  }
}

/// One client protocol, the flag that enables it and the user store it
/// needs; see [MoavServices.userProtocolFlags].
class UserProtocol {
  const UserProtocol(this.id, this.flag, {this.store});

  /// Bundle protocol id as used by [BundleEntry.titles], e.g. `hysteria2`.
  final String id;
  final String flag;

  /// `moav user list` service that must list the user; `null` when shared.
  final String? store;
}

/// How a `moav status` service row maps to `.env` flags.
class ServiceToggle {
  const ServiceToggle({required this.onFlags, this.offFlags = const []});

  /// Set to `true` on enable.
  final List<String> onFlags;

  /// Only ever set to `false` on disable (opt-in sub-protocols).
  final List<String> offFlags;

  List<String> get allFlags => [...onFlags, ...offFlags];

  Map<String, bool> flags({required bool enabled}) => {
        for (final f in enabled ? onFlags : allFlags) f: enabled,
      };
}

class MoavServices {
  MoavServices._();

  static const _proxy = ServiceToggle(
    onFlags: [
      'ENABLE_REALITY',
      'ENABLE_TROJAN',
      'ENABLE_HYSTERIA2',
      'ENABLE_SS',
      'ENABLE_SNELL',
    ],
    offFlags: ['ENABLE_ANYTLS'],
  );
  static const _monitoring = ServiceToggle(onFlags: ['ENABLE_MONITORING']);

  /// Compose service name (as printed by `moav status`) to its toggle.
  /// Support containers (certbot, decoy, dns-router, docker-proxy) follow the
  /// protocols they serve and have no flag of their own.
  static const toggles = <String, ServiceToggle>{
    'sing-box': _proxy,
    'wireguard': ServiceToggle(onFlags: ['ENABLE_WIREGUARD']),
    'wstunnel': ServiceToggle(onFlags: ['ENABLE_WIREGUARD']),
    'amneziawg': ServiceToggle(onFlags: ['ENABLE_AMNEZIAWG']),
    'dnstt': ServiceToggle(onFlags: ['ENABLE_DNSTT']),
    'slipstream': ServiceToggle(onFlags: ['ENABLE_SLIPSTREAM']),
    'masterdns': ServiceToggle(onFlags: ['ENABLE_MASTERDNS']),
    'xray': ServiceToggle(onFlags: ['ENABLE_XHTTP']),
    'trusttunnel': ServiceToggle(onFlags: ['ENABLE_TRUSTTUNNEL']),
    'telemt': ServiceToggle(onFlags: ['ENABLE_TELEMT']),
    'admin': ServiceToggle(onFlags: ['ENABLE_ADMIN_UI']),
    'psiphon-conduit': ServiceToggle(onFlags: ['ENABLE_CONDUIT']),
    'snowflake': ServiceToggle(onFlags: ['ENABLE_SNOWFLAKE']),
    'gooserelay': ServiceToggle(onFlags: ['ENABLE_GOOSERELAY']),
    'prometheus': _monitoring,
    'grafana': _monitoring,
    'grafana-proxy': _monitoring,
    'node-exporter': _monitoring,
    'cadvisor': _monitoring,
    'singbox-exporter': _monitoring,
    'telemt-exporter': _monitoring,
    'xray-exporter': _monitoring,
    'wireguard-exporter': _monitoring,
    'snowflake-exporter': _monitoring,
    'amneziawg-exporter': _monitoring,
  };

  static ServiceToggle? toggleFor(String service) => toggles[service];

  /// Client protocols a user can be handed, each with the `.env` flag that
  /// turns it on and the user store (`moav user list` service) it needs.
  /// A `null` store is a shared tunnel every bundle gets (dnstt, Slipstream,
  /// MasterDNS, GooseRelay). Mirrors upstream `scripts/generate-user.sh`.
  static const userProtocolFlags = <UserProtocol>[
    UserProtocol('reality', 'ENABLE_REALITY', store: 'sing-box'),
    UserProtocol('trojan', 'ENABLE_TROJAN', store: 'sing-box'),
    UserProtocol('anytls', 'ENABLE_ANYTLS', store: 'sing-box'),
    UserProtocol('hysteria2', 'ENABLE_HYSTERIA2', store: 'sing-box'),
    UserProtocol('shadowsocks', 'ENABLE_SS', store: 'sing-box'),
    UserProtocol('snell', 'ENABLE_SNELL', store: 'sing-box'),
    UserProtocol('cdn', 'ENABLE_CDN', store: 'sing-box'),
    UserProtocol('xhttp', 'ENABLE_XHTTP', store: 'xray'),
    UserProtocol('xdns', 'ENABLE_XDNS', store: 'xray'),
    UserProtocol('wireguard', 'ENABLE_WIREGUARD', store: 'wireguard'),
    UserProtocol('wireguard-wstunnel', 'ENABLE_WIREGUARD', store: 'wireguard'),
    UserProtocol('amneziawg', 'ENABLE_AMNEZIAWG', store: 'amneziawg'),
    UserProtocol('trusttunnel', 'ENABLE_TRUSTTUNNEL', store: 'trusttunnel'),
    UserProtocol('telegram', 'ENABLE_TELEMT', store: 'telegram'),
    UserProtocol('dnstt', 'ENABLE_DNSTT'),
    UserProtocol('slipstream', 'ENABLE_SLIPSTREAM'),
    UserProtocol('masterdns', 'ENABLE_MASTERDNS'),
    UserProtocol('gooserelay', 'ENABLE_GOOSERELAY'),
  ];

  /// The protocols a user actually gets on a server: every entry of
  /// [userProtocolFlags] whose flag is on in [flags] and whose store (if
  /// any) lists the user in [stores]. With [flags] unknown (still loading,
  /// or a box without `.env`) the upstream defaults decide, so the answer
  /// is the server's protocol set rather than the six store names.
  static List<String> userProtocols(
    Iterable<String> stores, {
    ServiceFlags? flags,
  }) {
    final mine = stores.toSet();
    return [
      for (final p in userProtocolFlags)
        if ((p.store == null || mine.contains(p.store)) &&
            (flags?.isOn(p.flag) ?? flagDefault(p.flag)))
          p.id,
    ];
  }

  /// Upstream's default when a flag is absent or empty in `.env`
  /// (`get_env_val KEY .env <default>`): opt-in flags are off, the rest on.
  static bool flagDefault(String key) => switch (key) {
        'ENABLE_ANYTLS' || 'ENABLE_GOOSERELAY' || 'ENABLE_CDN' => false,
        _ => true,
      };

  static final validFlag = RegExp(r'^ENABLE_[A-Z0-9_]+$');
}
