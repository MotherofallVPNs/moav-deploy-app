/// The built-in demo server: a [MoavController] that emulates every server
/// operation in memory so a new user can walk the whole app, from install to
/// analytics, without a server, SSH or network.
///
/// Values are documentation values only (RFC 2606 domain, TEST-NET-3
/// address, synthetic keys). State is mutable (users, service states, the
/// install result) but never persisted: a fresh instance is the pristine
/// baseline. See docs/ARCHITECTURE.md.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';

import 'app_error.dart';
import 'dns_check.dart';
import 'dns_records.dart';
import 'donate.dart';
import 'donate_cli.dart';
import 'install_progress.dart';
import 'moav_cli.dart';
import 'moav_controller.dart';
import 'moav_services.dart';

/// One log line of an emulated job and when it appears, relative to start.
typedef _Line = (Duration at, String text);

/// A service row of the demo, mutable so actions can move it.
class _DemoService {
  _DemoService(this.name, this.state, this.ports, this.uptime);

  final String name;
  ServiceState state;
  final List<String> ports;
  String? uptime;
}

class DemoMoavController implements MoavController {
  DemoMoavController({
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _now = now ?? clock.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d)) {
    reset();
  }

  /// Time source: `clock.now` by default so widget tests drive the install
  /// timeline with `pump`; unit tests pass their own.
  final DateTime Function() _now;

  /// How the demo waits; tests pass a no-op so nothing sleeps.
  final Future<void> Function(Duration) _delay;

  static const domain = 'demo.example.org';
  static const ip = '203.0.113.10';
  static const installedVersion = '2.3.1';
  static const latestVersion = '2.3.2';

  /// Pre-filled install form values. The password is a documentation value
  /// that satisfies the installer's own rules (12+ chars, no shell specials).
  static const installDomain = domain;
  static const installPassword = 'demo-admin-passw0rd';

  /// The one answer for anything that needs a real box behind the app.
  static AppError unavailable(String what) => AppError(
        AppErrorKind.unreachable,
        'The demo server has no $what to open.',
        hint: 'This is the built-in demo: nothing runs behind it, so there '
            'is no web page to load. Everything else here is emulated.',
      );

  // --- Emulated state ---

  late bool _installed;
  late String _version;
  late List<MoavUser> _users;
  late List<_DemoService> _services;
  late Map<String, String> _flags;
  late bool _mahsaNetKey;
  DateTime? _installStartedAt;
  InstallSpec? _installSpec;
  DateTime? _updateStartedAt;

  /// Back to the pristine baseline: not installed, stock users, every
  /// service as `moav status` shows it on a healthy box.
  void reset() {
    _installed = false;
    _version = installedVersion;
    _installStartedAt = null;
    _installSpec = null;
    _updateStartedAt = null;
    _mahsaNetKey = false;
    final created = DateTime.utc(2026, 10, 2, 9, 30);
    _users = [
      _user('alice', created),
      _user('bob', created.add(const Duration(days: 3, hours: 5))),
      _user('family-tablet', created.add(const Duration(days: 11))),
      _user('office-laptop', created.add(const Duration(days: 19, hours: 2))),
    ];
    _services = [
      _DemoService('sing-box', ServiceState.running, ['443/tcp', '8443/udp'], '3 days'),
      _DemoService('xray', ServiceState.running, ['2053/tcp'], '3 days'),
      _DemoService('wireguard', ServiceState.running, ['51820/udp'], '3 days'),
      _DemoService('wstunnel', ServiceState.running, ['8080/tcp'], '3 days'),
      _DemoService('amneziawg', ServiceState.running, ['51821/udp'], '3 days'),
      _DemoService('dnstt', ServiceState.running, ['53/udp'], '3 days'),
      _DemoService('slipstream', ServiceState.running, ['5353/udp'], '3 days'),
      _DemoService('masterdns', ServiceState.running, ['5354/udp'], '3 days'),
      _DemoService('trusttunnel', ServiceState.running, ['8444/tcp', '8444/udp'], '3 days'),
      _DemoService('telemt', ServiceState.running, ['443/tcp'], '3 days'),
      _DemoService('admin', ServiceState.running, ['9443/tcp'], '3 days'),
      _DemoService('psiphon-conduit', ServiceState.running, const [], '3 days'),
      _DemoService('snowflake', ServiceState.unhealthy, const [], '3 days'),
      _DemoService('gooserelay', ServiceState.never, const [], null),
      _DemoService('certbot', ServiceState.exited, const [], null),
      _DemoService('decoy', ServiceState.running, ['80/tcp'], '3 days'),
      _DemoService('prometheus', ServiceState.running, const [], '3 days'),
      _DemoService('grafana', ServiceState.running, ['9444/tcp'], '3 days'),
      _DemoService('node-exporter', ServiceState.running, const [], '3 days'),
      _DemoService('cadvisor', ServiceState.running, const [], '3 days'),
    ];
    _flags = {
      for (final p in MoavProfiles.all)
        for (final f in p.allFlags) f: 'true',
      'ENABLE_ANYTLS': 'false',
      'ENABLE_GOOSERELAY': 'false',
      'ENABLE_MONITORING': 'true',
    };
  }

  static MoavUser _user(String name, DateTime createdAt) => MoavUser(
        name: name,
        createdAt: createdAt,
        bundleReady: true,
        protocols: const [
          'sing-box',
          'xray',
          'wireguard',
          'amneziawg',
          'trusttunnel',
          'telegram',
        ],
      );

  static const _profiles = [
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
    'monitoring',
  ];

  static final _adminUrl = Uri.parse('https://$domain:9443/');

  /// Looks like the real one but is never launched: the demo leaves the
  /// browser URLs out of [monitoring] so no button opens example.org.
  static final _grafanaUrl = Uri.parse('https://$domain:9444/');

  // --- Connection ---

  @override
  Future<ConnectionCheck> ping() async {
    await _delay(const Duration(milliseconds: 300));
    return ConnectionCheck(
      reachable: true,
      moavInstalled: _installed,
      moavVersion: _installed ? _version : null,
    );
  }

  @override
  Future<String?> publicIp() async {
    await _delay(const Duration(milliseconds: 200));
    return ip;
  }

  @override
  Future<DnsCheckReport> checkDns({
    required String domain,
    required String serverIp,
  }) async {
    await _delay(const Duration(milliseconds: 600));
    return DnsCheckReport(
      tool: 'dig',
      checkedAt: _now(),
      checks: [
        for (final r in DnsRecords.forDomain(domain, serverIp))
          DnsRecordCheck(
            record: r,
            result: CheckResult.pass,
            detail: r.type == 'A' ? 'points to ${r.value}' : 'delegated to ${r.value}',
            found: [r.value],
          ),
      ],
    );
  }

  // --- Install ---

  /// The emulated deploy.sh, on a timeline of seconds instead of minutes.
  /// Step boundaries are at 0, 1.5, 6 and 16 s; `exit=0` lands at 20 s.
  static const installStepsAt = [
    Duration.zero,
    Duration(milliseconds: 1500),
    Duration(seconds: 6),
    Duration(seconds: 16),
  ];
  static const installDoneAt = Duration(seconds: 20);

  List<_Line> _installLines(InstallSpec spec, DateTime startedAt) {
    final domain = spec.domain.trim();
    final profiles = spec.profiles.isEmpty ? MoavProfiles.defaults : spec.profiles;
    const ms = Duration.new;
    final date = startedAt.toUtc().toIso8601String().split('.').first;
    return [
      (installStepsAt[0], '[moav-deploy] step 1/4: Preflight'),
      (installStepsAt[0], 'Host: demo  User: moav  Date: ${date}Z'),
      (ms(milliseconds: 400), 'No MoaV install at /opt/moav - performing a fresh install.'),
      (installStepsAt[1], ''),
      (installStepsAt[1], '[moav-deploy] step 2/4: Run MoaV installer (non-interactive .env setup)'),
      (
        installStepsAt[1],
        domain.isEmpty
            ? 'No domain: domainless mode (the installer disables certificate-dependent protocols itself)'
            : "Domain: $domain (Let's Encrypt email set)",
      ),
      (ms(milliseconds: 1800), 'ENABLE_* flags passed from the selected services'),
      (ms(milliseconds: 2300), 'Installing prerequisites: curl git ca-certificates'),
      (ms(milliseconds: 3200), 'Installing Docker Engine 28.3 from download.docker.com'),
      (ms(milliseconds: 4600), 'Cloning MoaV (main) into /opt/moav'),
      (ms(milliseconds: 5400), 'Writing /opt/moav/.env (mode 0600): DEFAULT_PROFILES=${profiles.join(' ')}'),
      (installStepsAt[2], ''),
      (installStepsAt[2], '[moav-deploy] step 3/4: Bootstrap MoaV'),
      (installStepsAt[2], 'Bootstrapping (keys, certs, first user); the image build is the long part...'),
      (ms(milliseconds: 6500), 'Building images: sing-box xray wireguard amneziawg dnstt slipstream telemt admin'),
      (ms(milliseconds: 9000), 'Reality keypair generated'),
      (
        ms(milliseconds: 9800),
        domain.isEmpty
            ? 'Self-signed certificate generated for $ip'
            : "Requesting Let's Encrypt certificate for $domain",
      ),
      (ms(milliseconds: 11500), domain.isEmpty ? 'Certificate written' : 'Certificate issued (expires in 89 days)'),
      (ms(milliseconds: 12300), 'WireGuard and AmneziaWG server keys generated'),
      (ms(milliseconds: 13200), 'Creating first user: alice'),
      (ms(milliseconds: 14500), 'Bundle written to /opt/moav/outputs/bundles/alice (12 files)'),
      (installStepsAt[3], ''),
      (installStepsAt[3], '[moav-deploy] step 4/4: Start services'),
      (ms(milliseconds: 16200), 'Container moav-sing-box  Started'),
      (ms(milliseconds: 16600), 'Container moav-xray  Started'),
      (ms(milliseconds: 17000), 'Container moav-wireguard  Started'),
      (ms(milliseconds: 17400), 'Container moav-amneziawg  Started'),
      (ms(milliseconds: 17800), 'Container moav-dnstt  Started'),
      (ms(milliseconds: 18200), 'Container moav-telemt  Started'),
      (ms(milliseconds: 18600), 'Container moav-admin  Started'),
      (ms(milliseconds: 19000), 'Container moav-grafana  Started'),
      (ms(milliseconds: 19500), 'All services started. Dashboard: $_adminUrl'),
      (installDoneAt, ''),
      (installDoneAt, '[moav-deploy] exit=0'),
    ];
  }

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    await _delay(const Duration(milliseconds: 400));
    _installStartedAt = _now();
    _installSpec = spec;
    return const InstallHandle(
      jobId: 'demo-install',
      logPath: '.moav-deploy/deploy.log',
    );
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async {
    await _delay(const Duration(milliseconds: 100));
    final started = _installStartedAt;
    final spec = _installSpec;
    if (started == null || spec == null) {
      return const InstallStatus(
        phase: InstallPhase.unknown,
        message: 'No install log found on the server',
      );
    }
    final elapsed = _now().difference(started);
    final lines = [
      for (final (at, text) in _installLines(spec, started))
        if (at <= elapsed) text,
    ];
    var step = 0;
    for (var i = 0; i < installStepsAt.length; i++) {
      if (elapsed >= installStepsAt[i]) step = i + 1;
    }
    if (elapsed >= installDoneAt) {
      _installed = true;
      return InstallStatus(
        phase: InstallPhase.succeeded,
        logTail: lines,
        progress: 1,
        progressIsExact: true,
        message: 'Install finished',
        step: 4,
        totalSteps: 4,
      );
    }
    final stepStart = installStepsAt[step - 1];
    final stepEnd = step < installStepsAt.length ? installStepsAt[step] : installDoneAt;
    final f = (elapsed - stepStart).inMilliseconds / (stepEnd - stepStart).inMilliseconds;
    final (start, end, _) = InstallProgress.spanFor(step, 4);
    return InstallStatus(
      phase: InstallPhase.running,
      logTail: lines,
      progress: start + (end - start) * f.clamp(0, 1),
      progressIsExact: true,
      message: const [
        'Preflight',
        'Run MoaV installer (non-interactive .env setup)',
        'Bootstrap MoaV',
        'Start services',
      ][step - 1],
      step: step,
      totalSteps: 4,
    );
  }

  // --- Health ---

  @override
  Future<DoctorReport> doctor() async {
    await _delay(const Duration(milliseconds: 700));
    DoctorCheck check(String id, CheckResult r, List<String> detail) => DoctorCheck(
          name: id,
          result: r,
          detail: [MoavCli.doctorDescriptions[id] ?? id, ...detail].join('\n'),
        );
    final running = _services.where((s) => s.state.isUp).length;
    final down = _services.where((s) => !s.state.isUp && s.state != ServiceState.never && s.name != 'certbot');
    return DoctorReport(
      collectedAt: _now(),
      checks: [
        check('docker', CheckResult.pass, ['Docker 28.3.2, compose v2.39.1', 'docker-proxy reachable']),
        check('memory', CheckResult.pass, ['3.8 GB total, 2.9 GB available']),
        check('disk', CheckResult.pass, ['31.4 GB free on / (78%)']),
        check('logs', CheckResult.warn, ['moav-sing-box log is 48 MB', 'Rotate with: moav logs --prune']),
        check('dns', CheckResult.pass, [
          '$domain -> $ip',
          'dns.$domain -> $ip',
          't.$domain, s.$domain, m.$domain, x.$domain delegated to dns.$domain',
        ]),
        check(
          'services',
          down.isEmpty ? CheckResult.pass : CheckResult.warn,
          [
            '$running of ${_services.length} containers up',
            for (final s in down) '${s.name} is ${s.state.name} but enabled in .env',
          ],
        ),
        check('config', CheckResult.pass, ['Reality, WireGuard and AmneziaWG keys present', 'TLS certificate valid for 89 days']),
        check('ports', CheckResult.pass, ['443, 2053, 8443, 51820, 51821 bound by MoaV']),
        check('conflicts', CheckResult.pass, ['No systemd-resolved, nginx or apache on the MoaV ports']),
        check('reality', CheckResult.pass, ['www.microsoft.com:443 resolves and answers TLS 1.3']),
        check('net', CheckResult.pass, ['BBR enabled, qdisc fq', 'No packet drops on eth0', 'PMTU 1500, no CGNAT']),
        check('host', CheckResult.pass, ['load 0.42 on 2 CPUs', 'swap 0% used', 'no zombie processes']),
        check('peers', CheckResult.pass, ['${_users.length} WireGuard peers, no duplicate addresses']),
        check('env', CheckResult.pass, ['.env has every variable from .env.example']),
        check(
          'updates',
          _version == latestVersion ? CheckResult.pass : CheckResult.warn,
          [
            _version == latestVersion
                ? 'Up to date (v$_version)'
                : 'Update available: v$latestVersion (running v$_version)',
          ],
        ),
      ],
    );
  }

  // --- Users and bundles ---

  @override
  Future<List<MoavUser>> listUsers() async {
    await _delay(const Duration(milliseconds: 250));
    return List.unmodifiable(_users);
  }

  @override
  Future<MoavUser> addUser(String name) async {
    if (!MoavUser.validName.hasMatch(name)) {
      throw AppError(
        AppErrorKind.invalidInput,
        'Invalid username: $name',
        hint: 'Letters, numbers, _ and - only.',
      );
    }
    if (_users.any((u) => u.name == name)) {
      throw AppError(
        AppErrorKind.commandFailed,
        'User $name already exists',
        hint: 'Pick another name or revoke the existing user first.',
      );
    }
    await _delay(const Duration(milliseconds: 900));
    final user = _user(name, _now());
    _users = [..._users, user]..sort((a, b) => a.name.compareTo(b.name));
    return user;
  }

  @override
  Future<void> removeUser(String name) async {
    if (!_users.any((u) => u.name == name)) {
      throw AppError(AppErrorKind.commandFailed, 'No such user: $name');
    }
    await _delay(const Duration(milliseconds: 500));
    _users = _users.where((u) => u.name != name).toList();
  }

  @override
  Future<Bundle> getBundle(String user) async {
    if (!_users.any((u) => u.name == user)) {
      throw AppError(
        AppErrorKind.commandFailed,
        'No bundle for $user',
        hint: 'The user does not exist on the demo server.',
      );
    }
    await _delay(const Duration(milliseconds: 400));
    final entries = [
      for (final (file, content) in demoBundleFiles(user))
        MoavCli.bundleEntry(file, content),
    ].whereType<BundleEntry>().toList()
      ..sort(MoavCli.compareEntries);
    return Bundle(
      user: user,
      entries: entries,
      fetchedAt: _now(),
      path: '${MoavCli.bundlesDir}/$user',
    );
  }

  @override
  Future<Uint8List?> getBundleArchive(String user) async => null;

  /// The files of a demo user's bundle directory, in upstream's names so
  /// `MoavCli.classifyBundleFile` recognises every one of them. Keys and
  /// secrets are synthetic: derived from the username, never generated by
  /// a real tool, and good for nothing but drawing a QR code.
  static List<(String, String)> demoBundleFiles(String user) {
    final uuid = _fakeUuid(user);
    final pbk = _fakeKey('$user:pbk');
    final sid = _fakeHex('$user:sid', 8);
    final pass = _fakeHex('$user:pass', 24);
    const sni = 'www.microsoft.com';
    final reality = 'vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision'
        '&security=reality&sni=$sni&fp=chrome&pbk=$pbk&sid=$sid&type=tcp'
        '#MoaV-$user-reality';
    final hysteria = 'hysteria2://$pass@$domain:8443/?sni=$domain'
        '&obfs=salamander&obfs-password=${_fakeHex('$user:obfs', 16)}'
        '#MoaV-$user-hysteria2';
    final trojan = 'trojan://$pass@$domain:8443?security=tls&sni=$domain&type=tcp'
        '#MoaV-$user-trojan';
    final ssUserInfo = base64Url
        .encode(utf8.encode('2022-blake3-aes-128-gcm:${_fakeKey('$user:ss')}'))
        .replaceAll('=', '');
    final shadowsocks = 'ss://$ssUserInfo@$ip:8388#MoaV-$user-shadowsocks';
    final xhttp = 'vless://$uuid@$ip:2053?encryption=none&security=reality'
        '&sni=$sni&fp=chrome&pbk=$pbk&sid=$sid&type=xhttp&path=%2Fdemo&mode=auto'
        '#MoaV-$user-xhttp';
    final telegram = 'tg://proxy?server=$domain&port=443'
        '&secret=ee${_fakeHex('$user:mtproto', 32)}7777772e6d6963726f736f66742e636f6d';
    final subscription = base64.encode(
      utf8.encode([reality, hysteria, trojan, shadowsocks, xhttp].join('\n')),
    );
    final octet = 10 + (_hash(user) % 200);
    final wg = '''
# MoaV demo bundle for $user: synthetic keys, not a real peer
[Interface]
PrivateKey = ${_fakeKey('$user:wg-priv')}
Address = 10.66.66.$octet/32
DNS = 10.66.66.1

[Peer]
PublicKey = ${_fakeKey('demo:wg-server')}
PresharedKey = ${_fakeKey('$user:wg-psk')}
Endpoint = $ip:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';
    final wgws = wg
        .replaceFirst('Endpoint = $ip:51820', 'Endpoint = 127.0.0.1:51820')
        .replaceFirst('[Peer]', '# wstunnel client: wss://$domain:8080/wg\n[Peer]');
    final awg = '''
# MoaV demo bundle for $user: synthetic keys, not a real peer
[Interface]
PrivateKey = ${_fakeKey('$user:awg-priv')}
Address = 10.77.77.$octet/32
DNS = 10.77.77.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 15
S2 = 25
H1 = 1234567
H2 = 2345678
H3 = 3456789
H4 = 4567890

[Peer]
PublicKey = ${_fakeKey('demo:awg-server')}
PresharedKey = ${_fakeKey('$user:awg-psk')}
Endpoint = $ip:51821
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';
    final trusttunnel = const JsonEncoder.withIndent('  ').convert({
      'server': '$domain:8444',
      'username': user,
      'password': pass,
      'protocols': ['http2', 'quic'],
      'note': 'MoaV demo bundle: synthetic credentials',
    });
    const dnstt = '''
dnstt tunnel (shared)
  nameserver: dns.$domain
  domain:     t.$domain
  pubkey:     synthetic-demo-key
Use with the dnstt client: dnstt-client -doh https://1.1.1.1/dns-query -pubkey-file server.pub t.$domain 127.0.0.1:7000
''';
    final snell = '''
# Snell v4 (Surge)
Proxy = snell, $domain, 6160, psk=${_fakeHex('$user:snell', 20)}, version=4, obfs=tls
''';
    return [
      ('subscription.txt', '$subscription\n'),
      ('reality.txt', '$reality\n'),
      ('hysteria2.txt', '$hysteria\n'),
      ('trojan.txt', '$trojan\n'),
      ('shadowsocks.txt', '$shadowsocks\n'),
      ('xhttp-vless.txt', '$xhttp\n'),
      ('telegram-proxy-link.txt', '$telegram\n'),
      ('$user-wg.conf', wg),
      ('$user-wgws.conf', wgws),
      ('$user-awg.conf', awg),
      ('trusttunnel.json', '$trusttunnel\n'),
      ('dnstt.txt', dnstt),
      ('snell.txt', snell),
      ('README.html', '<html></html>'),
      ('reality.png', ''),
    ];
  }

  // Deterministic, obviously synthetic material: a tiny FNV hash stretched
  // into bytes. Nothing here is a key any tool produced or would accept.
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  static List<int> _bytes(String seed, int n) {
    var h = _hash(seed);
    return List<int>.generate(n, (_) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      return (h >> 16) & 0xff;
    });
  }

  static String _fakeKey(String seed) => base64.encode(_bytes(seed, 32));

  static String _fakeHex(String seed, int chars) => _bytes(seed, (chars + 1) ~/ 2)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .substring(0, chars);

  static String _fakeUuid(String seed) {
    final h = _fakeHex('$seed:uuid', 32);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}'
        '-a${h.substring(17, 20)}-${h.substring(20, 32)}';
  }

  // --- Services ---

  _DemoService _service(String name) {
    for (final s in _services) {
      if (s.name == name) return s;
    }
    throw AppError(
      AppErrorKind.commandFailed,
      'No such service: $name',
      detail: 'Known services: ${_services.map((s) => s.name).join(', ')}',
    );
  }

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    void out(String line) => onOutput?.call('$line\n');
    final targets = action.service == null
        ? _services.where((s) => s.name != 'certbot' && s.state != ServiceState.never).toList()
        : [_service(action.service!)];

    Future<void> stop() async {
      for (final s in targets) {
        if (!s.state.isUp) {
          out('Container moav-${s.name} is not running');
          continue;
        }
        out('Stopping moav-${s.name} ...');
        await _delay(const Duration(milliseconds: 350));
        s.state = ServiceState.stopped;
        s.uptime = null;
        out('Container moav-${s.name}  Stopped');
      }
    }

    Future<void> start() async {
      for (final s in targets) {
        if (s.state == ServiceState.running) {
          out('Container moav-${s.name}  Running');
          continue;
        }
        s.state = ServiceState.starting;
        out('Container moav-${s.name}  Starting');
        await _delay(const Duration(milliseconds: 450));
        s.state = ServiceState.running;
        s.uptime = 'Less than a second';
        out('Container moav-${s.name}  Started');
      }
      // The health check turns a started container green a moment later.
      await _delay(const Duration(milliseconds: 300));
      for (final s in targets) {
        if (s.state == ServiceState.running) s.uptime = '2 seconds';
      }
    }

    switch (action.kind) {
      case ServiceActionKind.stop:
        await stop();
      case ServiceActionKind.start:
        await start();
      case ServiceActionKind.restart:
        await stop();
        await start();
      case ServiceActionKind.enable:
        final toggle = MoavServices.toggleFor(action.service!);
        for (final f in toggle?.onFlags ?? const <String>[]) {
          out('$f=true written to /opt/moav/.env');
          _flags[f] = 'true';
        }
        await start();
      case ServiceActionKind.disable:
        final toggle = MoavServices.toggleFor(action.service!);
        for (final f in toggle?.allFlags ?? const <String>[]) {
          out('$f=false written to /opt/moav/.env');
          _flags[f] = 'false';
        }
        await stop();
      case ServiceActionKind.regenerateUsers:
        out('Regenerating bundles for ${_users.length} users from /opt/moav/.env');
        for (final u in _users) {
          await _delay(const Duration(milliseconds: 300));
          out('  ${u.name}: 12 files written to ${MoavCli.bundlesDir}/${u.name}');
        }
        _users = [for (final u in _users) _user(u.name, u.createdAt ?? _now())];
        out('Done. Existing keys kept; clients keep working.');
    }
  }

  @override
  Future<ServiceStatusReport> status() async {
    await _delay(const Duration(milliseconds: 300));
    return ServiceStatusReport(
      collectedAt: _now(),
      version: _version,
      adminUrl: _adminUrl,
      grafanaUrl: _grafanaUrl,
      defaultProfiles: _profiles,
      services: [
        for (final s in _services)
          ServiceStatus(
            name: s.name,
            state: s.state,
            uptime: s.uptime,
            ports: s.ports,
            lastRun: s.name == 'certbot' ? '6 hours ago' : null,
          ),
      ],
    );
  }

  @override
  Future<ServiceFlags> serviceFlags() async {
    await _delay(const Duration(milliseconds: 200));
    return ServiceFlags(
      values: Map.unmodifiable(_flags),
      defaultProfiles: _profiles,
      collectedAt: _now(),
    );
  }

  // --- Monitoring ---

  @override
  Future<Monitoring> monitoring() async {
    await _delay(const Duration(milliseconds: 300));
    final grafana = _service('grafana').state.isUp;
    return Monitoring(
      // No browser URL on purpose: nothing listens at example.org.
      grafanaUrl: null,
      adminUrl: _adminUrl,
      grafanaHealthy: grafana,
      grafanaVersion: grafana ? '11.3.0' : null,
      collectedAt: _now(),
    );
  }

  @override
  Future<MetricsSnapshot> metrics() async {
    await _delay(const Duration(milliseconds: 500));
    final up = _services.where((s) => s.name.endsWith('exporter') || s.name == 'cadvisor' || s.name == 'prometheus').where((s) => s.state.isUp).length;
    return MetricsSnapshot(
      collectedAt: _now(),
      metrics: [
        Metric(name: 'Exporters up', value: '${up + 4}'),
        const Metric(name: 'Load (1m)', value: '0.42'),
        const Metric(name: 'RAM available', value: '2.9 GB'),
        const Metric(name: 'RAM total', value: '3.8 GB'),
        const Metric(name: 'Inbound', value: '1.8 MB', unit: '/s'),
        const Metric(name: 'Outbound', value: '2.1 MB', unit: '/s'),
        const Metric(name: 'Disk free', value: '31.4 GB'),
      ],
    );
  }

  @override
  Future<ChartsSnapshot> metricSeries() async {
    await _delay(const Duration(milliseconds: 500));
    final now = _now();
    const points = 61;
    // Smooth, deterministic shapes: a slow wave plus a faster ripple.
    List<SeriesPoint> wave(double base, double amp, double period, {double ripple = 0, double floor = 0}) => [
          for (var i = 0; i < points; i++)
            SeriesPoint(
              now.subtract(Duration(minutes: points - 1 - i)),
              math.max(
                floor,
                base +
                    amp * math.sin(i / period * 2 * math.pi) +
                    ripple * math.sin(i / 3.7 * 2 * math.pi),
              ),
            ),
        ];
    List<SeriesPoint> steps(int base, int amp, double period) => [
          for (final p in wave(base.toDouble(), amp.toDouble(), period))
            SeriesPoint(p.time, p.value.roundToDouble().clamp(0, 99)),
        ];
    const jobs = ['cadvisor', 'grafana', 'node', 'prometheus', 'singbox', 'wireguard', 'xray'];
    return ChartsSnapshot(
      collectedAt: now,
      series: [
        MetricSeries(key: 'cpu_percent', points: wave(28, 9, 40, ripple: 3, floor: 2)),
        MetricSeries(key: 'mem_percent', points: wave(62, 3, 55, ripple: 0.6)),
        MetricSeries(key: 'rx_bytes_per_s', points: wave(1.8e6, 0.7e6, 30, ripple: 1.5e5, floor: 1e5)),
        MetricSeries(key: 'tx_bytes_per_s', points: wave(2.1e6, 0.9e6, 30, ripple: 2e5, floor: 1e5)),
        MetricSeries(key: 'users_singbox', points: steps(4, 2, 35)),
        MetricSeries(key: 'users_xray', points: steps(2, 1, 25)),
        MetricSeries(key: 'users_wireguard', points: steps(2, 1, 45)),
        MetricSeries(key: 'users_amneziawg', points: steps(1, 1, 50)),
        MetricSeries(key: 'users_conduit', points: steps(6, 3, 20)),
        for (final job in jobs)
          MetricSeries(
            key: MoavCli.exporterHealthKey,
            label: job,
            points: [SeriesPoint(now, 1)],
          ),
      ],
    );
  }

  @override
  Future<ServerInfo> serverInfo() async {
    await _delay(const Duration(milliseconds: 400));
    const gb = 1024 * 1024 * 1024;
    return ServerInfo(
      collectedAt: _now(),
      host: const HostMetrics(
        cpuCount: 2,
        cpuUsage: 0.23,
        load1: 0.42,
        load5: 0.38,
        load15: 0.35,
        memTotalBytes: 4 * gb,
        memAvailableBytes: (2.9 * gb) ~/ 1,
        swapTotalBytes: gb,
        swapFreeBytes: gb,
        diskTotalBytes: 40 * gb,
        diskAvailableBytes: (31.4 * gb) ~/ 1,
        uptime: Duration(days: 3, hours: 4, minutes: 12),
      ),
      version: VersionInfo(
        moavVersion: _version,
        branch: 'main',
        commit: _version == latestVersion ? 'f4e5d6c' : 'a1b2c3d',
        components: const [
          ComponentVersion(name: 'sing-box', version: '1.12.4', source: 'docker image'),
          ComponentVersion(name: 'xray', version: '25.9.11', source: 'docker image'),
          ComponentVersion(name: 'wireguard', version: '1.0.20250521', source: 'kernel module'),
          ComponentVersion(name: 'wstunnel', version: '10.4.3', source: 'docker image'),
          ComponentVersion(name: 'amneziawg', version: '1.0.20250706', source: 'docker image'),
          ComponentVersion(name: 'trusttunnel', version: '0.9.2', source: 'docker image'),
          ComponentVersion(name: 'telemt', version: '2.1.0', source: 'docker image'),
          ComponentVersion(name: 'dnstt', version: '1.20240513', source: 'docker image'),
          ComponentVersion(name: 'slipstream', version: '0.4.1', source: 'docker image'),
          ComponentVersion(name: 'prometheus', version: '3.6.0', source: 'docker image'),
          ComponentVersion(name: 'grafana', version: '11.3.0', source: 'docker image'),
        ],
      ),
    );
  }

  // --- Self-update ---

  @override
  Future<UpdateCheck> checkForUpdates() async {
    await _delay(const Duration(milliseconds: 800));
    final upToDate = _version == latestVersion;
    return UpdateCheck(
      updateAvailable: !upToDate,
      checkedAt: _now(),
      currentVersion: _version,
      latestVersion: latestVersion,
      message: upToDate ? 'Up to date (v$_version)' : 'Update available: v$latestVersion',
    );
  }

  static const updateStepsAt = [
    Duration.zero,
    Duration(milliseconds: 1200),
    Duration(milliseconds: 5500),
  ];
  static const updateDoneAt = Duration(seconds: 7);

  List<_Line> get _updateLines => [
        (updateStepsAt[0], '[moav-deploy] step 1/3: Preflight'),
        (updateStepsAt[0], 'MoaV v$installedVersion at /opt/moav (branch main, a1b2c3d)'),
        (updateStepsAt[1], ''),
        (updateStepsAt[1], '[moav-deploy] step 2/3: Run moav update'),
        (const Duration(milliseconds: 1400), 'Fetching origin...'),
        (const Duration(milliseconds: 2600), 'Updating a1b2c3d..f4e5d6c'),
        (const Duration(milliseconds: 3400), 'Fast-forward: 14 files changed, 212 insertions(+), 40 deletions(-)'),
        (const Duration(milliseconds: 4200), 'Post-update checks: .env has every variable from .env.example'),
        (updateStepsAt[2], ''),
        (updateStepsAt[2], '[moav-deploy] step 3/3: Report'),
        (updateStepsAt[2], 'Updated to v$latestVersion.'),
        (const Duration(milliseconds: 5700), 'Services were not restarted. Apply any rebuild/restart steps listed above when convenient.'),
        (updateDoneAt, ''),
        (updateDoneAt, '[moav-deploy] exit=0'),
      ];

  @override
  Future<void> startUpdate() async {
    await _delay(const Duration(milliseconds: 200));
    final started = _updateStartedAt;
    // Re-attach to a job that is still running, like the real one.
    if (started != null && _now().difference(started) < updateDoneAt) return;
    _updateStartedAt = _now();
  }

  @override
  Future<InstallStatus?> updateStatus() async {
    await _delay(const Duration(milliseconds: 100));
    final started = _updateStartedAt;
    if (started == null) return null;
    final elapsed = _now().difference(started);
    final lines = [
      for (final (at, text) in _updateLines)
        if (at <= elapsed) text,
    ];
    var step = 0;
    for (var i = 0; i < updateStepsAt.length; i++) {
      if (elapsed >= updateStepsAt[i]) step = i + 1;
    }
    if (elapsed >= updateDoneAt) {
      _version = latestVersion;
      return InstallStatus(
        phase: InstallPhase.succeeded,
        logTail: lines,
        progress: 1,
        message: 'Update finished',
        step: 3,
        totalSteps: 3,
      );
    }
    return InstallStatus(
      phase: InstallPhase.running,
      logTail: lines,
      progress: step / 3,
      message: const ['Preflight', 'Run moav update', 'Report'][step - 1],
      step: step,
      totalSteps: 3,
    );
  }

  // --- Web UIs: nothing listens behind the demo ---

  @override
  Future<AdminPanelAccess> adminPanelAccess() async => AdminPanelAccess(
        port: 9443,
        enabled: _flags['ENABLE_ADMIN_UI'] != 'false',
      );

  @override
  Future<GrafanaAccess> grafanaAccess() async => GrafanaAccess(
        port: 9444,
        enabled: _flags['ENABLE_MONITORING'] != 'false',
      );

  @override
  Future<ServerTunnel> openTunnel(int remotePort) async {
    throw unavailable(remotePort == 9444 ? 'Grafana' : 'admin dashboard');
  }

  // --- Donate ---

  @override
  Future<DonateEnv> donateEnv() async {
    await _delay(const Duration(milliseconds: 250));
    return DonateEnv(
      mahsaNetKeyPresent: _mahsaNetKey,
      protocols: DonateCli.defaultProtocols,
      conduitEnabled: _flags['ENABLE_CONDUIT'] != 'false',
      snowflakeEnabled: _flags['ENABLE_SNOWFLAKE'] != 'false',
      collectedAt: _now(),
    );
  }

  @override
  Future<DonationStatus> donateStatus() async {
    await _delay(const Duration(milliseconds: 500));
    final conduit = _service('psiphon-conduit');
    final snowflake = _service('snowflake');
    return DonationStatus(
      collectedAt: _now(),
      mahsaNet: MahsaNetStats(
        configured: _mahsaNetKey,
        total: _mahsaNetKey ? _donated.length : null,
        active: _mahsaNetKey ? _donated.where((c) => c.active).length : null,
        inactive: _mahsaNetKey ? _donated.where((c) => !c.active).length : null,
      ),
      conduit: BandwidthDonation(
        enabled: _flags['ENABLE_CONDUIT'] != 'false',
        running: conduit.state.isUp,
        bandwidthMbps: 40,
        maxClients: 50,
        connected: conduit.state.isUp ? 7 : 0,
        uploaded: '12.4 GB',
        downloaded: '3.1 GB',
      ),
      snowflake: BandwidthDonation(
        enabled: _flags['ENABLE_SNOWFLAKE'] != 'false',
        running: snowflake.state.isUp,
        bandwidthMbps: 20,
        maxClients: 10,
        served: 1284,
        uploaded: '4.8 GB',
        downloaded: '1.2 GB',
      ),
    );
  }

  List<DonatedConfig> _donated = const [];

  @override
  Future<List<DonatedConfig>> donateList() async {
    await _delay(const Duration(milliseconds: 300));
    return List.unmodifiable(_donated);
  }

  @override
  Future<void> saveMahsaNetKey(String key, {OutputSink? onOutput}) async {
    void out(String line) => onOutput?.call('$line\n');
    out('Validating the key with MahsaNet ...');
    await _delay(const Duration(milliseconds: 700));
    if (key.trim().length < 8) {
      out('MahsaNet rejected the key.');
      throw const AppError(
        AppErrorKind.commandFailed,
        'MahsaNet rejected the key',
        hint: 'The demo accepts any key of 8 characters or more.',
      );
    }
    _mahsaNetKey = true;
    out('Key accepted. MAHSANET_API_KEY written to /opt/moav/.env (mode 0600).');
  }

  @override
  Future<DonateResult> donateConfigs({
    required int count,
    String prefix = DonateCli.defaultPrefix,
    bool force = false,
    OutputSink? onOutput,
  }) async {
    void out(String line) => onOutput?.call('$line\n');
    if (!_mahsaNetKey) {
      throw const AppError(
        AppErrorKind.commandFailed,
        'MAHSANET_API_KEY is not set',
        hint: 'Save a MahsaNet API key first.',
      );
    }
    final schemes = ['vless', 'hysteria2', 'trojan'];
    var created = 0;
    var donated = 0;
    for (var i = 1; i <= count; i++) {
      final name = '$prefix-${_donated.length + i}';
      out('Creating donate user $name ...');
      await _delay(const Duration(milliseconds: 400));
      if (!_users.any((u) => u.name == name)) {
        _users = [..._users, _user(name, _now())]..sort((a, b) => a.name.compareTo(b.name));
        created++;
      }
      for (final scheme in schemes) {
        _donated = [
          ..._donated,
          DonatedConfig(
            index: _donated.length + 1,
            scheme: scheme,
            active: true,
            healthPercent: 100,
          ),
        ];
        donated++;
      }
      out('  submitted ${schemes.length} configs to MahsaNet');
    }
    out('Done: $created users, $donated configs donated.');
    return DonateResult(usersCreated: created, donated: donated);
  }
}
