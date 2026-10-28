import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/moav_links.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/memory_cred_store.dart';

/// Device feedback batch 3: hamburger menu redesign and the admin
/// dashboard launched from the Server tab instead of the card menu.

class _Controller implements MoavController {
  @override
  Future<ServerInfo> serverInfo() async => ServerInfo(
        host: const HostMetrics(cpuCount: 2, load1: 0.2),
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

Widget _app(MemoryCredStore store) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        moavControllerFactoryProvider.overrideWithValue(_Factory(_Controller())),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

void main() {
  testWidgets('menu: keys, docs, support, one social row, wipe last',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('SSH keys'), findsOneWidget);
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('Support us'), findsOneWidget);
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

  testWidgets('admin dashboard is reachable from the Server tab',
      (tester) async {
    await tester.pumpWidget(_app(MemoryCredStore()..profiles = [_profile]));
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
