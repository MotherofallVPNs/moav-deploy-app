import 'package:flutter/foundation.dart';

import 'redactor.dart';

/// The only logging facility in the app.
///
/// - In release builds it is a no-op: nothing is printed to logcat / the
///   system log, ever. There is no crash reporter and no telemetry.
/// - In debug builds it prints one scrubbed line per event via [debugPrint].
/// - Every message passes through [Redactor.scrub] first, so even a
///   developer-added log line cannot leak key material.
///
/// The sink is swappable so tests can assert what would have been printed.
class AppLog {
  AppLog._();

  /// Where scrubbed lines go. `null` disables output (the release default).
  static void Function(String line)? sink = kDebugMode ? debugPrint : null;

  static void info(String context, String message) => _emit('I', context, message);

  static void warn(String context, String message) => _emit('W', context, message);

  /// Records an error. The stack trace is included only in debug builds and
  /// is scrubbed as well (stack frames never carry secrets, but the
  /// exception message they are printed with can).
  static void error(String context, Object error, [StackTrace? stack]) {
    final text = StringBuffer(error.toString());
    if (stack != null && kDebugMode) text.write('\n$stack');
    _emit('E', context, text.toString());
  }

  static void _emit(String level, String context, String message) {
    final s = sink;
    if (s == null) return;
    final scrubbed = Redactor.scrub(message);
    // If a pattern slipped through, refuse to print the payload at all.
    s('[$level] $context: ${Redactor.looksSecret(scrubbed) ? '<suppressed>' : scrubbed}');
  }

  /// Routes framework and platform errors through the redactor so an
  /// uncaught exception can never print a secret. Call once from `main`.
  static void installGlobalHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error('flutter', details.exceptionAsString(), details.stack);
      if (kDebugMode && previous != null) {
        // Keep the red-box / console diagnostics in debug, with the message
        // scrubbed. In release nothing is presented or printed.
        previous(FlutterErrorDetails(
          exception: _ScrubbedException(Redactor.scrub(details.exceptionAsString())),
          stack: details.stack,
          library: details.library,
          context: details.context,
          silent: details.silent,
        ));
      }
    };
    PlatformDispatcher.instance.onError = (e, stack) {
      error('uncaught', e, stack);
      return true; // handled: do not let the engine print it
    };
  }
}

class _ScrubbedException implements Exception {
  const _ScrubbedException(this.message);
  final String message;
  @override
  String toString() => message;
}
