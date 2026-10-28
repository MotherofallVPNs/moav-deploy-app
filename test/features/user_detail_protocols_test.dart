import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/features/users/user_detail_screen.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';
import '../support/fixtures.dart';

/// The user detail header crosses the stores that list a user with the
/// server's `ENABLE_*` flags, so it names the protocols the bundle really
/// contains rather than the six store names.
class _Controller extends StubMoavController {
  _Controller({required this.flagsText, this.flagsError});

  final String flagsText;
  final Object? flagsError;
  int bundleCalls = 0;

  static const alice = MoavUser(
    name: 'alice',
    bundleReady: true,
    protocols: ['sing-box', 'wireguard'],
  );

  @override
  Future<List<MoavUser>> listUsers() async => const [alice];

  @override
  Future<ServiceFlags> serviceFlags() async {
    final e = flagsError;
    if (e != null) throw e;
    return MoavCli.parseServiceFlags(flagsText, now: DateTime(2026));
  }

  @override
  Future<Bundle> getBundle(String user) async {
    bundleCalls++;
    return Bundle(
      user: user,
      fetchedAt: DateTime(2026),
      entries: const [
        BundleEntry(
          protocol: 'subscription',
          fileName: 'subscription.txt',
          content: 'c3ViLWJsb2I=\n',
          qrPayload: 'c3ViLWJsb2I=',
        ),
        BundleEntry(protocol: 'reality', fileName: 'reality.txt', content: 'vless://a'),
      ],
    );
  }
}

/// Pills print their label in capitals.
Finder _pill(String title) => find.text(title.toUpperCase());

Future<_Controller> _pump(WidgetTester tester, _Controller c) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [moavControllerProvider(demoProfile.id).overrideWithValue(c)],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: const UserDetailScreen(profile: demoProfile, user: _Controller.alice),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('flags from .env trim the store protocols to what is enabled',
      (tester) async {
    // env_flags.txt: SNELL and ANYTLS off, SLIPSTREAM off, DNSTT/MASTERDNS on.
    await _pump(tester, _Controller(flagsText: fixture('env_flags.txt')));

    for (final title in [
      'VLESS Reality',
      'Trojan',
      'Hysteria2',
      'Shadowsocks',
      'WireGuard',
      'WireGuard over wstunnel',
      'dnstt',
      'MasterDNS',
    ]) {
      expect(_pill(title), findsOneWidget, reason: title);
    }
    for (final title in ['Snell', 'AnyTLS', 'Slipstream', 'VLESS XHTTP', 'AmneziaWG', 'GooseRelay']) {
      expect(_pill(title), findsNothing, reason: title);
    }
    expect(find.text('8 protocols enabled · 2 stores'), findsOneWidget);
    expect(_pill('bundle ready'), findsOneWidget);
    // The subscription blob comes from the bundle fetched once.
    expect(find.text('c3ViLWJsb2I='), findsOneWidget);
    expect(find.text('2 configs, 1 with a QR code.'), findsOneWidget);
  });

  testWidgets('unreadable flags fall back to upstream defaults', (tester) async {
    await _pump(
      tester,
      _Controller(flagsText: '', flagsError: StateError('.env missing')),
    );
    // Defaults: stock protocols on (Snell included), opt-ins off.
    expect(_pill('Snell'), findsOneWidget);
    expect(_pill('Slipstream'), findsOneWidget);
    expect(_pill('AnyTLS'), findsNothing);
    expect(_pill('GooseRelay'), findsNothing);
    expect(_pill('VLESS XHTTP'), findsNothing, reason: 'no xray store');
  });

  testWidgets('every flag off leaves an explicit empty state', (tester) async {
    final off = [
      for (final k in [
        'ENABLE_REALITY', 'ENABLE_TROJAN', 'ENABLE_HYSTERIA2', 'ENABLE_SS',
        'ENABLE_SNELL', 'ENABLE_WIREGUARD', 'ENABLE_DNSTT', 'ENABLE_SLIPSTREAM',
        'ENABLE_MASTERDNS', 'ENABLE_CDN', 'ENABLE_ANYTLS',
      ])
        '$k=false',
    ].join('\n');
    await _pump(tester, _Controller(flagsText: off));
    expect(find.text('No protocols enabled for this user'), findsOneWidget);
    expect(_pill('VLESS Reality'), findsNothing);
  });

  testWidgets('refresh re-reads users, flags and the bundle', (tester) async {
    final c = await _pump(tester, _Controller(flagsText: fixture('env_flags.txt')));
    expect(c.bundleCalls, 1);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(c.bundleCalls, 2);
    expect(_pill('VLESS Reality'), findsOneWidget);
  });
}
