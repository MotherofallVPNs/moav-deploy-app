import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/ssh_moav_controller.dart';
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
  final String? error;

  bool get isRunning =>
      handle != null && !(status?.isTerminal ?? false) && status?.phase != InstallPhase.unknown;

  DeployState copyWith({
    InstallHandle? handle,
    bool clearHandle = false,
    InstallStatus? status,
    bool clearStatus = false,
    bool? starting,
    bool? polling,
    String? error,
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

  MoavController get _controller =>
      ref.read(moavControllerProvider(serverId));

  @override
  DeployState build() {
    ref.onDispose(_stopPolling);
    Future<void>.microtask(_restore);
    return const DeployState();
  }

  Future<void> _restore() async {
    final json = await ref.read(secureCredStoreProvider).readInstallHandle(serverId);
    if (json == null) return;
    if (!ref.mounted) return;
    state = state.copyWith(handle: InstallHandle.fromJson(json));
    await refresh();
    _startPolling();
  }

  /// Starts (or re-attaches to) the detached install and begins polling.
  Future<void> start(InstallSpec spec) async {
    if (state.starting) return;
    state = state.copyWith(starting: true, clearError: true, clearStatus: true);
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
      if (!ref.mounted) return;
      state = state.copyWith(
        starting: false,
        error: SshMoavController.describeError(e),
      );
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
      state = state.copyWith(status: status, clearError: true);
      if (status.isTerminal) _stopPolling();
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: SshMoavController.describeError(e));
    }
  }

  /// Forgets the finished job so a new install can be started.
  Future<void> reset() async {
    _stopPolling();
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
