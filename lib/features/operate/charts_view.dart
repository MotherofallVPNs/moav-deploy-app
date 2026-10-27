import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/moav_controller.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'chart_panels.dart';
import 'operate_provider.dart';

/// The native charts section of the Analytics tab: a handful of line charts
/// over the last hour plus an exporter health row, all from one cached
/// Prometheus round trip ([chartsProvider]).
class ChartsSection extends StatelessWidget {
  const ChartsSection({super.key, required this.state, required this.onRetry});

  final FetchState<ChartsSnapshot> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final error = state.error;
    final panels = data == null ? const <ChartPanel>[] : chartPanels(data);
    final exporters = data == null ? const <ExporterHealth>[] : exporterHealth(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          ErrorBanner(
            error: error,
            trailing: data == null ? null : 'Showing the last result.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ),
        ],
        if (data != null) ...[
          if (panels.isEmpty && exporters.isEmpty)
            const MoavCard(
              child: Text(
                'No chart data. Enable the monitoring profile '
                '(moav start monitoring) and give Prometheus a few minutes.',
              ),
            ),
          for (final p in panels) ...[
            MetricChartCard(panel: p, window: data.window),
            const SizedBox(height: 10),
          ],
          if (exporters.isNotEmpty) ExporterRow(exporters: exporters),
        ] else if (error == null)
          MoavCard(
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Querying Prometheus for the last hour…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One line chart on a card: title, latest value, legend for several
/// series, crosshair tooltip on touch.
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.panel,
    required this.window,
  });

  final ChartPanel panel;
  final Duration window;

  @override
  Widget build(BuildContext context) {
    final maxY = chartMax(panel);
    final headline = panel.series.length == 1 ? panel.series.first.last : null;
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(panel.title,
                    style: moavLabel(size: 11, color: MoavColors.textSecondary)),
              ),
              if (headline != null)
                Text(
                  formatChartValue(headline, panel.unit),
                  style: moavMono(size: 16, weight: FontWeight.w600),
                ),
              const SizedBox(width: 6),
              Text(
                'last ${window.inMinutes} min',
                style: moavLabel(size: 10, color: MoavColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: LineChart(_data(maxY), duration: Duration.zero),
          ),
          if (panel.series.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final s in panel.series) _LegendEntry(series: s, unit: panel.unit),
              ],
            ),
          ],
        ],
      ),
    );
  }

  LineChartData _data(double maxY) {
    final allPoints = panel.series.expand((s) => s.points);
    final minX = allPoints
        .map((p) => p.time.millisecondsSinceEpoch.toDouble())
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final maxX = allPoints
        .map((p) => p.time.millisecondsSinceEpoch.toDouble())
        .fold<double>(double.negativeInfinity, (a, b) => a > b ? a : b);
    final gridStep = maxY / 4;
    return LineChartData(
      minX: minX,
      maxX: maxX > minX ? maxX : minX + 1,
      minY: 0,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: gridStep,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: MoavColors.border, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            interval: gridStep,
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                formatChartValue(v, panel.unit),
                style: moavMono(size: 9, weight: FontWeight.w400, color: MoavColors.textMuted),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 18,
            interval: (maxX - minX) / 3 > 0 ? (maxX - minX) / 3 : 1,
            getTitlesWidget: (v, meta) {
              if (v == minX || v == maxX) return const SizedBox.shrink();
              final t = DateTime.fromMillisecondsSinceEpoch(v.round()).toLocal();
              return Text(
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                style: moavMono(size: 9, weight: FontWeight.w400, color: MoavColors.textMuted),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => MoavColors.cardRaised,
          tooltipBorder: const BorderSide(color: MoavColors.borderStrong),
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${panel.series[s.barIndex].label}  ${formatChartValue(s.y, panel.unit)}',
                moavMono(size: 10, color: MoavColors.text),
              ),
          ],
        ),
        getTouchedSpotIndicator: (bar, indexes) => [
          for (final _ in indexes)
            const TouchedSpotIndicatorData(
              FlLine(color: MoavColors.borderStrong, strokeWidth: 1),
              FlDotData(show: false),
            ),
        ],
      ),
      lineBarsData: [
        for (final s in panel.series)
          LineChartBarData(
            spots: [
              for (final p in s.points)
                FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value),
            ],
            color: s.color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: panel.series.length == 1,
              color: s.color.withValues(alpha: 0.12),
            ),
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.series, required this.unit});

  final ChartSeries series;
  final ChartUnit unit;

  @override
  Widget build(BuildContext context) {
    final last = series.last;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: series.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(series.label, style: moavLabel(size: 10, color: MoavColors.textSecondary)),
        if (last != null) ...[
          const SizedBox(width: 4),
          Text(
            formatChartValue(last, unit),
            style: moavMono(size: 10, color: MoavColors.text),
          ),
        ],
      ],
    );
  }
}

/// Exporter health: one pill per Prometheus scrape job.
class ExporterRow extends StatelessWidget {
  const ExporterRow({super.key, required this.exporters});

  final List<ExporterHealth> exporters;

  @override
  Widget build(BuildContext context) {
    final up = exporters.where((e) => e.up).length;
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Exporters',
                    style: moavLabel(size: 11, color: MoavColors.textSecondary)),
              ),
              Text(
                '$up / ${exporters.length} up',
                style: moavMono(size: 12, color: MoavColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in exporters)
                StatusPill(e.job, tone: e.up ? StatusTone.pass : StatusTone.fail),
            ],
          ),
        ],
      ),
    );
  }
}
