import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/install_progress.dart';
import '../../core/moav_controller.dart';
import '../../core/app_error.dart';
import '../activity/activity_provider.dart';
import '../server/server_connection.dart';
import '../servers/servers_provider.dart';

/// Screen state for a server's detached install job.
class DeployState {
  const DeployState({
    this.handle,
    this.status,
    this.starting = false,
    this.polling = false,
    this.error,
    this.progress,
    this.quietFor = Duration.zero,
  });

  /// The job we are attached to, if any (persisted across app restarts).
  final InstallHandle? handle;
  final InstallStatus? status;
  final bool starting;
  final bool polling;
  /// Classified failure of the last start/poll, if any.
  final AppError? error;

  /// Estimated 0.0–1.0 from the current step and the time spent in it
  /// ([InstallProgress]); `null` until the job reports its first step.
  final double? progress;

  /// How long the log tail has not changed; long stretches are normal while
  /// Docker builds images, and the screen says so.
  final Duration quietFor;

  bool get isRunning =>
      handle != null && !(status?.isTerminal ?? false) && status?.phase != InstallPhase.unknown;

  /// True while the running job has been silent for a while.
  bool get waitingForServer =>
      isRunning && status != null && quietFor >= DeployNotifier.quietAfter;

  DeployState copyWith({
    InstallHandle? handle,
    bool clearHandle = false,
    InstallStatus? status,
    bool clearStatus = false,
    bool? starting,
    bool? polling,
    AppError? error,
    bool clearError = false,
    double? progress,
    bool clearProgress = false,
    Duration? quietFor,
  }) =>
      DeployState(
        handle: clearHandle ? null : (handle ?? this.handle),
        status: clearStatus ? null : (status ?? this.status),
        starting: starting ?? this.starting,
        polling: polling ?? this.polling,
        error: clearError ? null : (error ?? this.error),
        progress: clearProgress ? null : (progress ?? this.progress),
        quietFor: quietFor ?? this.quietFor,
      );
}

/// Drives [MoavController.install] / [MoavController.installStatus] for one
/// server. On creation it re-attaches to a previously started job, so the
/// screen shows live progress again after the app was suspended or killed.
class DeployNotifier extends Notifier<DeployState> {
  DeployNotifier(this.serverId);

  final String serverId;

  static const pollInterval = Duration(seconds: 3);

  /// Progress re-estimate between polls, so the bar creeps rather than jumps.
  static const tickInterval = Duration(seconds: 1);

  /// Silence on the log before the screen shows "Waiting for the server".
  static const quietAfter = Duration(seconds: 20);

  Timer? _timer;
  Timer? _ticker;

  /// When the current step was first seen, and the last log change.
  int? _step;
  DateTime? _stepSince;
  DateTime? _logChangedAt;
  List<String>? _lastLog;

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
    state = state.copyWith(
      starting: true,
      clearError: true,
      clearStatus: true,
      clearProgress: true,
    );
    _forgetTiming();
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
      final justSucceeded = status.phase == InstallPhase.succeeded &&
          state.status?.phase != InstallPhase.succeeded;
      _observe(status);
      state = state.copyWith(
        status: status,
        clearError: true,
        progress: _estimate(status),
        quietFor: _quietFor(),
      );
      if (status.isTerminal || status.phase == InstallPhase.unknown) {
        _stopPolling();
        _endOp(status);
      }
      // One fresh connection check so the server hub reflects the install.
      if (justSucceeded) ref.invalidate(serverConnectionProvider(serverId));
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
    _forgetTiming();
    await ref.read(secureCredStoreProvider).deleteInstallHandle(serverId);
    if (!ref.mounted) return;
    state = const DeployState();
  }

  /// Records when the step changed and when the log last moved.
  void _observe(InstallStatus status) {
    final now = clock.now();
    final step = status.step;
    if (step != null && step != _step) {
      _step = step;
      _stepSince = now;
    }
    final log = status.logTail;
    final last = _lastLog;
    if (last == null ||
        last.length != log.length ||
        (log.isNotEmpty && last.last != log.last)) {
      _logChangedAt = now;
      _lastLog = log;
    }
  }

  double? _estimate(InstallStatus status) {
    if (status.phase == InstallPhase.succeeded) return 1.0;
    final step = status.step;
    final total = status.totalSteps;
    if (step == null || total == null) return status.progress;
    final since = _stepSince;
    final elapsed = since == null ? Duration.zero : clock.now().difference(since);
    return InstallProgress.estimate(step: step, totalSteps: total, elapsed: elapsed);
  }

  Duration _quietFor() {
    final at = _logChangedAt;
    return at == null ? Duration.zero : clock.now().difference(at);
  }

  void _forgetTiming() {
    _step = null;
    _stepSince = null;
    _logChangedAt = null;
    _lastLog = null;
  }

  /// Re-estimates between polls; only publishes a visible change (a tenth
  /// of a percent, or the quiet flag) so the screen is not rebuilt for noise.
  void _tick() {
    final status = state.status;
    if (status == null || !state.isRunning) return;
    final progress = _estimate(status);
    final quiet = _quietFor();
    final visible = (progress ?? 0) * 1000;
    final shown = (state.progress ?? 0) * 1000;
    final waitingNow = quiet >= quietAfter;
    if (visible.round() == shown.round() && waitingNow == state.waitingForServer) {
      return;
    }
    state = state.copyWith(progress: progress, quietFor: quiet);
  }

  void _startPolling() {
    if (_timer != null || (state.status?.isTerminal ?? false)) return;
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
    state = state.copyWith(polling: true);
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    _ticker?.cancel();
    _ticker = null;
    if (ref.mounted && state.polling) state = state.copyWith(polling: false);
  }
}

final deployProvider = NotifierProvider.autoDispose
    .family<DeployNotifier, DeployState, String>(DeployNotifier.new);
