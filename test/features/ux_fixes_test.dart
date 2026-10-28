import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/servers/add_server_form.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';
import 'package:moav_deploy/widgets/log_view.dart';
import 'package:moav_deploy/widgets/moav_app_bar.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// Device-feedback batch: auth icon, key persistence, no client test,
/// copyable logs, global activity indicator, "key" label, admin dashboard.

const _secret = 'hunter2-never-shown';

class _Controller extends StubMoavController {
  final log = <String>[];

  /// Holds [service] open until completed by the test.
  Completer<void>? serviceGate;
  AdminPanelAccess access =
      const AdminPanelAccess(port: 9443, password: _secret);
  FakeTunnel? tunnel;

  @override
  Future<ConnectionCheck> ping() async => const ConnectionCheck(
        reachable: true,
        moavInstalled: true,
        moavVersion: '2.3.1',
      );

  @override
  Future<void> service(ServiceAction action, {OutputSink? onOutput}) async {
    onOutput?.call('stopping ${action.service}\n');
    await (serviceGate?.future ?? Future<void>.value());
    onOutput?.call('${action.service} stopped\n');
    log.add('service ${action.kind.name} ${action.service}');
  }

  @override
  Future<ServiceStatusReport> status() async => ServiceStatusReport(
        collectedAt: DateTime(2026),
        services: const [
          ServiceStatus(name: 'sing-box', state: ServiceState.running),
        ],
      );

  @override
  Future<ServiceFlags> serviceFlags() async =>
      ServiceFlags(values: const {}, collectedAt: DateTime(2026));

  @override
  Future<InstallStatus?> updateStatus() async => null;

  @override
  Future<AdminPanelAccess> adminPanelAccess() async {
    log.add('admin access');
    return access;
  }

  @override
  Future<ServerTunnel> openTunnel(int remotePort) async {
    log.add('tunnel $remotePort');
    return tunnel = FakeTunnel(remotePort);
  }
}

/// Never unlocks, so the lock screen stays up.
class _LockedService extends AppLockService {
  @override
  Future<bool> canLock() async => true;

  @override
  Future<bool> authenticate({bool disguised = false}) async => false;
}

Widget _app(MemoryCredStore store, _Controller controller) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        moavControllerFactoryProvider.overrideWithValue(FakeControllerFactory(controller)),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

Future<void> _pumpFor(WidgetTester tester,
    [Duration d = const Duration(milliseconds: 600)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Home, then the server hub, then the "Admin dashboard" tile.
Future<void> _openAdminTile(WidgetTester tester) async {
  await tester.tap(find.text('Demo'));
  await tester.pumpAndSettle();
  final tile = find.text('Admin dashboard');
  await tester.scrollUntilVisible(tile, 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

List<String> _clipboardSpy(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  return copied;
}

void main() {
  group('1. auth screens use the MoaV mark', () {
    testWidgets('lock screen renders MoavMark and no FlutterLogo',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [appLockServiceProvider.overrideWithValue(_LockedService())],
        child: MaterialApp(
          theme: moavDarkTheme(),
          home: const AppLockGate(child: SizedBox()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Unlock failed'), findsOneWidget);
      expect(find.byType(FlutterLogo), findsNothing);
      expect(find.byType(MoavMark), findsOneWidget);
      final image = tester.widget<Image>(find.descendant(
        of: find.byType(MoavMark),
        matching: find.byType(Image),
      ));
      expect((image.image as AssetImage).assetName, MoavMark.asset);
    });

    testWidgets('onboarding renders MoavMark and no FlutterLogo',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: moavDarkTheme(),
        home: OnboardingScreen(onContinue: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterLogo), findsNothing);
      expect(find.byType(MoavMark), findsOneWidget);
    });

    test('the mark asset is bundled and declared', () {
      expect(File(MoavMark.asset).existsSync(), isTrue);
      expect(File('pubspec.yaml').readAsStringSync(), contains(MoavMark.asset));
    });
  });

  group('2. generated key is saved at once', () {
    test('generateKey writes the key to the keyring before the server exists',
        () async {
      final store = MemoryCredStore();
      final container = ProviderContainer(
        retry: noProviderRetry,
        overrides: [secureCredStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(addServerFormProvider, (_, _) {});
      addTearDown(sub.close);
      final form = container.read(addServerFormProvider.notifier);

      await form.generateKey();
      final state = container.read(addServerFormProvider);
      expect(state.generatedKey, isNotNull);
      expect(store.profiles, isEmpty, reason: 'the flow was not completed');
      expect(store.sshKeys, hasLength(1));
      final saved = store.sshKeys.single;
      expect(saved.id, state.generatedKeyId);
      expect(saved.label, 'MoaV device key');
      expect(saved.publicKey, startsWith('ssh-ed25519 '));
      expect(store.sshKeySecrets[saved.id],
          state.generatedKey!.privateKeyPem.trim());
      expect(state.notice, contains('saved'));

      // Regenerating replaces the unused key instead of piling up.
      await form.generateKey();
      expect(store.sshKeys, hasLength(1));
      expect(store.sshKeys.single.id, isNot(saved.id));
      expect(store.sshKeySecrets.keys, [store.sshKeys.single.id]);
    });

    test('a labelled form names the key after the server', () {
      expect(AddServerFormNotifier.generatedKeyLabel('  Frankfurt '),
          'Frankfurt key');
      expect(AddServerFormNotifier.generatedKeyLabel(''), 'MoaV device key');
    });
  });

  group('3. the per-protocol client test is gone', () {
    test('no source references remain', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        for (final needle in [
          'testUser',
          'TestMatrix',
          'ProtocolTest',
          'UserTestScreen',
          'userTestProvider',
          'moav test',
          'Run connection test',
        ]) {
          if (text.contains(needle)) offenders.add('${f.path}: $needle');
        }
      }
      expect(offenders, isEmpty);
      expect(File('lib/features/operate/user_test_screen.dart').existsSync(),
          isFalse);
    });
  });

  group('4. shared log view', () {
    testWidgets('scrolls, selects and copies every line', (tester) async {
      final copied = _clipboardSpy(tester);
      final lines = List.generate(200, (i) => 'line $i');
      await tester.pumpWidget(MaterialApp(
        theme: moavDarkTheme(),
        home: Scaffold(
          body: LogView(lines: lines, height: 160, title: 'deploy.log'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('DEPLOY.LOG'), findsOneWidget);
      expect(find.text('200 lines'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('line 199'), findsNothing, reason: 'not yet scrolled');

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(find.text('line 199'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('log-copy')));
      await tester.pumpAndSettle();
      expect(copied, [lines.join('\n')]);
      expect(find.text('Log copied'), findsOneWidget);
    });
  });

  group('5. global activity indicator', () {
    testWidgets('a service stop spins the indicator and streams its log',
        (tester) async {
      final store = MemoryCredStore()..profiles = [demoKeyProfile];
      final controller = _Controller()..serviceGate = Completer<void>();
      await tester.pumpWidget(_app(store, controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-idle')), findsOneWidget);

      await tester.tap(find.byTooltip('Actions for sing-box'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester);

      // In flight: the corner icon spins and the panel shows the stream.
      expect(find.byKey(const ValueKey('activity-busy')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-idle')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('activity-busy')));
      await _pumpFor(tester);
      expect(find.text('Stop sing-box · Demo'), findsAtLeastNWidgets(1));
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('stopping sing-box'), findsOneWidget);

      // Finished: Done pill, full log, and the usual confirmation snackbar.
      controller.serviceGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('sing-box stopped'), findsOneWidget);
      expect(find.text('Stop sing-box done'), findsOneWidget);
      expect(controller.log, contains('service stop sing-box'));

      // Back on the tab the corner icon is idle again.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-idle')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-busy')), findsNothing);
    });

    test('the tracker records phases and bounds the log', () async {
      final container = ProviderContainer(retry: noProviderRetry);
      addTearDown(container.dispose);
      final activity = container.read(activityProvider.notifier);
      expect(container.read(activityProvider).busy, isFalse);

      final op = activity.begin('Stop all · Demo');
      expect(container.read(activityProvider).busy, isTrue);
      op.log('a\nb\n');
      op.log('password=topsecret');
      op.finish();
      final done = container.read(activityProvider).current!;
      expect(done.phase, OperationPhase.done);
      expect(done.lines, ['a', 'b', 'password=[redacted]']);
      expect(container.read(activityProvider).busy, isFalse);

      await expectLater(
        activity.run('Boom', (_) async => throw StateError('nope')),
        throwsStateError,
      );
      final failed = container.read(activityProvider).current!;
      expect(failed.phase, OperationPhase.failed);
      expect(failed.error, 'nope');

      final big = activity.begin('big');
      big.setLog(List.generate(1000, (i) => '$i'));
      expect(container.read(activityProvider).current!.lines.length,
          ActivityNotifier.maxLines);
    });
  });

  group('6. server card label', () {
    testWidgets('a generated key reads "key", not "device key"',
        (tester) async {
      final store = MemoryCredStore()..profiles = [demoKeyProfile];
      await tester.pumpWidget(_app(store, _Controller()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo'));
      await tester.pumpAndSettle();
      expect(find.text('KEY'), findsOneWidget);
      expect(find.text('DEVICE KEY'), findsNothing);
    });
  });

  group('7. in-app admin dashboard', () {
    testWidgets('opens a tunnel to PORT_ADMIN and keeps the password private',
        (tester) async {
      final store = MemoryCredStore()..profiles = [demoKeyProfile];
      final controller = _Controller();
      await tester.pumpWidget(_app(store, controller));
      await tester.pumpAndSettle();

      // No longer in the server card menu (user management lives in the
      // Users tab); it is launched from the server hub and the Server tab.
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      expect(find.text('Admin dashboard'), findsNothing);
      expect(find.text('Users'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await _openAdminTile(tester);

      expect(controller.log, ['admin access', 'tunnel 9443']);
      expect(find.text('Admin dashboard preview is not available here'),
          findsOneWidget);
      expect(find.text('https://127.0.0.1:45000/ forwards to server port 9443'),
          findsOneWidget);
      expect(find.byTooltip('Open in browser'), findsOneWidget);

      // The password is in memory only: not on screen, not in the activity
      // log, not in the controller's description.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? '', isNot(contains(_secret)));
      }
      final element = tester.element(find.byType(MoavAppBar).last);
      final ops = ProviderScope.containerOf(element).read(activityProvider);
      expect(ops.current!.label, 'Admin dashboard · Demo');
      expect(ops.current!.phase, OperationPhase.done);
      expect(ops.current!.lines.join('\n'), isNot(contains(_secret)));
      expect(ops.current!.lines.join('\n'), contains('password read'));
      expect(controller.access.toString(), isNot(contains(_secret)));

      // Leaving the screen closes the tunnel.
      expect(controller.tunnel!.closed, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.tunnel!.closed, isTrue);
    });

    testWidgets('a disabled panel is reported without opening a tunnel',
        (tester) async {
      final store = MemoryCredStore()..profiles = [demoKeyProfile];
      final controller = _Controller()
        ..access = const AdminPanelAccess(port: 9443, enabled: false);
      await tester.pumpWidget(_app(store, controller));
      await tester.pumpAndSettle();
      await _openAdminTile(tester);
      expect(find.text('The admin dashboard is disabled on this server.'),
          findsOneWidget);
      expect(controller.log, ['admin access']);
      expect(controller.tunnel, isNull);
    });
  });
}
