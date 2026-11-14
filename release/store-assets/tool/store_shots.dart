// Store listing capture run, driven by capture.sh: walks the app through the
// built-in demo server and asks the host for a device screenshot per step.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../test/support/memory_cred_store.dart';

/// Host-side capture endpoint, see store_shots_driver.dart. The simulator
/// shares the host loopback; capture.sh sets up `adb reverse` for Android.
const _shotHost = '127.0.0.1';
const _shotPort = int.fromEnvironment('MOAV_SHOT_PORT', defaultValue: 45055);

// Two saved servers on documentation hosts so the list is not a single row.
// Nothing connects to them: the home screen only dials a server on tap.
const _frankfurt = ServerProfile(
  id: 'fra',
  label: 'Frankfurt',
  host: 'fra.example.net',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.generatedKey,
);
const _homeLab = ServerProfile(
  id: 'lab',
  label: 'Home lab',
  host: 'lab.example.org',
  port: 2222,
  username: 'admin',
  authMethod: SshAuthMethod.password,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'store listing shots',
    (tester) async {
      // In-memory store: the run never touches the keychain or keystore.
      final store = MemoryCredStore()
        ..profiles = [_frankfurt, _homeLab]
        ..secrets['fra'] = 'x'
        ..secrets['lab'] = 'x';

      await tester.pumpWidget(ProviderScope(
        retry: noProviderRetry,
        overrides: [secureCredStoreProvider.overrideWithValue(store)],
        child: const MoavDeployApp(lockEnabled: false),
      ));
      await _idle(tester);
      await _wait(tester, find.text('Frankfurt'));

      // Add server: the form plus the demo hint.
      await tester.tap(find.text('Add server'));
      await _wait(tester, find.byKey(const ValueKey('try-demo')));
      await _pumpFor(tester, const Duration(seconds: 6));
      await _shot(tester, '02-add-server');

      // Demo install: pre-filled form, a run in progress, the finished run.
      await tester.tap(find.byKey(const ValueKey('try-demo')));
      await _wait(tester, find.text('Start install'));
      await _shot(tester, '03-install-form');
      await tester.ensureVisible(find.text('Start install'));
      await _idle(tester);
      await tester.tap(find.text('Start install'));
      await _pumpFor(tester, const Duration(seconds: 13));
      await _shot(tester, '04-install-progress');
      await _wait(tester, find.text('Go to the server'));
      await _shot(tester, '05-install-done');

      // Server hub.
      await tester.tap(find.text('Go to the server'));
      await _wait(tester, find.textContaining('is installed'));
      await _shot(tester, '06-server-hub');

      // Users, one user's detail, the bundle with its QR codes.
      await tester.tap(find.text('Users'));
      await _wait(tester, find.text('alice'));
      await _shot(tester, '07-users');
      await tester.tap(find.text('alice'));
      await _wait(tester, find.text('Download connection bundle'));
      await _idle(tester);
      await _shot(tester, '08-user-detail');
      await tester.tap(find.text('Download connection bundle'));
      await _wait(tester, find.byType(QrImageView));
      await _shot(tester, '09-bundle-qr');
      await _back(tester, 3);

      // Operate: services, health, analytics, server info.
      await tester.tap(find.text('Services'));
      await _wait(tester, find.text('sing-box'));
      await _shot(tester, '10-services');
      for (final (tab, name) in [
        ('Health', '11-health'),
        ('Analytics', '12-analytics'),
        ('Server', '13-server-info'),
      ]) {
        await tester.tap(find.widgetWithText(Tab, tab));
        await _idle(tester);
        await _pumpFor(tester, const Duration(seconds: 3));
        await _shot(tester, name);
        if (tab == 'Analytics') {
          // Second analytics shot: the last-hour charts moved to the top.
          final from = tester.getTopLeft(find.text('HEADLINE METRICS')).dy;
          final to = tester.getTopLeft(find.text('LAST HOUR')).dy;
          await tester.drag(find.text('HEADLINE METRICS'), Offset(0, from - to));
          await _idle(tester);
          await _shot(tester, '12b-analytics-charts');
        }
      }
      await _back(tester, 1);

      // Give back: bandwidth and config donation.
      await tester.scrollUntilVisible(
        find.text('Donate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Donate'));
      await _wait(tester, find.text('Give back'));
      await _idle(tester);
      await _shot(tester, '14-give-back');
      await _back(tester, 2);

      // Home: the server list, the menu, the support sheet.
      await _wait(tester, find.text('Demo server'));
      await _shot(tester, '01-servers');
      await tester.tap(find.byTooltip('Menu'));
      await _wait(tester, find.text('Emergency wipe'));
      await _shot(tester, '15-menu');
      await tester.tap(find.text('Support us'));
      await _wait(tester, find.text('Support MoaV'));
      await _shot(tester, '16-support');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// Asks the host to grab the device screen, status bar included.
Future<void> _shot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _pumpFor(tester, const Duration(milliseconds: 600));
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: _shotHost,
      port: _shotPort,
      path: '/shot',
      queryParameters: {'name': name},
    ));
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw TestFailure('capture of $name failed: HTTP ${response.statusCode}');
    }
  } finally {
    client.close(force: true);
  }
}

/// Pumps real time; safe while a progress animation never settles.
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [f] matches, then until loading spinners are gone.
Future<void> _wait(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after $timeout waiting for $f');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _idle(tester);
}

/// Waits for route transitions and loading spinners to finish.
Future<void> _idle(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  var calm = 0;
  while (calm < 8 && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    final busy = find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        tester.binding.hasScheduledFrame;
    calm = busy ? 0 : calm + 1;
  }
}

Future<void> _back(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pageBack();
    await _idle(tester);
  }
}
