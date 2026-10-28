import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';

import '../support/fake_controller.dart';

/// `status()` answers from a queue of completers so tests control timing.
class _StatusController extends StubMoavController {
  final pending = <Completer<ServiceStatusReport>>[];
  int calls = 0;

  @override
  Future<ServiceStatusReport> status() {
    calls++;
    final c = Completer<ServiceStatusReport>();
    pending.add(c);
    return c.future;
  }
}

ServiceStatusReport report(int running) => ServiceStatusReport(
      collectedAt: DateTime(2026),
      services: [
        for (var i = 0; i < running; i++)
          ServiceStatus(name: 'svc$i', state: ServiceState.running),
      ],
    );

void main() {
  late _StatusController controller;
  late ProviderContainer container;
  const id = 's1';

  setUp(() {
    controller = _StatusController();
    container = ProviderContainer(
      retry: noProviderRetry,
      overrides: [moavControllerProvider(id).overrideWithValue(controller)],
    );
    addTearDown(container.dispose);
    // Keep the family member alive like a watching widget would.
    container.listen(statusProvider(id), (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('first watch fetches once; data and fetchedAt land together', () async {
    await settle();
    expect(controller.calls, 1);
    expect(container.read(statusProvider(id)).loading, isTrue);
    expect(container.read(statusProvider(id)).hasData, isFalse);

    controller.pending.single.complete(report(2));
    await settle();
    final s = container.read(statusProvider(id));
    expect(s.loading, isFalse);
    expect(s.data!.runningCount, 2);
    expect(s.fetchedAt, isNotNull);
    expect(s.error, isNull);
  });

  test('a failed refresh keeps the last result and records the cause', () async {
    await settle();
    controller.pending.single.complete(report(2));
    await settle();

    final refresh = container.read(statusProvider(id).notifier).refresh();
    expect(container.read(statusProvider(id)).refreshing, isTrue);
    controller.pending.last.completeError(TimeoutException('slow'));
    await refresh;

    final s = container.read(statusProvider(id));
    expect(s.data!.runningCount, 2);
    expect(s.loading, isFalse);
    expect(s.error!.kind, AppErrorKind.timeout);

    // The next success clears the error.
    final again = container.read(statusProvider(id).notifier).refresh();
    controller.pending.last.complete(report(3));
    await again;
    expect(container.read(statusProvider(id)).error, isNull);
    expect(container.read(statusProvider(id)).data!.runningCount, 3);
  });

  test('concurrent refreshes share one round trip', () async {
    await settle();
    final n = container.read(statusProvider(id).notifier);
    final a = n.refresh();
    final b = n.refresh();
    expect(controller.calls, 1);
    controller.pending.single.complete(report(1));
    await Future.wait([a, b]);
    expect(controller.calls, 1);

    // Once settled, a refresh really fetches again.
    final c = n.refresh();
    expect(controller.calls, 2);
    controller.pending.last.complete(report(1));
    await c;
  });

  test('refreshIfStale only fetches when the cache is old or missing', () async {
    await settle();
    controller.pending.single.complete(report(1));
    await settle();
    final n = container.read(statusProvider(id).notifier);
    final at = container.read(statusProvider(id)).fetchedAt!;

    await n.refreshIfStale(const Duration(minutes: 2), now: at.add(const Duration(seconds: 30)));
    expect(controller.calls, 1);

    final f = n.refreshIfStale(const Duration(minutes: 2), now: at.add(const Duration(minutes: 3)));
    expect(controller.calls, 2);
    controller.pending.last.complete(report(1));
    await f;
  });

  test('the cache outlives its watchers (no autoDispose)', () async {
    await settle();
    controller.pending.single.complete(report(4));
    await settle();
    // A fresh listener (a tab re-opened) sees the data without a fetch.
    container.listen(statusProvider(id), (_, _) {});
    await settle();
    expect(container.read(statusProvider(id)).data!.runningCount, 4);
    expect(controller.calls, 1);
  });

  test('FetchState.copyWith keeps data unless replaced', () {
    final s = FetchState<int>(data: 1, fetchedAt: DateTime(2026));
    final e = s.copyWith(error: const AppError(AppErrorKind.unknown, 'x'));
    expect(e.data, 1);
    expect(e.error, isNotNull);
    expect(e.copyWith(clearError: true).error, isNull);
    expect(s.copyWith(loading: true).refreshing, isTrue);
    expect(const FetchState<int>(loading: true).refreshing, isFalse);
  });
}
