import 'package:flutter/material.dart';

import '../core/app_error.dart';
import '../theme/moav_theme.dart';

/// The one way errors are shown full-screen or in a tab: an icon that says
/// what kind of failure it was, one sentence, a hint on what to do, the
/// scrubbed detail folded away, and a Retry button.
///
/// Accepts any thrown object; classification happens via [AppError.from].
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final Object error;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBadge(
                iconFor(e.kind),
                size: 56,
                color: e.retryable ? MoavColors.warn : MoavColors.fail,
              ),
              const SizedBox(height: 16),
              Text(e.message, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              if (e.hint != null) ...[
                const SizedBox(height: 8),
                Text(e.hint!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              ],
              if (e.detail != null && e.detail!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: Text('Details', style: theme.textTheme.bodySmall),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [CodeBlock(e.detail!, size: 11)],
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(retryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData iconFor(AppErrorKind kind) => switch (kind) {
        AppErrorKind.offline => Icons.wifi_off,
        AppErrorKind.unreachable => Icons.cloud_off,
        AppErrorKind.timeout => Icons.timer_off_outlined,
        AppErrorKind.auth => Icons.key_off,
        AppErrorKind.credential => Icons.vpn_key_off_outlined,
        AppErrorKind.transport => Icons.link_off,
        AppErrorKind.commandFailed => Icons.terminal,
        AppErrorKind.unexpectedOutput => Icons.help_outline,
        AppErrorKind.invalidInput => Icons.edit_off,
        AppErrorKind.unknown => Icons.error_outline,
      };
}

/// Inline variant for forms and headers: icon, sentence, hint; no scrolling.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error, this.trailing});

  final Object error;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    // Retryable failures (network, timeout) get the calm warn tone; only a
    // rejected key or password is red.
    final c = e.retryable ? MoavColors.warn : MoavColors.fail;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: MoavRadius.control,
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ErrorView.iconFor(e.kind), size: 20, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trailing == null ? e.message : '${e.message} $trailing',
                  style: const TextStyle(color: MoavColors.text, fontWeight: FontWeight.w600),
                ),
                if (e.hint != null)
                  Text(
                    e.hint!,
                    style: const TextStyle(color: MoavColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Snackbar text for a failed action: sentence + hint, scrubbed.
String errorSummary(Object e) => AppError.from(e).summary;

/// Compact inline status for a failed connection attempt: icon for the kind,
/// one sentence, one hint. Sits under a form field or in a card header.
class ConnectionNotice extends StatelessWidget {
  const ConnectionNotice({super.key, required this.error, this.prefix});

  final Object error;

  /// Short lead-in such as "Could not connect." shown before the sentence.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    final c = e.retryable ? MoavColors.warn : MoavColors.fail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(ErrorView.iconFor(e.kind), size: 16, color: c),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prefix == null ? e.message : '$prefix ${e.message}',
                style: const TextStyle(
                  color: MoavColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (e.hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    e.hint!,
                    style: const TextStyle(
                      color: MoavColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows a failed action as a quiet snackbar: kind icon, sentence, hint.
/// Replaces the current snackbar so a "Connecting…" notice never lingers.
void showErrorSnackBar(
  ScaffoldMessengerState messenger,
  Object error, {
  String? prefix,
  Duration duration = const Duration(seconds: 6),
}) {
  final e = AppError.from(error);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              ErrorView.iconFor(e.kind),
              size: 18,
              color: e.retryable ? MoavColors.warn : MoavColors.fail,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prefix == null ? e.message : '$prefix ${e.message}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (e.hint != null)
                  Text(
                    e.hint!,
                    style: const TextStyle(
                      color: MoavColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
