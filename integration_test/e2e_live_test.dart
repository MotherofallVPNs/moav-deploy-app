// Real end-to-end run against a disposable box, driven through the app UI
// on a simulator: add the server (password auth), run the headless install,
// check services and health, add a user, open the bundle and share its zip.
//
// Needs `--dart-define`s (see tool/e2e_live.sh): MOAV_TEST_HOST,
// MOAV_TEST_USER, MOAV_TEST_PORT and MOAV_TEST_PASSWORD_B64 (the SSH
// password, base64 so shell metacharacters survive the define). Optional:
// MOAV_TEST_ADMIN_PASSWORD (installer admin password, random by default),
// MOAV_TEST_DOMAIN (blank = domainless install), MOAV_TEST_E2E_DESELECT
// (profiles to untick on the Deploy form), MOAV_TEST_E2E_USER and
// MOAV_TEST_E2E_CLEANUP=true to revoke that user at the end.
//
// Per-step results, the install log tail and the shared zip (base64) are
// returned through `reportData`, which `flutter drive` writes to
// build/integration_response_data.json. Screenshots land in shots/.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/deploy/deploy_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/features/users/bundle_share.dart';
import 'package:moav_deploy/features/users/users_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../test/support/memory_cred_store.dart';

const _host = String.fromEnvironment('MOAV_TEST_HOST');
const _user = String.fromEnvironment('MOAV_TEST_USER', defaultValue: 'root');
const _port = int.fromEnvironment('MOAV_TEST_PORT', defaultValue: 22);
const _passwordB64 = String.fromEnvironment('MOAV_TEST_PASSWORD_B64');
const _adminPassword = String.fromEnvironment('MOAV_TEST_ADMIN_PASSWORD');
const _domain = String.fromEnvironment('MOAV_TEST_DOMAIN');
const _e2eUser = String.fromEnvironment('MOAV_TEST_E2E_USER');

/// Comma-separated profiles to untick on the Deploy form (optional; the
/// installer disables the certificate-dependent protocols itself on a
/// domainless box, so the default selection works without a domain).
const _deselect = String.fromEnvironment('MOAV_TEST_E2E_DESELECT');
const _cleanup = bool.fromEnvironment('MOAV_TEST_E2E_CLEANUP');

const _label = 'E2E box';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live e2e: add server, install, status, add user, share zip',
    (tester) async {
      expect(_host, isNotEmpty, reason: 'MOAV_TEST_HOST is required');
      expect(_passwordB64, isNotEmpty,
          reason: 'MOAV_TEST_PASSWORD_B64 is required');
      final sshPassword = utf8.decode(base64Decode(_passwordB64));
      final adminPassword =
          _adminPassword.isNotEmpty ? _adminPassword : _randomPassword();
      final user = _e2eUser.isNotEmpty
          ? _e2eUser
          : 'e2e${DateTime.now().millisecondsSinceEpoch % 100000}';

      final store = MemoryCredStore();
      final sharer = _CapturingSharer();
      final results = <String, Object?>{
        'host': _host,
        'user': user,
        'domain': _domain,
        'startedAt': DateTime.now().toIso8601String(),
      };
      void step(String name, String verdict, [Map<String, Object?>? extra]) {
        results[name] = {'result': verdict, ...?extra};
        debugPrint('[e2e] $name: $verdict ${extra ?? ''}');
      }

      await tester.pumpWidget(ProviderScope(
        retry: noProviderRetry,
        overrides: [
          secureCredStoreProvider.overrideWithValue(store),
          bundleZipSharerProvider.overrideWithValue(sharer),
        ],
        child: const MoavDeployApp(lockEnabled: false),
      ));
      await _settleBounded(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MoavDeployApp)),
      );

      String? serverId;
      try {
        // 1. Add the server with password auth, through the form.
        await _wait(tester, find.text('Add server'));
        await tester.tap(find.text('Add server'));
        await _settleBounded(tester);
        await tester.enterText(
            find.widgetWithText(TextField, 'Label (optional)'), _label);
        await tester.enterText(find.widgetWithText(TextField, 'Host'), _host);
        await tester.enterText(
            find.widgetWithText(TextField, 'Port'), '$_port');
        await tester.enterText(
            find.widgetWithText(TextField, 'Username'), _user);
        await _blur(tester);
        await tester.tap(find.text('Password'));
        await _settleBounded(tester);
        await tester.enterText(
            find.widgetWithText(TextField, 'Password'), sshPassword);
        await _blur(tester);
        await _scrollTo(tester, find.text('Save server'));
        await _shot(binding, tester, '01-add-server-password');
        await tester.tap(find.text('Save server'));
        await _wait(tester, find.text(_label), timeout: const Duration(minutes: 2));
        final profiles = container.read(serversProvider).value ?? const [];
        final saved = profiles.firstWhere((p) => p.label == _label);
        serverId = saved.id;
        await _shot(binding, tester, '01b-servers-list');
        step('1-add-server', 'PASS', {
          'serverId': serverId,
          'authMethod': saved.authMethod.name,
        });

        // Open the server hub; the connection row pings the box.
        await tester.tap(find.text(_label));
        await _settleBounded(tester);
        await _wait(tester, find.text('Users'));
        await tester.tap(find.text('Check connection'));
        await _wait(tester, find.textContaining('Connected.'),
            timeout: const Duration(minutes: 2));
        await _shot(binding, tester, '01c-server-hub-connected');
        results['connectionRow'] = find
            .textContaining('Connected.')
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .firstOrNull;
        // The hub list is lazy; the Deploy tile sits below the fold.
        await _scrollTo(tester, find.text('Deploy'));

        // 2. Headless install, domainless unless MOAV_TEST_DOMAIN is set.
        await tester.tap(find.text('Deploy'));
        await _settleBounded(tester);
        await _wait(tester, find.text('Admin dashboard password'));
        if (_domain.isNotEmpty) {
          await tester.enterText(
              find.widgetWithText(TextField, 'Domain'), _domain);
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Admin dashboard password'),
          adminPassword,
        );
        await _blur(tester);
        await _shot(binding, tester, '02-deploy-form');
        final deselect = _deselect
            .split(',')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        for (final p in deselect) {
          final box = find.byKey(ValueKey('profile-$p'));
          await _scrollTo(tester, box);
          await tester.tap(box);
          await _settleBounded(tester);
        }
        if (deselect.isNotEmpty) {
          await _shot(binding, tester, '02a-deploy-services');
        }
        await _scrollTo(tester, find.text('Start install'));
        await tester.tap(find.text('Start install'));
        await _wait(tester, find.text('DEPLOY.LOG'),
            timeout: const Duration(minutes: 3));
        await _settle(tester, const Duration(seconds: 6));
        await _shot(binding, tester, '02b-install-started');
        // Poll the app's own deploy state until the job is terminal, with a
        // progress screenshot every five minutes.
        final installStart = DateTime.now();
        var lastShotMinute = 0;
        DeployState deploy;
        while (true) {
          deploy = container.read(deployProvider(serverId));
          final st = deploy.status;
          results['installLogTail'] = st?.logTail ?? const <String>[];
          if (st != null &&
              (st.isTerminal || st.phase == InstallPhase.unknown)) {
            break;
          }
          if (deploy.handle == null && !deploy.starting && deploy.error != null) {
            break;
          }
          final elapsed = DateTime.now().difference(installStart);
          if (elapsed > const Duration(minutes: 50)) {
            throw TestFailure('Install did not finish within 50 minutes');
          }
          if (elapsed.inMinutes >= lastShotMinute + 5) {
            lastShotMinute = elapsed.inMinutes;
            await _shot(
                binding, tester, '02c-install-progress-${lastShotMinute}m');
          }
          await tester.pump(const Duration(milliseconds: 500));
        }
        await _settle(tester, const Duration(seconds: 1));
        await _shot(binding, tester, '02d-install-final');
        final status = deploy.status;
        step(
          '2-install',
          status?.phase == InstallPhase.succeeded ? 'PASS' : 'FAIL',
          {
            'phase': status?.phase.name,
            'message': status?.message,
            'jobId': deploy.handle?.jobId,
            'startError': deploy.error?.summary,
            'deselected': deselect,
            'minutes': DateTime.now().difference(installStart).inMinutes,
          },
        );
        expect(status?.phase, InstallPhase.succeeded,
            reason: 'install did not succeed: ${status?.message}');
        await tester.pageBack();
        await _settleBounded(tester);

        // 3. Services table and doctor health.
        await tester.tap(find.text('Services'));
        await _wait(tester, find.text('services running'),
            timeout: const Duration(minutes: 3));
        await _settle(tester, const Duration(seconds: 2));
        await _shot(binding, tester, '03-services');
        final controller = container.read(moavControllerProvider(serverId));
        final report = await controller.status();
        final running = report.services
            .where((s) => s.state == ServiceState.running)
            .map((s) => s.name)
            .toList();
        final notRunning = report.services
            .where((s) => s.state != ServiceState.running)
            .map((s) => '${s.name}:${s.state.name}')
            .toList();
        step('3-services', running.isNotEmpty ? 'PASS' : 'FAIL', {
          'moavVersion': report.version,
          'running': running,
          'notRunning': notRunning,
          'defaultProfiles': report.defaultProfiles,
        });
        await tester.tap(find.text('Health'));
        await _wait(tester, find.text('CHECKS'),
            timeout: const Duration(minutes: 4));
        await _settle(tester, const Duration(seconds: 1));
        await _shot(binding, tester, '03b-health');
        final doctor = await controller.doctor();
        step('3-health', 'PASS', {
          'checks': [
            for (final c in doctor.checks) '${c.name}=${c.result.name}',
          ],
        });
        await tester.pageBack();
        await _settleBounded(tester);

        // 4. Add a user through the dialog. Re-enter the hub from the
        // servers list so its lazy list starts at the top again.
        await tester.pageBack();
        await _wait(tester, find.text('Add server'));
        await tester.tap(find.text(_label));
        await _wait(tester, find.text('Users'));
        await _shot(binding, tester, '04-hub-before-users');
        await tester.tap(find.text('Users'));
        await _wait(tester, find.text('Add user'),
            timeout: const Duration(minutes: 3));
        await _shot(binding, tester, '04-users-before');
        await tester.tap(find.text('Add user'));
        await _settleBounded(tester);
        await tester.enterText(
            find.widgetWithText(TextField, 'Username'), user);
        await _settleBounded(tester);
        await tester.tap(find.text('Add'));
        await _wait(tester, find.byType(QrImageView),
            timeout: const Duration(minutes: 8));
        await _blur(tester);
        final users = await controller.listUsers();
        final added = users.where((u) => u.name == user).toList();
        step('4-add-user', added.isNotEmpty ? 'PASS' : 'FAIL', {
          'listed': added.isNotEmpty,
          'bundleReady': added.firstOrNull?.bundleReady,
          'protocols': added.firstOrNull?.protocols,
        });

        // 5. Bundle: configs + QR rendered, then Share .zip.
        final bundle =
            container.read(bundleProvider((serverId: serverId, user: user)));
        final entries = bundle.value?.entries ?? const <BundleEntry>[];
        final qrCount = find.byType(QrImageView).evaluate().length;
        await _shot(binding, tester, '05-bundle-qr');
        await tester.tap(find.byTooltip('Share .zip'));
        await tester.pump();
        await _shot(binding, tester, '05b-share-zip-preparing');
        final end = DateTime.now().add(const Duration(minutes: 2));
        while (sharer.bytes == null && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await _settleBounded(tester);
        await _shot(binding, tester, '05c-share-zip-done');
        final zip = sharer.bytes;
        List<String> zipFiles = const [];
        if (zip != null) {
          zipFiles = ZipDecoder()
              .decodeBytes(zip)
              .files
              .map((f) => '${f.name} (${f.size} B)')
              .toList();
          results['zipBase64'] = base64Encode(zip);
        }
        final sub = entries
            .where((e) => e.protocol == 'subscription')
            .map((e) => e.content.trim())
            .firstOrNull;
        if (sub != null) results['subscriptionUrl'] = sub;
        results['bundleEntries'] = [
          for (final e in entries) '${e.fileName} (${e.content.length} chars)',
        ];
        step(
          '5-bundle-zip',
          zip != null && zip.isNotEmpty && qrCount > 0 ? 'PASS' : 'FAIL',
          {
            'entries': entries.length,
            'qrWidgets': qrCount,
            'zipFileName': sharer.fileName,
            'zipBytes': zip?.length,
            'zipFiles': zipFiles,
            'serverBuiltZip': zipFiles.any((f) => f.contains('.png')),
          },
        );
      } finally {
        results['finishedAt'] = DateTime.now().toIso8601String();
        try {
          await binding.takeScreenshot('zz-last-screen');
        } on Object catch (_) {}
        if (_cleanup && serverId != null) {
          try {
            final c = container.read(moavControllerProvider(serverId));
            if ((await c.listUsers()).any((u) => u.name == user)) {
              await c.removeUser(user);
              results['cleanup'] = 'removed $user';
            }
          } on Object catch (e) {
            results['cleanup'] = 'failed: $e';
          }
        }
        // takeScreenshot stores its PNGs in reportData; keep them.
        binding.reportData = {...?binding.reportData, ...results};
      }
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}

// --- Helpers ---

String _randomPassword() {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final r = math.Random.secure();
  return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await _blur(tester);
  await _settleBounded(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await binding.takeScreenshot(name);
}

Future<void> _blur(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _settleBounded(tester);
}

/// pumpAndSettle that gives up after a few seconds: an indeterminate
/// progress bar or a long snackbar must not stall the run.
Future<void> _settleBounded(
  WidgetTester tester, [
  Duration timeout = const Duration(seconds: 5),
]) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } on FlutterError {
    // Still animating; the screen is as settled as it gets.
  }
}

/// Pumps real time until [f] matches (network work has no scheduled frames).
Future<void> _wait(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after $timeout waiting for $f');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  await _settleBounded(tester);
}

Future<void> _settle(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    160,
    scrollable: find
        .descendant(
            of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first,
  );
  await _settleBounded(tester);
}

/// Stands in for the platform share sheet: keeps the zip the app built.
class _CapturingSharer extends BundleZipSharer {
  const _CapturingSharer();

  static Uint8List? _bytes;
  static String? _fileName;

  Uint8List? get bytes => _bytes;
  String? get fileName => _fileName;

  @override
  Future<void> share(
    String fileName,
    Uint8List bytes, {
    required String user,
    Rect? origin,
  }) async {
    _bytes = bytes;
    _fileName = fileName;
  }
}
