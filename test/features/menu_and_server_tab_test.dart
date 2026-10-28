import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/app_identity.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_links.dart';
import 'package:moav_deploy/features/about/about_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// Device feedback batch 3: hamburger menu redesign and the admin
/// dashboard launched from the Server tab instead of the card menu.

class _Controller extends StubMoavController {
  @override
  Future<ServerInfo> serverInfo() async => ServerInfo(
        host: const HostMetrics(cpuCount: 2, load1: 0.2),
        version: const VersionInfo(moavVersion: '2.3.1'),
        collectedAt: DateTime(2026),
      );

  @override
  Future<InstallStatus?> updateStatus() async => null;
}

Widget _app(MemoryCredStore store) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        moavControllerFactoryProvider.overrideWithValue(FakeControllerFactory(_Controller())),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

void main() {
  testWidgets('menu: keys, docs, support, about, one social row, wipe last',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('SSH keys'), findsOneWidget);
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('Support us'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.byTooltip('GitHub'), findsOneWidget);
    expect(find.byTooltip('X'), findsOneWidget);
    expect(find.byTooltip('Telegram'), findsOneWidget);
    expect(find.text('Emergency wipe'), findsOneWidget);
    // The old standalone rows are gone (folded into the above).
    expect(find.text('Website & docs'), findsNothing);
    expect(find.text('GitHub'), findsNothing);
    expect(find.text('Telegram'), findsNothing);
    expect(find.text('Admin dashboard'), findsNothing);

    // The social icons share one row, and the wipe sits below the divider.
    final gh = tester.getCenter(find.byTooltip('GitHub'));
    final x = tester.getCenter(find.byTooltip('X'));
    final tg = tester.getCenter(find.byTooltip('Telegram'));
    expect(gh.dy, x.dy);
    expect(x.dy, tg.dy);
    expect(gh.dx, lessThan(x.dx));
    expect(x.dx, lessThan(tg.dx));
    final about = tester.getCenter(find.text('About'));
    expect(tester.getCenter(find.text('Support us')).dy, lessThan(about.dy));
    expect(about.dy, lessThan(gh.dy));
    final wipe = tester.getCenter(find.text('Emergency wipe'));
    expect(wipe.dy, greaterThan(tg.dy));
    expect(find.byType(PopupMenuDivider), findsOneWidget);

    // Links are constants in one place; "Support us" opens a popup instead
    // of a URL (see support_sheet_test.dart).
    expect(MoavLinks.docs.toString(), 'https://moav.sh/docs');
    expect(MoavLinks.supportMoreUrl, 'https://moav.sh/docs/support/');
    expect(MoavLinks.github.toString(), 'https://github.com/MotherofallVPNs');
    expect(MoavLinks.x.toString(), 'https://x.com/motherofallvpns');
    expect(MoavLinks.telegram.toString(), 'https://t.me/motherofallvpns');
  });

  testWidgets('menu: About opens the About screen with the pubspec version',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'MoaV Deploy',
      packageName: 'org.motherofallvpns.moavdeploy',
      version: '0.2.7',
      buildNumber: '10',
      buildSignature: '',
    );
    // No Android side under test: the channel answers as an absent plugin,
    // which pumpAndSettle's fake clock would otherwise never see resolve.
    const channel = MethodChannel(AppSigning.channelName);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(_app(MemoryCredStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 0.2.7 (10)'), findsOneWidget);
    // No signing channel in the test binding: the screen says so, no crash.
    expect(find.text(AboutScreen.noFingerprint), findsOneWidget);
  });

  testWidgets('admin dashboard is reachable from the Server tab',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()..profiles = [demoKeyProfile]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server info'));
    await tester.pumpAndSettle();

    expect(find.text('MoaV v2.3.1'), findsOneWidget);
    final row = find.text('Admin dashboard');
    await tester.scrollUntilVisible(
      row,
      120,
      scrollable: find
          .descendant(
              of: find.byType(ListView).last, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(find.text('The MoaV web panel, through this SSH connection'),
        findsOneWidget);
  });
}
