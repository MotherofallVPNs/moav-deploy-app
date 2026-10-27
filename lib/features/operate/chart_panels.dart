import 'dart:ui' show Color;

import '../../core/moav_cli.dart';
import '../../core/moav_controller.dart';

/// Series colours for the native charts: five hues stepped for the card
/// surface and checked for colour-vision separation. A colour follows its
/// entity (sing-box is always [ChartPalette.cyan]), never its position.
class ChartPalette {
  ChartPalette._();

  static const cyan = Color(0xFF1A9BC0);
  static const orange = Color(0xFFD95926);
  static const violet = Color(0xFF8578E0);
  static const yellow = Color(0xFFC98500);
  static const green = Color(0xFF2FA574);
}

/// One line in a chart.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
  });

  final String label;
  final Color color;
  final List<SeriesPoint> points;

  double? get last => points.isEmpty ? null : points.last.value;
}

/// How a value is written on the axis, in the legend and in the tooltip.
enum ChartUnit { percent, bytesPerSecond, count }

/// One native chart: a title, a unit and the lines to draw.
class ChartPanel {
  const ChartPanel({
    required this.key,
    required this.title,
    required this.unit,
    required this.series,
    this.fixedMax,
  });

  final String key;
  final String title;
  final ChartUnit unit;
  final List<ChartSeries> series;

  /// Pins the top of the axis (100 for percentages); `null` fits the data.
  final double? fixedMax;

  bool get hasData => series.any((s) => s.points.isNotEmpty);
}

/// `up` per Prometheus scrape job, for the exporter health row.
class ExporterHealth {
  const ExporterHealth({required this.job, required this.up});

  final String job;
  final bool up;
}

/// Per-protocol user series: `.env` service name, display label, colour.
const userSeries = <String, (String, Color)>{
  'users_singbox': ('sing-box', ChartPalette.cyan),
  'users_xray': ('xray', ChartPalette.orange),
  'users_wireguard': ('wireguard', ChartPalette.violet),
  'users_amneziawg': ('amneziawg', ChartPalette.yellow),
  'users_conduit': ('conduit', ChartPalette.green),
};

/// Turns the flat series list into the handful of panels the Analytics tab
/// draws. Panels whose queries returned nothing are left out, so a box
/// without, say, the xray exporter simply shows fewer lines.
List<ChartPanel> chartPanels(ChartsSnapshot snapshot) {
  ChartSeries? single(String key, String label, Color color) {
    final s = snapshot.named(key);
    if (s.isEmpty || s.first.points.isEmpty) return null;
    return ChartSeries(label: label, color: color, points: s.first.points);
  }

  final panels = <ChartPanel>[];
  final cpu = single('cpu_percent', 'CPU', ChartPalette.cyan);
  if (cpu != null) {
    panels.add(ChartPanel(
      key: 'cpu',
      title: 'CPU',
      unit: ChartUnit.percent,
      series: [cpu],
      fixedMax: 100,
    ));
  }
  final mem = single('mem_percent', 'RAM used', ChartPalette.violet);
  if (mem != null) {
    panels.add(ChartPanel(
      key: 'mem',
      title: 'RAM used',
      unit: ChartUnit.percent,
      series: [mem],
      fixedMax: 100,
    ));
  }
  final net = [
    single('rx_bytes_per_s', 'Inbound', ChartPalette.cyan),
    single('tx_bytes_per_s', 'Outbound', ChartPalette.orange),
  ].whereType<ChartSeries>().toList();
  if (net.isNotEmpty) {
    panels.add(ChartPanel(
      key: 'net',
      title: 'Network',
      unit: ChartUnit.bytesPerSecond,
      series: net,
    ));
  }
  final users = [
    for (final e in userSeries.entries) single(e.key, e.value.$1, e.value.$2),
  ].whereType<ChartSeries>().toList();
  if (users.isNotEmpty) {
    panels.add(ChartPanel(
      key: 'users',
      title: 'Active users',
      unit: ChartUnit.count,
      series: users,
    ));
  }
  return panels;
}

/// Exporter health from the `sum by (job)(up)` vector, sorted by job.
List<ExporterHealth> exporterHealth(ChartsSnapshot snapshot) {
  final rows = [
    for (final s in snapshot.named(MoavCli.exporterHealthKey))
      if (s.label != null && s.last != null)
        ExporterHealth(job: s.label!, up: s.last! >= 1),
  ]..sort((a, b) => a.job.compareTo(b.job));
  return rows;
}

/// Axis / legend / tooltip formatting per [ChartUnit].
String formatChartValue(double v, ChartUnit unit) => switch (unit) {
      ChartUnit.percent => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}%',
      ChartUnit.bytesPerSecond => '${formatBytes(v)}/s',
      ChartUnit.count => v.toStringAsFixed(0),
    };

String formatBytes(double b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// The top of the y axis: [ChartPanel.fixedMax], or the data maximum with
/// headroom so the highest point never touches the frame.
double chartMax(ChartPanel panel) {
  final fixed = panel.fixedMax;
  if (fixed != null) return fixed;
  var max = 0.0;
  for (final s in panel.series) {
    for (final p in s.points) {
      if (p.value > max) max = p.value;
    }
  }
  if (max <= 0) return 1;
  return max * 1.15;
}
