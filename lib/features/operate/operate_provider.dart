import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../core/moav_controller.dart';
import '../servers/servers_provider.dart';
import '../users/users_provider.dart';

/// The last successful result of a server fetch plus what is happening now.
///
/// Tabs render [data] immediately when they come back and never block on a
/// spinner once something was fetched; [loading] with data means "refreshing".
class FetchState<T> {
  const FetchState({
    this.data,
    this.fetchedAt,
    this.loading = false,
    this.error,
  });

  final T? data;
  final DateTime? fetchedAt;
  final bool loading;

  /// Failure of the most recent fetch; cleared by the next success.
  final AppError? error;

  bool get hasData => data != null;
  bool get refreshing => loading && hasData;

  FetchState<T> copyWith({
    T? data,
    DateTime? fetchedAt,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) =>
      FetchState<T>(
        data: data ?? this.data,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Fetches once on first watch, keeps the last good value for the life of
/// the app, and coalesces concurrent refreshes into one round trip.
///
/// Not autoDispose on purpose: switching tabs must neither cancel the fetch
/// in flight nor forget the cached result.
abstract class CachedFetchNotifier<T> extends Notifier<FetchState<T>> {
  CachedFetchNotifier(this.serverId);

  final String serverId;

  Future<void>? _inFlight;

  MoavController get controller =>
      ref.read(moavControllerProvider(serverId));

  Future<T> fetch();

  @override
  FetchState<T> build() {
    Future<void>.microtask(refresh);
    return const FetchState();
  }

  /// Re-fetches; returns the in-flight future when one is already running.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _fetch();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  /// Refreshes only when the cached value is older than [maxAge] or absent.
  Future<void> refreshIfStale(Duration maxAge, {DateTime? now}) {
    final at = state.fetchedAt;
    final fresh = at != null &&
        (now ?? DateTime.now()).difference(at) < maxAge;
    if (fresh) return Future.value();
    return refresh();
  }

  Future<void> _fetch() async {
    state = state.copyWith(loading: true);
    try {
      final value = await fetch();
      if (!ref.mounted) return;
      state = FetchState<T>(
        data: value,
        fetchedAt: DateTime.now(),
        loading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: AppError.from(e));
    }
  }
}

class StatusNotifier extends CachedFetchNotifier<ServiceStatusReport> {
  StatusNotifier(super.serverId);

  @override
  Future<ServiceStatusReport> fetch() => controller.status();
}

class DoctorNotifier extends CachedFetchNotifier<DoctorReport> {
  DoctorNotifier(super.serverId);

  @override
  Future<DoctorReport> fetch() => controller.doctor();
}

class MonitoringNotifier extends CachedFetchNotifier<Monitoring> {
  MonitoringNotifier(super.serverId);

  @override
  Future<Monitoring> fetch() => controller.monitoring();
}

class MetricsNotifier extends CachedFetchNotifier<MetricsSnapshot> {
  MetricsNotifier(super.serverId);

  @override
  Future<MetricsSnapshot> fetch() => controller.metrics();
}

class ServerInfoNotifier extends CachedFetchNotifier<ServerInfo> {
  ServerInfoNotifier(super.serverId);

  @override
  Future<ServerInfo> fetch() => controller.serverInfo();
}

/// `ENABLE_*` flags from `.env`; the Services tab reads enabled/disabled
/// per row from it and refreshes it after an enable/disable action.
class ServiceFlagsNotifier extends CachedFetchNotifier<ServiceFlags> {
  ServiceFlagsNotifier(super.serverId);

  @override
  Future<ServiceFlags> fetch() => controller.serviceFlags();
}

final statusProvider = NotifierProvider.family<StatusNotifier,
    FetchState<ServiceStatusReport>, String>(StatusNotifier.new);

final doctorProvider = NotifierProvider.family<DoctorNotifier,
    FetchState<DoctorReport>, String>(DoctorNotifier.new);

final monitoringProvider = NotifierProvider.family<MonitoringNotifier,
    FetchState<Monitoring>, String>(MonitoringNotifier.new);

final metricsProvider = NotifierProvider.family<MetricsNotifier,
    FetchState<MetricsSnapshot>, String>(MetricsNotifier.new);

final serverInfoProvider = NotifierProvider.family<ServerInfoNotifier,
    FetchState<ServerInfo>, String>(ServerInfoNotifier.new);

final serviceFlagsProvider = NotifierProvider.family<ServiceFlagsNotifier,
    FetchState<ServiceFlags>, String>(ServiceFlagsNotifier.new);

/// A cached value is re-fetched in the background when a tab reopens and
/// the value is older than this.
const tabStaleAfter = Duration(minutes: 2);

/// Runs `moav test <user>` when first watched (minutes on a cold image).
final userTestProvider =
    FutureProvider.autoDispose.family<TestMatrix, BundleKey>(
  (ref, key) => ref.read(moavControllerProvider(key.serverId)).testUser(key.user),
);

class ServiceActionState {
  const ServiceActionState({this.running, this.message, this.error});

  /// The action in flight, if any.
  final ServiceAction? running;
  final String? message;

  /// Failure of the last action, with the command output as detail.
  final AppError? error;

  bool get busy => running != null;

  /// Whether the action in flight targets [service] specifically.
  bool isRunningFor(String service) => running?.service == service;
}

/// Serialises service actions for one server and refreshes status after.
class ServiceActionsNotifier extends Notifier<ServiceActionState> {
  ServiceActionsNotifier(this.serverId);

  final String serverId;

  @override
  ServiceActionState build() => const ServiceActionState();

  Future<void> run(ServiceAction action) async {
    if (state.busy) return;
    state = ServiceActionState(running: action);
    try {
      await ref.read(moavControllerProvider(serverId)).service(action);
      if (!ref.mounted) return;
      state = ServiceActionState(message: '${describe(action)} done');
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ServiceActionState(error: AppError.from(e));
    } finally {
      // Same cached refresh the tab uses: the row re-renders from the
      // next `moav status`, the old report stays visible meanwhile.
      unawaited(ref.read(statusProvider(serverId).notifier).refresh());
      if (action.kind.perService) {
        unawaited(ref.read(serviceFlagsProvider(serverId).notifier).refresh());
      }
      if (action.kind == ServiceActionKind.regenerateUsers) {
        ref.invalidate(usersProvider(serverId));
      }
    }
  }

  static String describe(ServiceAction a) {
    final verb = switch (a.kind) {
      ServiceActionKind.start => 'Start',
      ServiceActionKind.stop => 'Stop',
      ServiceActionKind.restart => 'Restart',
      ServiceActionKind.regenerateUsers => 'Regenerate users',
      ServiceActionKind.enable => 'Enable',
      ServiceActionKind.disable => 'Disable',
    };
    if (a.kind == ServiceActionKind.regenerateUsers) return verb;
    return '$verb ${a.service ?? 'all services'}';
  }
}

final serviceActionsProvider = NotifierProvider.autoDispose
    .family<ServiceActionsNotifier, ServiceActionState, String>(
  ServiceActionsNotifier.new,
);

// --- Self-update ---

/// Update check plus the detached `moav update` job, for one server.
class UpdateState {
  const UpdateState({
    this.check,
    this.checking = false,
    this.checkError,
    this.job,
    this.starting = false,
    this.polling = false,
    this.jobError,
  });

  final UpdateCheck? check;
  final bool checking;
  final AppError? checkError;

  /// Progress of the update job once started or re-attached.
  final InstallStatus? job;
  final bool starting;
  final bool polling;
  final AppError? jobError;

  bool get jobRunning =>
      job != null && !job!.isTerminal && job!.phase != InstallPhase.unknown;

  UpdateState copyWith({
    UpdateCheck? check,
    bool? checking,
    AppError? checkError,
    bool clearCheckError = false,
    InstallStatus? job,
    bool clearJob = false,
    bool? starting,
    bool? polling,
    AppError? jobError,
    bool clearJobError = false,
  }) =>
      UpdateState(
        check: check ?? this.check,
        checking: checking ?? this.checking,
        checkError: clearCheckError ? null : (checkError ?? this.checkError),
        job: clearJob ? null : (job ?? this.job),
        starting: starting ?? this.starting,
        polling: polling ?? this.polling,
        jobError: clearJobError ? null : (jobError ?? this.jobError),
      );
}

/// Drives [MoavController.checkForUpdates] / [MoavController.startUpdate]
/// and polls [MoavController.updateStatus] like the deploy screen does. On
/// creation it re-attaches to a job that is still running on the server.
class UpdateNotifier extends Notifier<UpdateState> {
  UpdateNotifier(this.serverId);

  final String serverId;

  static const pollInterval = Duration(seconds: 3);

  Timer? _timer;

  MoavController get _controller => ref.read(moavControllerProvider(serverId));

  @override
  UpdateState build() {
    ref.onDispose(_stopPolling);
    Future<void>.microtask(attach);
    return const UpdateState();
  }

  /// Picks up a job that is still running (e.g. after the app was killed).
  Future<void> attach() async {
    try {
      final status = await _controller.updateStatus();
      if (!ref.mounted || status == null) return;
      if (status.phase == InstallPhase.pending ||
          status.phase == InstallPhase.running) {
        state = state.copyWith(job: status);
        _startPolling();
      }
    } on Object {
      // Nothing to attach to; the user can still check or start an update.
    }
  }

  Future<void> check() async {
    if (state.checking) return;
    state = state.copyWith(checking: true, clearCheckError: true);
    try {
      final check = await _controller.checkForUpdates();
      if (!ref.mounted) return;
      state = state.copyWith(check: check, checking: false);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(checking: false, checkError: AppError.from(e));
    }
  }

  Future<void> start() async {
    if (state.starting || state.jobRunning) return;
    state = state.copyWith(starting: true, clearJobError: true, clearJob: true);
    try {
      await _controller.startUpdate();
      if (!ref.mounted) return;
      state = state.copyWith(starting: false);
      await poll();
      _startPolling();
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(starting: false, jobError: AppError.from(e));
    }
  }

  /// One status poll. Errors are shown but polling continues; a dropped
  /// SSH session after backgrounding is expected and recoverable.
  Future<void> poll() async {
    try {
      final status = await _controller.updateStatus();
      if (!ref.mounted) return;
      state = state.copyWith(
        job: status ??
            const InstallStatus(
              phase: InstallPhase.unknown,
              message: 'No update log found on the server',
            ),
        clearJobError: true,
      );
      if (status == null || status.isTerminal) {
        _stopPolling();
        if (status?.phase == InstallPhase.succeeded) _afterSuccess();
      }
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(jobError: AppError.from(e));
    }
  }

  /// Forgets the finished job so the card returns to the check/update view.
  void dismiss() {
    _stopPolling();
    state = state.copyWith(clearJob: true, clearJobError: true);
  }

  void _afterSuccess() {
    // The version and update verdict changed; drop the stale check.
    state = UpdateState(job: state.job);
    unawaited(ref.read(serverInfoProvider(serverId).notifier).refresh());
    unawaited(ref.read(statusProvider(serverId).notifier).refresh());
  }

  void _startPolling() {
    if (_timer != null || !state.jobRunning) return;
    _timer = Timer.periodic(pollInterval, (_) => poll());
    state = state.copyWith(polling: true);
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted && state.polling) state = state.copyWith(polling: false);
  }
}

final updateProvider =
    NotifierProvider.family<UpdateNotifier, UpdateState, String>(
  UpdateNotifier.new,
);
