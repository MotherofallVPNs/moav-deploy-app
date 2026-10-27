import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../core/ssh_connection.dart';
import '../../security/redactor.dart';

/// [detached]: the app stopped watching a server-side job that keeps running.
enum OperationPhase { running, done, failed, detached }

/// One background operation the app ran against a server: a label, when it
/// started and ended, and the output it streamed. Shown by the activity
/// indicator in every app bar.
class Operation {
  const Operation({
    required this.id,
    required this.label,
    required this.startedAt,
    this.endedAt,
    this.phase = OperationPhase.running,
    this.lines = const [],
    this.error,
  });

  final int id;
  final String label;
  final DateTime startedAt;
  final DateTime? endedAt;
  final OperationPhase phase;

  /// Streamed output, oldest first. Already scrubbed by the caller where it
  /// could carry a secret (command output passes through [AppError]).
  final List<String> lines;

  /// One sentence on why it failed, when [phase] is [OperationPhase.failed].
  final String? error;

  bool get running => phase == OperationPhase.running;

  Duration elapsed([DateTime? now]) =>
      (endedAt ?? now ?? DateTime.now()).difference(startedAt);

  Operation copyWith({
    DateTime? endedAt,
    OperationPhase? phase,
    List<String>? lines,
    String? error,
  }) =>
      Operation(
        id: id,
        label: label,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        phase: phase ?? this.phase,
        lines: lines ?? this.lines,
        error: error ?? this.error,
      );
}

class ActivityState {
  const ActivityState({this.operations = const []});

  /// Newest first, bounded to [ActivityNotifier.keep] entries.
  final List<Operation> operations;

  Iterable<Operation> get running => operations.where((o) => o.running);

  bool get busy => operations.any((o) => o.running);

  int get runningCount => running.length;

  /// What the panel opens on: the newest running operation, else the latest.
  Operation? get current => running.firstOrNull ?? operations.firstOrNull;

  Operation? byId(int id) => operations.where((o) => o.id == id).firstOrNull;
}

/// App-wide registry of in-flight and recent operations. Not autoDispose:
/// the last log must survive leaving the screen that produced it.
class ActivityNotifier extends Notifier<ActivityState> {
  static const keep = 20;
  static const maxLines = 400;

  int _nextId = 1;

  @override
  ActivityState build() => const ActivityState();

  /// Registers a running operation; drive it through the returned handle.
  OperationHandle begin(String label) {
    final op = Operation(
      id: _nextId++,
      label: label,
      startedAt: DateTime.now(),
    );
    _set([op, ...state.operations].take(keep).toList(growable: false));
    return OperationHandle._(this, op.id);
  }

  /// Runs [body] as a tracked operation: done on return, failed on throw.
  Future<T> run<T>(
    String label,
    Future<T> Function(OperationHandle op) body,
  ) async {
    final op = begin(label);
    try {
      final value = await body(op);
      op.finish();
      return value;
    } on Object catch (e) {
      op.fail(AppError.from(e).summary);
      rethrow;
    }
  }

  void _set(List<Operation> ops) {
    if (!ref.mounted) return;
    state = ActivityState(operations: ops);
  }

  void _update(int id, Operation Function(Operation op) change) {
    // Handles outlive screens; after the container is gone there is nothing
    // to update (and reading `state` would throw).
    if (!ref.mounted) return;
    _set([
      for (final o in state.operations) o.id == id ? change(o) : o,
    ]);
  }

  void _append(int id, String text) {
    final incoming = _clean(text).split('\n').map((l) => l.trimRight()).toList();
    while (incoming.isNotEmpty && incoming.last.isEmpty) {
      incoming.removeLast();
    }
    if (incoming.isEmpty) return;
    _update(id, (o) => o.copyWith(lines: _tail([...o.lines, ...incoming])));
  }

  void _replace(int id, List<String> lines) => _update(
        id,
        (o) => o.copyWith(lines: _tail(lines.map(_clean).toList())),
      );

  void _detach(int id, String note) => _update(
        id,
        (o) => o.running
            ? o.copyWith(
                endedAt: DateTime.now(),
                phase: OperationPhase.detached,
                lines: _tail([...o.lines, note]),
              )
            : o,
      );

  void _end(int id, {String? error}) => _update(
        id,
        (o) => o.running
            ? o.copyWith(
                endedAt: DateTime.now(),
                phase: error == null
                    ? OperationPhase.done
                    : OperationPhase.failed,
                error: error,
              )
            : o,
      );

  /// No colour codes in the panel, and never a secret.
  static String _clean(String s) => Redactor.scrub(SshConnection.stripAnsi(s));

  static List<String> _tail(List<String> lines) => lines.length <= maxLines
      ? List.unmodifiable(lines)
      : List.unmodifiable(lines.sublist(lines.length - maxLines));
}

/// Write side of one [Operation]. Safe to call after the notifier is gone.
class OperationHandle {
  OperationHandle._(this._notifier, this.id);

  final ActivityNotifier _notifier;
  final int id;

  /// Appends streamed output (may contain several lines).
  void log(String text) => _notifier._append(id, text);

  /// Replaces the whole log, for polled jobs that return a fresh tail.
  void setLog(List<String> lines) => _notifier._replace(id, lines);

  void finish() => _notifier._end(id);

  void fail(String message) => _notifier._end(id, error: message);

  /// The app stops watching; the job itself continues on the server.
  void detach([String note = '(stopped watching; the job continues on the server)']) =>
      _notifier._detach(id, note);
}

final activityProvider =
    NotifierProvider<ActivityNotifier, ActivityState>(ActivityNotifier.new);
