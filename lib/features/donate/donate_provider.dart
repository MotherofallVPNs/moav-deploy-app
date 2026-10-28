import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../core/donate.dart';
import '../../core/donate_cli.dart';
import '../../core/moav_controller.dart';
import '../activity/activity_provider.dart';
import '../operate/operate_provider.dart';
import '../servers/servers_provider.dart';
import '../users/users_provider.dart';

/// Presence of the MahsaNet key and the donation settings from `.env`.
/// Fast, so the screen decides between the key form and the donate form
/// without waiting for the slow status fetch.
class DonateEnvNotifier extends CachedFetchNotifier<DonateEnv> {
  DonateEnvNotifier(super.serverId);

  @override
  Future<DonateEnv> fetch() => controller.donateEnv();

  @override
  String get activityLabel => '.env donation settings';
}

/// `moav donate status` plus, when MahsaNet is configured, `moav donate list`.
class DonateOverviewNotifier extends CachedFetchNotifier<DonateOverview> {
  DonateOverviewNotifier(super.serverId);

  @override
  Future<DonateOverview> fetch() async {
    final status = await controller.donateStatus();
    if (!status.mahsaNet.configured) return DonateOverview(status: status);
    try {
      return DonateOverview(
        status: status,
        configs: await controller.donateList(),
      );
    } on Object {
      // The list is a nicety; the status card already says when MahsaNet
      // could not be reached.
      return DonateOverview(status: status);
    }
  }

  @override
  String get activityLabel => 'moav donate status';
}

final donateEnvProvider = NotifierProvider.family<DonateEnvNotifier,
    FetchState<DonateEnv>, String>(DonateEnvNotifier.new);

final donateOverviewProvider = NotifierProvider.family<DonateOverviewNotifier,
    FetchState<DonateOverview>, String>(DonateOverviewNotifier.new);

enum DonateActionKind { saveKey, donate }

class DonateActionState {
  const DonateActionState({
    this.running,
    this.message,
    this.error,
    this.lastResult,
  });

  /// The action in flight, if any.
  final DonateActionKind? running;
  final String? message;

  /// Failure of the last action, with the command output as detail.
  final AppError? error;

  /// Summary of the most recent donate run on this screen.
  final DonateResult? lastResult;

  bool get busy => running != null;

  bool isRunning(DonateActionKind kind) => running == kind;
}

/// Serialises the two donate actions for one server and refreshes the
/// cached `.env` and status afterwards. The key passes straight through to
/// the controller: it is never kept in state, logged or echoed back.
class DonateActionsNotifier extends Notifier<DonateActionState> {
  DonateActionsNotifier(this.serverId);

  final String serverId;

  @override
  DonateActionState build() => const DonateActionState();

  MoavController get _controller => ref.read(moavControllerProvider(serverId));

  OperationHandle _begin(String label) => ref
      .read(activityProvider.notifier)
      .begin('$label · ${serverLabelOf(ref, serverId)}');

  /// `moav donate setup` with [key]; `.env` is re-read when it returns so
  /// the screen flips to the donate form on success.
  Future<void> saveKey(String key) async {
    if (state.busy) return;
    state = DonateActionState(
      running: DonateActionKind.saveKey,
      lastResult: state.lastResult,
    );
    final op = _begin('Save MahsaNet API key');
    try {
      await _controller.saveMahsaNetKey(key, onOutput: op.log);
      op.finish();
      if (!ref.mounted) return;
      state = DonateActionState(
        message: 'MahsaNet API key saved to the server',
        lastResult: state.lastResult,
      );
    } on Object catch (e) {
      final error = AppError.from(e);
      op.fail(error.summary);
      if (!ref.mounted) return;
      state = DonateActionState(error: error, lastResult: state.lastResult);
    } finally {
      unawaited(ref.read(donateEnvProvider(serverId).notifier).refresh());
      unawaited(ref.read(donateOverviewProvider(serverId).notifier).refresh());
    }
  }

  /// `moav donate submit` for [count] users; the users list is invalidated
  /// because the run creates real users on the server.
  Future<void> donate({
    required int count,
    String prefix = DonateCli.defaultPrefix,
  }) async {
    if (state.busy) return;
    state = DonateActionState(
      running: DonateActionKind.donate,
      lastResult: state.lastResult,
    );
    final op = _begin(
      'Donate $count config ${count == 1 ? 'set' : 'sets'} to MahsaNet',
    );
    try {
      final result = await _controller.donateConfigs(
        count: count,
        prefix: prefix,
        onOutput: op.log,
      );
      op.finish();
      if (!ref.mounted) return;
      state = DonateActionState(message: describe(result), lastResult: result);
    } on Object catch (e) {
      final error = AppError.from(e);
      op.fail(error.summary);
      if (!ref.mounted) return;
      state = DonateActionState(error: error, lastResult: state.lastResult);
    } finally {
      unawaited(ref.read(donateOverviewProvider(serverId).notifier).refresh());
      ref.invalidate(usersProvider(serverId));
    }
  }

  static String describe(DonateResult r) {
    String n(int v, String noun) => '$v $noun${v == 1 ? '' : 's'}';
    final parts = [
      '${n(r.usersCreated, 'user')} created',
      '${n(r.donated, 'config')} donated',
      if (r.skipped > 0) '${r.skipped} skipped',
      if (r.failed > 0) '${r.failed} failed',
    ];
    final text = parts.join(', ');
    return r.quotaHit
        ? '$text. MahsaNet quota reached; run again later to resume.'
        : text;
  }
}

final donateActionsProvider = NotifierProvider.autoDispose
    .family<DonateActionsNotifier, DonateActionState, String>(
  DonateActionsNotifier.new,
);
