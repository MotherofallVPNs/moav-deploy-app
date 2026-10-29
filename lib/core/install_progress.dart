import 'dart:math' as math;

/// Maps a detached install's `step N/M` markers to a progress fraction that
/// keeps moving while a long step runs.
///
/// `deploy.sh` reports four steps whose typical durations differ by two
/// orders of magnitude: preflight (seconds), the upstream installer (a
/// couple of minutes: packages, Docker, clone), bootstrap (the Docker image
/// build plus keys, certs and the first user: the long pole) and starting
/// the services. Each step owns a span of the bar sized by its typical
/// share, and inside the span the bar eases forward with the time spent in
/// that step so a ten-minute build does not sit at one number. A span is
/// never filled to its end before the next marker; 100% is reserved for the
/// `exit=0` marker, i.e. the install actually finishing.
class InstallProgress {
  InstallProgress._();

  /// `(start, end, typical duration)` per step of the four-step job.
  static const spans = <(double, double, Duration)>[
    (0.00, 0.02, Duration(seconds: 5)),
    (0.02, 0.22, Duration(minutes: 2)),
    (0.22, 0.92, Duration(minutes: 7)),
    (0.92, 0.99, Duration(seconds: 45)),
  ];

  /// Easing constant: `1 - e^-k` of a span is reached at its typical
  /// duration (about 80%), 96% at twice that, never 100%.
  static const _k = 1.6;

  /// Span for [step] of a job with [totalSteps]. Jobs written by another app
  /// version (a different step count) get equal spans with a generic
  /// typical duration.
  static (double, double, Duration) spanFor(int step, int totalSteps) {
    final i = (step - 1).clamp(0, totalSteps - 1);
    if (totalSteps == spans.length) return spans[i];
    final width = 0.99 / totalSteps;
    return (width * i, width * (i + 1), const Duration(minutes: 3));
  }

  /// Estimated fraction after [elapsed] in [step] of [totalSteps].
  static double estimate({
    required int step,
    required int totalSteps,
    required Duration elapsed,
  }) {
    if (step < 1 || totalSteps < 1) return 0;
    final (start, end, typical) = spanFor(step, totalSteps);
    final t = elapsed.inMilliseconds / typical.inMilliseconds;
    final eased = 1 - math.exp(-_k * t.clamp(0, double.infinity));
    return start + (end - start) * eased;
  }

  /// Step fraction without any elapsed time: the span's start.
  static double floorOf(int step, int totalSteps) =>
      estimate(step: step, totalSteps: totalSteps, elapsed: Duration.zero);
}
