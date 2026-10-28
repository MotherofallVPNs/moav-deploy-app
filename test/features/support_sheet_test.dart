import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_links.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/features/support/support_sheet.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

void main() {
  testWidgets('"Support us" opens the popup instead of a web page',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
        moavControllerFactoryProvider.overrideWithValue(
            FakeControllerFactory(StubMoavController())),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support us'));
    await tester.pumpAndSettle();

    expect(find.byType(SupportSheet), findsOneWidget);
    expect(find.text('Support MoaV'), findsOneWidget);
    expect(find.text('GitHub Sponsors'), findsOneWidget);
    expect(find.text('Buy Me a Coffee'), findsOneWidget);
    expect(find.text('More ways to support'), findsOneWidget);
  });

  testWidgets('each button opens its configured link', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      theme: moavDarkTheme(),
      home: Scaffold(body: SupportSheet(onOpen: (u) async => opened.add(u))),
    ));
    await tester.tap(find.text('GitHub Sponsors'));
    await tester.tap(find.text('Buy Me a Coffee'));
    await tester.tap(find.text('More ways to support'));
    await tester.pump();

    expect(opened, [
      MoavLinks.supportGithubSponsors,
      MoavLinks.supportBuymeacoffee,
      MoavLinks.supportMore,
    ]);
    // Handles confirmed by the owner in #53.
    expect(MoavLinks.supportGithubSponsorsUrl, 'https://github.com/sponsors/shayanb');
    expect(MoavLinks.supportBuymeacoffeeUrl, 'https://buymeacoffee.com/pangana');
    expect(MoavLinks.supportMoreUrl, 'https://moav.sh/docs/support/');
  });
}
