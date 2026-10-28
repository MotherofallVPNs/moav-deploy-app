import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/donate.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/features/activity/activity_provider.dart';
import 'package:moav_deploy/features/donate/donate_provider.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/features/users/users_provider.dart';
import 'package:moav_deploy/security/app_log.dart';

import '../support/fake_box.dart';
import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// The donate providers: the `.env` presence branch decides whether the
/// donated list is fetched, and the MahsaNet key passes through the
/// actions notifier without being kept, shown, logged or echoed back.
const _key = 'mk_live_PROVIDER_SECRET_42_abcdef';

class _Controller extends StubMoavController {
  bool keyPresent = false;
  int envCalls = 0;
  int statusCalls = 0;
  int listCalls = 0;
  int usersCalls = 0;
  final saved = <String>[];
  final donated = <(int, String)>[];
  Object? saveError;
  Object? listError;

  /// Pretend the CLI echoed the `.env` line (it does not; belt and braces).
  bool echoKey = false;

  /// Holds [saveMahsaNetKey] open until completed by the test.
  Completer<void>? gate;

  @override
  Future<DonateEnv> donateEnv() async {
    envCalls++;
    return DonateEnv(mahsaNetKeyPresent: keyPresent, collectedAt: DateTime(2026));
  }

  @override
  Future<DonationStatus> donateStatus() async {
    statusCalls++;
    return DonationStatus(
      mahsaNet: MahsaNetStats(configured: keyPresent, total: keyPresent ? 3 : null),
      conduit: const BandwidthDonation(enabled: true, running: true),
      snowflake: const BandwidthDonation(enabled: false, running: false),
      collectedAt: DateTime(2026),
    );
  }

  @override
  Future<List<DonatedConfig>> donateList() async {
    listCalls++;
    final e = listError;
    if (e != null) throw e;
    return const [DonatedConfig(index: 1, scheme: 'vless', active: true)];
  }

  @override
  Future<void> saveMahsaNetKey(String key, {OutputSink? onOutput}) async {
    final e = saveError;
    if (e != null) throw e;
    saved.add(key);
    onOutput?.call('ℹ Validating API key...\n');
    if (echoKey) onOutput?.call('MAHSANET_API_KEY=$key\n');
    await (gate?.future ?? Future<void>.value());
    onOutput?.call('✓ API key saved to .env\n');
    keyPresent = true;
  }

  @override
  Future<DonateResult> donateConfigs({
    required int count,
    String prefix = DonateCli.defaultPrefix,
    bool force = false,
    OutputSink? onOutput,
  }) async {
    donated.add((count, prefix));
    onOutput?.call('✓ Generated $count user(s)\n');
    return DonateResult(usersCreated: count, donated: count * 2, skipped: 1);
  }

  @override
  Future<List<MoavUser>> listUsers() async {
    usersCalls++;
    return const [];
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const id = 's1';
  late _Controller c;
  late ProviderContainer container;
  final logged = <String>[];
  DonateActionState state() => container.read(donateActionsProvider(id));
  DonateActionsNotifier actions() =>
      container.read(donateActionsProvider(id).notifier);
  /// The action's own entry; the refreshes it triggers are separate ones.
  Operation entry(String prefix) => container
      .read(activityProvider)
      .operations
      .firstWhere((o) => o.label.startsWith(prefix));

  setUp(() async {
    logged.clear();
    AppLog.sink = logged.add;
    c = _Controller();
    container = ProviderContainer(
      retry: noProviderRetry,
      overrides: [
        moavControllerProvider(id).overrideWithValue(c),
        secureCredStoreProvider.overrideWithValue(
            MemoryCredStore()..profiles = [demoProfile]),
      ],
    );
    addTearDown(container.dispose);
    container.listen(donateActionsProvider(id), (_, _) {});
    container.listen(donateEnvProvider(id), (_, _) {});
    container.listen(donateOverviewProvider(id), (_, _) {});
    await _settle();
  });
  tearDown(() => AppLog.sink = null);

  void expectNoKeyAnywhere() {
    for (final op in container.read(activityProvider).operations) {
      expect(op.label, isNot(contains(_key)));
      expect(op.error ?? '', isNot(contains(_key)));
      for (final l in op.lines) {
        expect(l, isNot(contains(_key)));
      }
    }
    for (final l in logged) {
      expect(l, isNot(contains(_key)));
    }
    expect(state().message ?? '', isNot(contains(_key)));
    expect(state().error?.summary ?? '', isNot(contains(_key)));
    expect(state().error?.detail ?? '', isNot(contains(_key)));
  }

  group('.env presence branch', () {
    test('without a key the donated list is never requested', () async {
      expect(c.envCalls, 1);
      expect(c.statusCalls, 1);
      expect(c.listCalls, 0);
      final overview = container.read(donateOverviewProvider(id)).data!;
      expect(overview.status.mahsaNet.configured, isFalse);
      expect(overview.configs, isEmpty);
      expect(container.read(donateEnvProvider(id)).data!.mahsaNetKeyPresent, isFalse);
    });

    test('with a key the list is fetched; a list failure is not an error',
        () async {
      c.keyPresent = true;
      await container.read(donateOverviewProvider(id).notifier).refresh();
      expect(c.listCalls, 1);
      expect(container.read(donateOverviewProvider(id)).data!.configs, hasLength(1));

      c.listError = StateError('MahsaNet API down');
      await container.read(donateOverviewProvider(id).notifier).refresh();
      final s = container.read(donateOverviewProvider(id));
      expect(s.error, isNull);
      expect(s.data!.configs, isEmpty);
      expect(s.data!.status.mahsaNet.total, 3);
    });
  });

  group('saveKey', () {
    test('hands the key over once, refreshes .env and status, keeps nothing',
        () async {
      c.echoKey = true;
      await actions().saveKey(_key);
      expect(c.saved, [_key]);
      expect(state().busy, isFalse);
      expect(state().message, 'MahsaNet API key saved to the server');
      expect(state().error, isNull);
      await _settle();
      expect(c.envCalls, 2);
      expect(c.statusCalls, 2);
      expect(container.read(donateEnvProvider(id)).data!.mahsaNetKeyPresent, isTrue);

      final op = entry('Save MahsaNet API key · ');
      expect(op.phase, OperationPhase.done);
      expect(op.lines, contains('✓ API key saved to .env'));
      expect(op.lines, contains('MAHSANET_API_KEY=[redacted]'));
      expectNoKeyAnywhere();
    });

    test('a rejected key: scrubbed error, nothing retains the key', () async {
      c.saveError = SshCommandException(
        DonateCli.setupMahsaNet,
        failed('MAHSANET_API_KEY=$_key\n✗ Invalid API key\n'),
      );
      await actions().saveKey(_key);
      final error = state().error!;
      expect(error.kind, AppErrorKind.commandFailed);
      expect(error.detail, contains('Invalid API key'));
      expect(error.detail, contains('MAHSANET_API_KEY=[redacted]'));
      expect(state().message, isNull);
      expect(entry('Save MahsaNet API key · ').phase, OperationPhase.failed);
      await _settle();
      expect(c.envCalls, 2, reason: '.env is re-read even after a failure');
      expectNoKeyAnywhere();
    });

    test('a donate during a save is dropped', () async {
      c.gate = Completer<void>();
      final save = actions().saveKey(_key);
      await _settle();
      expect(state().isRunning(DonateActionKind.saveKey), isTrue);
      await actions().donate(count: 2);
      expect(c.donated, isEmpty);
      c.gate!.complete();
      await save;
      expect(state().busy, isFalse);
    });
  });

  group('donate', () {
    test('passes count and prefix, summarises, invalidates the users list',
        () async {
      container.listen(usersProvider(id), (_, _) {});
      await _settle();
      expect(c.usersCalls, 1);

      await actions().donate(count: 3, prefix: 'give');
      expect(c.donated, [(3, 'give')]);
      expect(state().message, '3 users created, 6 configs donated, 1 skipped');
      expect(state().lastResult!.usersCreated, 3);
      final op = entry('Donate 3 config sets to MahsaNet · ');
      expect(op.phase, OperationPhase.done);
      expect(op.lines, ['✓ Generated 3 user(s)']);
      await _settle();
      expect(c.usersCalls, 2);
      expect(c.statusCalls, 2);

      // The last result survives a later save.
      await actions().saveKey(_key);
      expect(state().lastResult!.usersCreated, 3);
    });

    test('describe wording', () {
      expect(
        DonateActionsNotifier.describe(const DonateResult(usersCreated: 1, donated: 1)),
        '1 user created, 1 config donated',
      );
      expect(
        DonateActionsNotifier.describe(const DonateResult(
          usersCreated: 2,
          donated: 3,
          failed: 1,
          quotaHit: true,
        )),
        '2 users created, 3 configs donated, 1 failed. '
        'MahsaNet quota reached; run again later to resume.',
      );
    });
  });
}
