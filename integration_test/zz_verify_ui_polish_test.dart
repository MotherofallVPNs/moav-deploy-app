// Temporary on-device verification for the UI polish PR. Not committed.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/bundle_zip.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../test/support/memory_cred_store.dart';

const _host = String.fromEnvironment('MOAV_TEST_HOST');
const _user = String.fromEnvironment('MOAV_TEST_USER', defaultValue: 'root');
const _keyB64 = String.fromEnvironment('MOAV_TEST_SSH_KEY_B64');
const _platformTag = String.fromEnvironment('VERIFY_TAG', defaultValue: 'x');

const demo = ServerProfile(
  id: 'demo',
  label: 'Demo server',
  host: _host,
  port: 22,
  username: _user,
  authMethod: SshAuthMethod.generatedKey,
);

class _Factory extends MoavControllerFactory {
  _Factory(this.c) : super(secretResolver: (_) async => null);
  final SshMoavController c;
  @override
  SshMoavController forServer(ServerProfile profile) => c;
}

Future<void> _checkpoint(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // ignore: avoid_print
  print('CHECKPOINT $name');
  final end = DateTime.now().add(const Duration(seconds: 7));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _wait(WidgetTester tester, Finder f,
    {Duration timeout = const Duration(minutes: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timeout $f');
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ui polish on device', (tester) async {
    final store = MemoryCredStore()
      ..profiles = [demo]
      ..secrets['demo'] = utf8.decode(base64Decode(_keyB64));
    final ctrl = SshMoavController(
        profile: demo, secretResolver: (_) async => store.secrets['demo']);
    final name =
        'zzmoavdeploytest$_platformTag${DateTime.now().millisecondsSinceEpoch % 10000}';
    // ignore: avoid_print
    print('THROWAWAY $name');
    await ctrl.addUser(name);
    try {
      await tester.pumpWidget(ProviderScope(
        retry: noProviderRetry,
        overrides: [
          secureCredStoreProvider.overrideWithValue(store),
          moavControllerFactoryProvider.overrideWithValue(_Factory(ctrl)),
        ],
        child: const MoavDeployApp(lockEnabled: false),
      ));
      await _wait(tester, find.text('Demo server'));

      await tester.tap(find.byTooltip('Menu'));
      await _checkpoint(tester, 'menu');
      expect(find.byTooltip('GitHub'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Demo server'));
      await _checkpoint(tester, 'hub-top');
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await _checkpoint(tester, 'hub-bottom');
      expect(find.text('Admin dashboard'), findsNothing);
      await tester.drag(find.byType(ListView).last, const Offset(0, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Users'));
      await _wait(tester, find.byIcon(Icons.person_remove_outlined));
      await tester.scrollUntilVisible(find.text(name), 400,
          scrollable: find
              .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await _wait(tester, find.text('Share .zip'));
      await _checkpoint(tester, 'detail');

      var sw = Stopwatch()..start();
      final server = await ctrl.getBundleArchive(name);
      // ignore: avoid_print
      print('TIMING direct archive ${sw.elapsedMilliseconds} ms');
      sw = Stopwatch()..start();
      final bundle = await ctrl.getBundle(name);
      // ignore: avoid_print
      print('TIMING direct bundle ${sw.elapsedMilliseconds} ms');
      final client = encodeBundleZip(bundle);
      String names(List<int> z) =>
          ZipDecoder().decodeBytes(z).files.map((f) => f.name).join(',');
      // ignore: avoid_print
      print('SERVERZIP ${server?.length} bytes: ${server == null ? 'null' : names(server)}');
      // ignore: avoid_print
      print('CLIENTZIP ${client.length} bytes: ${names(client)}');

      await tester.tap(find.text('Download connection bundle'));
      await _wait(tester, find.byType(QrImageView));
      await _checkpoint(tester, 'bundle');
      sw = Stopwatch()..start();
      await tester.tap(find.byTooltip('Share .zip'));
      await tester.pump(const Duration(milliseconds: 300));
      final busy = find.text('Preparing the bundle zip…');
      final end = DateTime.now().add(const Duration(seconds: 120));
      while (busy.evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      // ignore: avoid_print
      print('TIMING in-app share ready after ${sw.elapsedMilliseconds} ms, busy still shown: ${busy.evaluate().isNotEmpty}');
      await tester.pump(const Duration(seconds: 2));
      await _checkpoint(tester, 'share-sheet');
    } finally {
      await ctrl.removeUser(name);
      // ignore: avoid_print
      print('REMOVED $name');
    }
  });
}
