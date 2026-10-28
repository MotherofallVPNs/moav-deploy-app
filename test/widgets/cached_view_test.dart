import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/operate/operate_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';
import 'package:moav_deploy/widgets/cached_view.dart';
import 'package:moav_deploy/widgets/error_view.dart';

/// Every cached tab renders through [CachedView]; these pin the four states
/// (first load, first-load failure, refreshing, stale-with-error) and that
/// each Retry path calls back once.
void main() {
  const timeout = AppError(
    AppErrorKind.timeout,
    'The server did not respond in time.',
    hint: 'Check the connection.',
  );

  Future<int> pump(
    WidgetTester tester,
    FetchState<int> state, {
    String? loadingLabel,
  }) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: moavDarkTheme(),
      home: Scaffold(
        body: CachedView<int>(
          state: state,
          loadingLabel: loadingLabel,
          onRefresh: () async => refreshes++,
          builder: (_, data) => ListView(children: [Text('value $data')]),
        ),
      ),
    ));
    await tester.pump();
    return refreshes;
  }

  testWidgets('first load: a spinner and the label, nothing else', (tester) async {
    await pump(tester, const FetchState(loading: true), loadingLabel: 'Running moav status');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Running moav status'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('first-load failure: full-page error with a working Retry',
      (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: moavDarkTheme(),
      home: Scaffold(
        body: CachedView<int>(
          state: const FetchState(error: timeout),
          onRefresh: () async => refreshes++,
          builder: (_, data) => Text('value $data'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('The server did not respond in time.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(refreshes, 1);
  });

  testWidgets('a retry in flight shows the spinner again, not the error',
      (tester) async {
    await pump(tester, const FetchState(error: timeout, loading: true));
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('refreshing: the cached value stays, a hairline bar appears',
      (tester) async {
    await pump(tester, FetchState(data: 7, fetchedAt: DateTime(2026), loading: true));
    expect(find.text('value 7'), findsOneWidget);
    expect(find.byKey(const ValueKey('refreshing')), findsOneWidget);
    expect(find.byType(StaleNotice), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('stale with error: banner, "last result" note and Retry',
      (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: moavDarkTheme(),
      home: Scaffold(
        body: CachedView<int>(
          state: FetchState(data: 3, fetchedAt: DateTime(2026), error: timeout),
          onRefresh: () async => refreshes++,
          builder: (_, data) => ListView(children: [Text('value $data')]),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('value 3'), findsOneWidget);
    expect(find.byType(StaleNotice), findsOneWidget);
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.text('The server did not respond in time. Showing the last result.'),
      findsOneWidget,
    );
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byKey(const ValueKey('refreshing')), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(refreshes, 1);
  });

  testWidgets('pull to refresh calls back once', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: moavDarkTheme(),
      home: Scaffold(
        body: CachedView<int>(
          state: FetchState(data: 1, fetchedAt: DateTime(2026)),
          onRefresh: () async => refreshes++,
          builder: (_, data) => ListView(children: [Text('value $data')]),
        ),
      ),
    ));
    await tester.pump();
    await tester.fling(find.text('value 1'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  test('FetchState flags: hasData, refreshing and clearError', () {
    const empty = FetchState<int>();
    expect(empty.hasData, isFalse);
    expect(empty.refreshing, isFalse);
    final loaded = FetchState<int>(data: 1, fetchedAt: DateTime(2026));
    expect(loaded.copyWith(loading: true).refreshing, isTrue);
    final failed = loaded.copyWith(error: timeout);
    expect(failed.copyWith(clearError: true).error, isNull);
    expect(failed.copyWith(error: null).error, same(timeout));
  });
}
