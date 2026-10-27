import 'package:flutter/material.dart';

import '../features/operate/operate_provider.dart';
import '../theme/moav_theme.dart';
import 'error_view.dart';

/// Renders a [FetchState]: cached data with a hairline "refreshing" bar and
/// pull-to-refresh, a full-page [ErrorView] with Retry only when nothing was
/// ever fetched, and a labelled spinner only for the very first load.
class CachedView<T> extends StatelessWidget {
  const CachedView({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.builder,
    this.loadingLabel,
  });

  final FetchState<T> state;
  final Future<void> Function() onRefresh;

  /// Builds the scrollable body (a `ListView`) for [FetchState.data].
  final Widget Function(BuildContext context, T data) builder;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data == null) {
      final error = state.error;
      if (error != null && !state.loading) {
        return ErrorView(error: error, onRetry: onRefresh);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (loadingLabel != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  loadingLabel!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        RefreshingBar(visible: state.refreshing),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: StaleNotice(error: state.error!, onRetry: onRefresh),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: builder(context, data),
          ),
        ),
      ],
    );
  }
}

/// Two-pixel indeterminate bar shown while cached data is being refreshed.
class RefreshingBar extends StatelessWidget {
  const RefreshingBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: visible
          ? const LinearProgressIndicator(
              key: ValueKey('refreshing'),
              minHeight: 2,
            )
          : const SizedBox(height: 2),
    );
  }
}

/// "Showing the last result" banner: the failure's cause and a Retry.
class StaleNotice extends StatelessWidget {
  const StaleNotice({super.key, required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErrorBanner(error: error, trailing: 'Showing the last result.'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

/// "updated 14:02" caption for section headers.
Widget updatedAt(BuildContext context, DateTime? at) => at == null
    ? const SizedBox.shrink()
    : Text(
        'updated ${TimeOfDay.fromDateTime(at).format(context)}',
        style: moavLabel(size: 10, color: MoavColors.textMuted),
      );
