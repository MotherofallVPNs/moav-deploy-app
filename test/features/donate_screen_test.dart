import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/donate.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/donate/donate_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_log.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/memory_cred_store.dart';

const secretKey = 'mk_live_WIDGET_SECRET_987654321';

/// A server whose `.env` state the test flips; records what the screen asks
/// the controller to do and plays back the `moav donate setup` output.
class _Controller implements MoavController {
  _Controller({required this.keyPresent});

  bool keyPresent;
  final savedKeys = <String>[];
  final donateCalls = <(int, String)>[];

  @override
  Future<DonateEnv> donateEnv() async => DonateEnv(
        mahsaNetKeyPresent: keyPresent,
        protocols: const ['reality', 'hysteria2'],
        pool: 'mahsa',
        collectedAt: DateTime(2026),
      );

  @override
  Future<DonationStatus> donateStatus() async => DonationStatus(
        mahsaNet: keyPresent
            ? const MahsaNetStats(configured: true, total: 12, active: 11, inactive: 1)
            : const MahsaNetStats(configured: false),
        conduit: const BandwidthDonation(
          enabled: true,
          running: true,
          bandwidthMbps: 100,
          maxClients: 200,
          connected: 37,
          uploaded: '41.2 GB',
          downloaded: '118.6 GB',
        ),
        snowflake: const BandwidthDonation(enabled: false, running: false),
        collectedAt: DateTime(2026),
      );

  @override
  Future<List<DonatedConfig>> donateList() async => const [
        DonatedConfig(index: 1, scheme: 'vless', active: true, healthPercent: 100, used: 33),
        DonatedConfig(index: 2, scheme: 'hysteria2', active: false, used: 0),
      ];

  @override
  Future<void> saveMahsaNetKey(String key, {OutputSink? onOutput}) async {
    savedKeys.add(key);
    onOutput?.call('  API Key: ℹ Validating API key...\n✓ API key saved to .env\n');
    keyPresent = true;
  }

  @override
  Future<DonateResult> donateConfigs({
    required int count,
    String prefix = DonateCli.defaultPrefix,
    bool force = false,
    OutputSink? onOutput,
  }) async {
    donateCalls.add((count, prefix));
    onOutput?.call('✓ Generated $count user(s)\n');
    return DonateResult(usersCreated: count, donated: count * 2);
  }

  @override
  Future<ServerInfo> serverInfo() async => ServerInfo(
        host: const HostMetrics(cpuCount: 2),
        version: const VersionInfo(moavVersion: '2.3.1'),
        collectedAt: DateTime(2026),
      );

  @override
  Future<InstallStatus?> updateStatus() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Factory extends MoavControllerFactory {
  _Factory(this.controller) : super(secretResolver: (_) async => null);

  final MoavController controller;

  @override
  MoavController forServer(ServerProfile profile) => controller;
}

const _profile = ServerProfile(
  id: 's1',
  label: 'Demo',
  host: 'demo.example.org',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.generatedKey,
);

MemoryCredStore _store() => MemoryCredStore()..profiles = [_profile];

/// Pumps the screen on its own on a tall surface so every section is laid
/// out (a `findsNothing` below is then meaningful), once the saved servers
/// have loaded (the controller provider looks the profile up by id).
Future<void> _pumpScreen(WidgetTester tester, _Controller c, {List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_screen(c, opened: opened));
  await tester.pumpAndSettle();
}

Widget _screen(_Controller c, {List<Uri>? opened}) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(_store()),
        moavControllerFactoryProvider.overrideWithValue(_Factory(c)),
      ],
      child: MaterialApp(
        theme: moavDarkTheme(),
        home: Consumer(
          builder: (_, ref, _) => ref.watch(serversProvider).hasValue
              ? DonateScreen(
                  profile: _profile,
                  openUrl: (u) async => opened?.add(u),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );

void main() {
  final logged = <String>[];
  setUp(() {
    logged.clear();
    AppLog.sink = logged.add;
  });
  tearDown(() => AppLog.sink = null);

  testWidgets('the server hub has a Donate entry that opens the screen',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(_store()),
        moavControllerFactoryProvider
            .overrideWithValue(_Factory(_Controller(keyPresent: true))),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();

    final tile = find.text('Donate');
    await tester.scrollUntilVisible(
      tile,
      120,
      scrollable: find
          .descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Conduit and Snowflake bandwidth, MahsaNet configs'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Give back'), findsOneWidget);
    expect(
      find.textContaining('MoaV can contribute bandwidth to Psiphon Conduit and Tor Snowflake'),
      findsOneWidget,
    );
    expect(find.text('Psiphon Conduit'), findsWidgets);
    expect(find.text('Tor Snowflake'), findsWidgets);
  });

  testWidgets('key missing: key form only; saving hands the key over once and never shows or logs it',
      (tester) async {
    final c = _Controller(keyPresent: false);
    await _pumpScreen(tester, c);

    expect(find.byKey(const ValueKey('mahsanet-key-field')), findsOneWidget);
    expect(find.text('key missing'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const ValueKey('donate-run')), findsNothing);
    expect(find.byKey(const ValueKey('donate-count')), findsNothing);
    expect(find.text('not configured'.toUpperCase()), findsOneWidget);

    // Save is disabled until something is typed.
    expect(
      tester.widget<GradientButton>(find.byKey(const ValueKey('mahsanet-save-key'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('mahsanet-key-field')), secretKey);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mahsanet-key-field'))).obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('mahsanet-save-key')));
    await tester.pumpAndSettle();

    expect(c.savedKeys, [secretKey]);
    // The field was cleared and the key appears nowhere on screen.
    expect(find.text(secretKey), findsNothing);
    expect(find.text('MahsaNet API key saved to the server'), findsOneWidget);

    // Nothing in the activity log or the app log carries it.
    final container = ProviderScope.containerOf(tester.element(find.byType(DonateScreen)));
    final ops = container.read(activityProvider).operations;
    expect(ops.map((o) => o.label), contains(contains('Save MahsaNet API key')));
    for (final op in ops) {
      expect(op.label, isNot(contains(secretKey)));
      expect(op.lines.join('\n'), isNot(contains(secretKey)));
    }
    expect(logged.join('\n'), isNot(contains(secretKey)));

    // .env was re-read: the server now reports the key, so the donate form shows.
    expect(find.byKey(const ValueKey('donate-run')), findsOneWidget);
    expect(find.byKey(const ValueKey('mahsanet-key-field')), findsNothing);
  });

  testWidgets('key present: donate form, confirm gate, right count and prefix',
      (tester) async {
    final c = _Controller(keyPresent: true);
    await _pumpScreen(tester, c);

    expect(find.byKey(const ValueKey('mahsanet-key-field')), findsNothing);
    expect(find.text('key set'.toUpperCase()), findsOneWidget);
    expect(find.text('connected'.toUpperCase()), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('used 33'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('donate-count')), '3');
    await tester.enterText(find.byKey(const ValueKey('donate-prefix')), 'donor');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('donate-run')));
    await tester.pumpAndSettle();

    expect(find.text('Donate 3 config sets?'), findsOneWidget);
    expect(find.textContaining('3 new users'), findsOneWidget);
    expect(find.textContaining('named donor01 onwards'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.donateCalls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('donate-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-donate')));
    await tester.pumpAndSettle();

    expect(c.donateCalls, [(3, 'donor')]);
    expect(find.text('3 users created, 6 configs donated'), findsOneWidget);
    expect(find.text('Last run: 3 users created, 6 configs donated'), findsOneWidget);
  });

  testWidgets('an out-of-range count disables the action', (tester) async {
    final c = _Controller(keyPresent: true);
    await _pumpScreen(tester, c);

    GradientButton run() => tester.widget<GradientButton>(find.byKey(const ValueKey('donate-run')));
    expect(run().onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('donate-count')), '0');
    await tester.pump();
    expect(run().onPressed, isNull);
    expect(find.text('Enter a number from 1 to 50'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('donate-count')), '51');
    await tester.pump();
    expect(run().onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('donate-count')), '50');
    await tester.pump();
    expect(run().onPressed, isNotNull);
    expect(c.donateCalls, isEmpty);
  });

  testWidgets('status cards and the MahsaNet dashboard link', (tester) async {
    final opened = <Uri>[];
    await _pumpScreen(tester, _Controller(keyPresent: true), opened: opened);

    expect(find.text('running'.toUpperCase()), findsOneWidget);
    expect(find.text('disabled'.toUpperCase()), findsOneWidget);
    expect(find.text('100 Mbps · 200 max clients'), findsOneWidget);
    expect(find.text('37 connected · 41.2 GB up / 118.6 GB down'), findsOneWidget);

    final button = find.byKey(const ValueKey('mahsanet-dashboard'));
    await tester.tap(button);
    await tester.pump();
    expect(opened, [Uri.parse('https://www.mahsaserver.com/login')]);
    expect(DonateCli.mahsaNetDashboardUrl, 'https://www.mahsaserver.com/login');
  });
}
