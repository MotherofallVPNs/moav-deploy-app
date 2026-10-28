import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/activity/activity_screen.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';
import 'package:moav_deploy/widgets/moav_app_bar.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// The activity tracker behind the app-bar indicator: operation phases,
/// bounded and scrubbed logs, cached fetches registering themselves, and
/// the indicator reflecting what is in flight.
class _GatedStatus extends StubMoavController {
  final pending = <Completer<ServiceStatusReport>>[];

  @override
  Future<ServiceStatusReport> status() {
    final c = Completer<ServiceStatusReport>();
    pending.add(c);
    return c.future;
  }
}

ServiceStatusReport _report() => ServiceStatusReport(
      collectedAt: DateTime(2026),
      services: const [ServiceStatus(name: 'sing-box', state: ServiceState.running)],
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('ActivityNotifier', () {
    late ProviderContainer container;
    late ActivityNotifier n;
    ActivityState state() => container.read(activityProvider);

    setUp(() {
      container = ProviderContainer(retry: noProviderRetry);
      addTearDown(container.dispose);
      n = container.read(activityProvider.notifier);
    });

    test('phases: newest first, current prefers the newest running one', () {
      final a = n.begin('A · s');
      final b = n.begin('B · s');
      expect(state().operations.map((o) => o.label), ['B · s', 'A · s']);
      expect(state().busy, isTrue);
      expect(state().runningCount, 2);
      expect(state().current!.id, b.id);

      b.finish();
      expect(state().current!.id, a.id, reason: 'A is still running');
      final doneB = state().byId(b.id)!;
      expect(doneB.phase, OperationPhase.done);
      expect(doneB.running, isFalse);
      expect(doneB.endedAt, isNotNull);
      expect(doneB.elapsed().isNegative, isFalse);

      a.fail('boom');
      expect(state().busy, isFalse);
      expect(state().runningCount, 0);
      expect(state().current!.id, b.id, reason: 'nothing running: the latest');
      expect(state().byId(a.id)!.phase, OperationPhase.failed);
      expect(state().byId(a.id)!.error, 'boom');

      // Ending twice is a no-op: a failed operation never becomes done.
      a.finish();
      a.detach();
      expect(state().byId(a.id)!.phase, OperationPhase.failed);
      expect(state().byId(a.id)!.lines, isEmpty);

      final c = n.begin('C');
      c.detach();
      final det = state().byId(c.id)!;
      expect(det.phase, OperationPhase.detached);
      expect(det.endedAt, isNotNull);
      expect(det.lines.single, contains('continues on the server'));
      expect(state().byId(999), isNull);
    });

    test('only the newest ${ActivityNotifier.keep} operations are kept', () {
      for (var i = 0; i < ActivityNotifier.keep + 5; i++) {
        n.begin('op $i');
      }
      expect(state().operations, hasLength(ActivityNotifier.keep));
      expect(state().operations.first.label, 'op ${ActivityNotifier.keep + 4}');
      expect(state().operations.last.label, 'op 5');
    });

    test('log strips colour, drops trailing blanks, scrubs secrets', () {
      final op = n.begin('x');
      op.log('\x1b[0;32m✓\x1b[0m done\n\n\n');
      expect(state().current!.lines, ['✓ done']);
      op.log('vless://uuid@h:443#tag\nnext');
      expect(state().current!.lines, ['✓ done', '[redacted vless link]', 'next']);
      op.log('');
      op.log('\n\n');
      expect(state().current!.lines, hasLength(3));
      op.setLog(['a', 'ADMIN_PASSWORD=hunter2', '-----BEGIN OPENSSH PRIVATE KEY-----']);
      expect(state().current!.lines,
          ['a', 'ADMIN_PASSWORD=[redacted]', '[redacted private key]']);
    });

    test('run returns the body value and ends the entry', () async {
      final v = await n.run('calc', (op) async {
        op.log('working');
        return 42;
      });
      expect(v, 42);
      expect(state().current!.phase, OperationPhase.done);
      expect(state().current!.lines, ['working']);
    });

    test('handles stay safe after the container is disposed', () {
      final c = ProviderContainer(retry: noProviderRetry);
      final op = c.read(activityProvider.notifier).begin('late');
      c.dispose();
      op.log('x');
      op.setLog(['y']);
      op.finish();
      op.fail('z');
      op.detach();
    });
  });

  group('cached fetches register as operations', () {
    late _GatedStatus controller;
    late ProviderContainer container;
    const id = 's1';

    setUp(() {
      controller = _GatedStatus();
      container = ProviderContainer(
        retry: noProviderRetry,
        overrides: [
          moavControllerProvider(id).overrideWithValue(controller),
          secureCredStoreProvider.overrideWithValue(
              MemoryCredStore()..profiles = [demoProfile]),
        ],
      );
      addTearDown(container.dispose);
      container.listen(statusProvider(id), (_, _) {});
    });

    test('running while the fetch is pending, done when it lands', () async {
      await _settle();
      final a = container.read(activityProvider);
      expect(a.busy, isTrue);
      expect(a.current!.label, startsWith('moav status · '));
      controller.pending.single.complete(_report());
      await _settle();
      expect(container.read(activityProvider).busy, isFalse);
      expect(container.read(activityProvider).current!.phase, OperationPhase.done);
    });

    test('a failed fetch fails the entry with the error summary', () async {
      await _settle();
      controller.pending.single.completeError(TimeoutException('slow'));
      await _settle();
      final op = container.read(activityProvider).current!;
      expect(op.phase, OperationPhase.failed);
      expect(op.error, startsWith('The server did not respond in time.'));
      // A refresh opens a second entry rather than reviving the first.
      final again = container.read(statusProvider(id).notifier).refresh();
      await _settle();
      expect(container.read(activityProvider).operations, hasLength(2));
      controller.pending.last.complete(_report());
      await again;
    });
  });

  group('ActivityIndicatorButton', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      final container = ProviderContainer(retry: noProviderRetry);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: moavDarkTheme(),
          home: const Scaffold(appBar: MoavAppBar(title: Text('Tab'))),
        ),
      ));
      return container;
    }

    testWidgets('spins while operations run and counts them in the tooltip',
        (tester) async {
      final container = await pump(tester);
      expect(find.byKey(const ValueKey('activity-idle')), findsOneWidget);
      expect(find.byTooltip('Activity'), findsOneWidget);

      final n = container.read(activityProvider.notifier);
      final a = n.begin('Stop sing-box · Demo');
      await tester.pump();
      expect(find.byKey(const ValueKey('activity-busy')), findsOneWidget);
      expect(find.byTooltip('1 operation running'), findsOneWidget);

      final b = n.begin('moav status · Demo');
      await tester.pump();
      expect(find.byTooltip('2 operations running'), findsOneWidget);

      a.finish();
      await tester.pump();
      expect(find.byTooltip('1 operation running'), findsOneWidget);

      b.fail('nope');
      await tester.pump();
      expect(find.byKey(const ValueKey('activity-idle')), findsOneWidget);
      expect(find.byTooltip('Activity'), findsOneWidget);
    });

    testWidgets('tapping opens the panel on the current operation',
        (tester) async {
      final container = await pump(tester);
      final n = container.read(activityProvider.notifier);
      n.begin('Restart all services · Demo').log('restarting...');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('activity-busy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(find.text('Restart all services · Demo'), findsAtLeastNWidgets(1));
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('restarting...'), findsOneWidget);
      // The panel's own app bar carries no indicator.
      final bar = tester.widget<MoavAppBar>(find.descendant(
        of: find.byType(ActivityScreen),
        matching: find.byType(MoavAppBar),
      ));
      expect(bar.showActivity, isFalse);
    });

    testWidgets('with nothing ever run the panel says so', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('activity-idle')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing running'), findsOneWidget);
    });
  });
}
