import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_services.dart';
import 'package:moav_deploy/features/deploy/deploy_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// Captures the [InstallSpec] the deploy form submits.
class _Controller extends StubMoavController {
  InstallSpec? installedSpec;

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    installedSpec = spec;
    return const InstallHandle(jobId: '1', logPath: '.moav-deploy/deploy.log');
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async =>
      const InstallStatus(phase: InstallPhase.succeeded, progress: 1);
}

Future<_Controller> _pump(WidgetTester tester) async {
  final c = _Controller();
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [
      secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
      moavControllerProvider(demoProfile.id).overrideWithValue(c),
    ],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: const DeployScreen(profile: demoProfile),
    ),
  ));
  await tester.pumpAndSettle();
  // Fill the only required field now, before the list scrolls it away.
  await tester.enterText(find.widgetWithText(TextField, 'Admin dashboard password'),
      'secret-but-long');
  await tester.pumpAndSettle();
  return c;
}

/// Scrolls the form until [f] is built; negative [delta] scrolls back up.
Future<void> _show(WidgetTester tester, Finder f, {double delta = 150}) async {
  await tester.scrollUntilVisible(f, delta, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String profile) async {
  final tile = find.byKey(ValueKey('profile-$profile'));
  await _show(tester, tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester) async {
  await _show(tester, find.text('Start install'));
  await tester.tap(find.text('Start install'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every profile is listed; the default set is pre-selected', (tester) async {
    await _pump(tester);
    for (final p in MoavProfiles.all) {
      final tile = find.byKey(ValueKey('profile-${p.name}'));
      await _show(tester, tile);
      expect(tester.widget<CheckboxListTile>(tile).value, p.recommended, reason: p.name);
    }
    expect(find.text('OPT-IN'), findsNWidgets(2));
  });

  testWidgets('an untouched form installs the default profiles', (tester) async {
    final c = await _pump(tester);
    await _start(tester);
    expect(c.installedSpec, isNotNull);
    expect(c.installedSpec!.profiles, MoavProfiles.defaults);
  });

  testWidgets('deselecting and selecting profiles reaches the install spec in catalog order',
      (tester) async {
    final c = await _pump(tester);
    await _toggle(tester, 'telegram');
    await _toggle(tester, 'monitoring');
    await _start(tester);

    final profiles = c.installedSpec!.profiles;
    expect(profiles, isNot(contains('telegram')));
    expect(profiles, contains('monitoring'));
    expect(profiles.last, 'monitoring');
    expect(profiles.first, 'proxy');
    expect(profiles.length, MoavProfiles.defaults.length);
  });

  testWidgets('an empty selection blocks the install until reset', (tester) async {
    final c = await _pump(tester);
    for (final p in MoavProfiles.defaults) {
      await _toggle(tester, p);
    }
    expect(find.text('Select at least one service.'), findsOneWidget);
    await _start(tester);
    expect(c.installedSpec, isNull);

    await _show(tester, find.text('Reset to default'), delta: -150);
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(find.text('Select at least one service.'), findsNothing);
    await _start(tester);
    expect(c.installedSpec!.profiles, MoavProfiles.defaults);
  });
}
