import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/app_error.dart';
import '../activity/activity_provider.dart';
import '../servers/servers_provider.dart';

/// Screen state for a server's detached install job.
class DeployState {
  const DeployState({
    this.handle,
    this.status,
    this.starting = false,
    this.polling = false,
    this.error,
  });

  /// The job we are attached to, if any (persisted across app restarts).
  final InstallHandle? handle;
  final InstallStatus? status;
  final bool starting;
  final bool polling;
  /// Classified failure of the last start/poll, if any.
  final AppError? error;

  bool get isRunning =>
      handle != null && !(status?.isTerminal ?? false) && status?.phase != InstallPhase.unknown;

  DeployState copyWith({
    InstallHandle? handle,
    bool clearHandle = false,
    InstallStatus? status,
    bool clearStatus = false,
    bool? starting,
    bool? polling,
    AppError? error,
    bool clearError = false,
  }) =>
      DeployState(
        handle: clearHandle ? null : (handle ?? this.handle),
        status: clearStatus ? null : (status ?? this.status),
        starting: starting ?? this.starting,
        polling: polling ?? this.polling,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives [MoavController.install] / [MoavController.installStatus] for one
/// server. On creation it re-attaches to a previously started job, so the
/// screen shows live progress again after the app was suspended or killed.
class DeployNotifier extends Notifier<DeployState> {
  DeployNotifier(this.serverId);

  final String serverId;

  static const pollInterval = Duration(seconds: 3);

  Timer? _timer;

  /// Activity entry for the job being watched, if any.
  OperationHandle? _op;

  MoavController get _controller =>
      ref.read(moavControllerProvider(serverId));

  @override
  DeployState build() {
    ref.onDispose(() {
      _stopPolling();
      // Other providers must not change inside a dispose callback.
      final op = _op;
      _op = null;
      if (op != null) scheduleMicrotask(op.detach);
    });
    Future<void>.microtask(_restore);
    return const DeployState();
  }

  OperationHandle _beginOp() {
    _op?.detach();
    return _op = ref
        .read(activityProvider.notifier)
        .begin('Install MoaV · ${serverLabelOf(ref, serverId)}');
  }

  void _endOp(InstallStatus status) {
    final op = _op;
    if (op == null) return;
    if (status.phase == InstallPhase.failed) {
      op.fail(status.message ?? 'Install failed');
    } else {
      op.finish();
    }
    _op = null;
  }

  Future<void> _restore() async {
    final json = await ref.read(secureCredStoreProvider).readInstallHandle(serverId);
    if (json == null) return;
    if (!ref.mounted) return;
    state = state.copyWith(handle: InstallHandle.fromJson(json));
    _beginOp();
    await refresh();
    _startPolling();
  }

  /// Starts (or re-attaches to) the detached install and begins polling.
  Future<void> start(InstallSpec spec) async {
    if (state.starting) return;
    state = state.copyWith(starting: true, clearError: true, clearStatus: true);
    final op = _beginOp();
    try {
      final handle = await _controller.install(spec);
      await ref
          .read(secureCredStoreProvider)
          .writeInstallHandle(serverId, handle.toJson());
      if (!ref.mounted) return;
      state = state.copyWith(handle: handle, starting: false);
      await refresh();
      _startPolling();
    } on Object catch (e) {
      final error = AppError.from(e);
      op.fail(error.summary);
      _op = null;
      if (!ref.mounted) return;
      state = state.copyWith(starting: false, error: error);
    }
  }

  /// One status poll. Errors are shown but polling continues, because a
  /// dropped SSH session after backgrounding is expected and recoverable.
  Future<void> refresh() async {
    final handle = state.handle;
    if (handle == null) return;
    try {
      final status = await _controller.installStatus(handle);
      if (!ref.mounted) return;
      _op?.setLog(status.logTail);
      state = state.copyWith(status: status, clearError: true);
      if (status.isTerminal || status.phase == InstallPhase.unknown) {
        _stopPolling();
        _endOp(status);
      }
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: AppError.from(e));
    }
  }

  /// Forgets the finished job so a new install can be started.
  Future<void> reset() async {
    _stopPolling();
    _op?.detach();
    _op = null;
    await ref.read(secureCredStoreProvider).deleteInstallHandle(serverId);
    if (!ref.mounted) return;
    state = const DeployState();
  }

  void _startPolling() {
    if (_timer != null || (state.status?.isTerminal ?? false)) return;
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    state = state.copyWith(polling: true);
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted && state.polling) state = state.copyWith(polling: false);
  }
}

final deployProvider = NotifierProvider.autoDispose
    .family<DeployNotifier, DeployState, String>(DeployNotifier.new);
