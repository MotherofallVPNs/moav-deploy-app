import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/error_view.dart';
import '../admin/admin_panel_screen.dart';
import 'charts_view.dart';
import 'grafana_screen.dart';
import 'operate_provider.dart';
import 'operate_screen.dart';

/// Analytics tab: Grafana health with the way into the full dashboards, a
/// grid of headline metric tiles from Prometheus, native charts over the
/// last hour, and per-protocol status derived from `moav status`. Read-only.
///
/// Four independent caches feed it: Grafana URLs/health (fast), Prometheus
/// metrics and chart series (slow, their own timeout and Retry) and
/// `moav status`. A slow or failing one never blocks the others.
class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key, required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = profile.id;
    final mon = ref.watch(monitoringProvider(id));
    final metrics = ref.watch(metricsProvider(id));
    final charts = ref.watch(chartsProvider(id));
    final status = ref.watch(statusProvider(id));

    Future<void> refreshAll() => Future.wait([
          ref.read(monitoringProvider(id).notifier).refresh(),
          ref.read(metricsProvider(id).notifier).refresh(),
          ref.read(chartsProvider(id).notifier).refresh(),
          ref.read(statusProvider(id).notifier).refresh(),
        ]);

    return StaleRefresher(
      onOpen: (ref) {
        ref.read(monitoringProvider(id).notifier).refreshIfStale(tabStaleAfter);
        ref.read(metricsProvider(id).notifier).refreshIfStale(tabStaleAfter);
        ref.read(chartsProvider(id).notifier).refreshIfStale(tabStaleAfter);
        ref.read(statusProvider(id).notifier).refreshIfStale(tabStaleAfter);
      },
      child: CachedView<Monitoring>(
        state: mon,
        onRefresh: refreshAll,
        loadingLabel: 'Checking Grafana…',
        builder: (context, m) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _GrafanaCard(monitoring: m, profile: profile),
            SectionHeader(
              'Headline metrics',
              trailing: _SectionRefresh(
                state: metrics,
                onRefresh: ref.read(metricsProvider(id).notifier).refresh,
              ),
            ),
            _MetricsSection(
              state: metrics,
              onRetry: ref.read(metricsProvider(id).notifier).refresh,
            ),
            SectionHeader(
              'Last hour',
              trailing: _SectionRefresh(
                state: charts,
                onRefresh: ref.read(chartsProvider(id).notifier).refresh,
              ),
            ),
            ChartsSection(
              state: charts,
              onRetry: ref.read(chartsProvider(id).notifier).refresh,
            ),
            SectionHeader(
              'Protocols',
              trailing: _SectionRefresh(
                state: status,
                onRefresh: ref.read(statusProvider(id).notifier).refresh,
              ),
            ),
            _StatusSection(
              state: status,
              onRetry: ref.read(statusProvider(id).notifier).refresh,
            ),
            if (m.adminUrl != null) ...[
              const SizedBox(height: 12),
              MoavCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                onTap: () =>
                    Navigator.of(context).push(AdminPanelScreen.route(profile)),
                child: Row(
                  children: [
                    const IconBadge(Icons.admin_panel_settings_outlined, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Admin dashboard'),
                          Text(
                            m.adminUrl.toString(),
                            style: moavMono(
                              size: 11,
                              weight: FontWeight.w400,
                              color: MoavColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: MoavColors.textMuted),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section-header trailing: "updated hh:mm" plus a refresh icon, or a tiny
/// spinner while that section is refreshing.
class _SectionRefresh extends StatelessWidget {
  const _SectionRefresh({required this.state, required this.onRefresh});

  final FetchState<Object> state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        updatedAt(context, state.fetchedAt),
        const SizedBox(width: 4),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
          ),
      ],
    );
  }
}

class _MetricsSection extends StatelessWidget {
  const _MetricsSection({required this.state, required this.onRetry});

  final FetchState<MetricsSnapshot> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final error = state.error;
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
        if (data != null)
          data.metrics.isNotEmpty
              ? _MetricGrid(tiles: analyticsTiles(data.metrics))
              : const MoavCard(
                  child: Text(
                    'No Prometheus metrics. Enable the monitoring profile '
                    '(moav start monitoring) to see headline numbers here.',
                  ),
                )
        else if (error == null)
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
                    'Querying Prometheus… this can take a while on a busy box.',
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

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.state, required this.onRetry});

  final FetchState<ServiceStatusReport> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final error = state.error;
    if (data != null) return _ProtocolMatrix(report: data);
    if (error != null) {
      return MoavCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(error: error),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }
    return const MoavCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _GrafanaCard extends StatelessWidget {
  const _GrafanaCard({required this.monitoring, required this.profile});

  final Monitoring monitoring;
  final ServerProfile profile;

  @override
  Widget build(BuildContext context) {
    final m = monitoring;
    final url = m.grafanaUrl;
    final (pill, text) = switch (m.grafanaHealthy) {
      true => (
          const StatusPill('up', tone: StatusTone.pass),
          'Grafana ${m.grafanaVersion ?? ''} is up',
        ),
      false => (
          const StatusPill('down', tone: StatusTone.fail),
          'Grafana is not responding',
        ),
      null => (
          const StatusPill('unknown', tone: StatusTone.neutral),
          'Grafana status unknown',
        ),
    };
    return MoavCard(
      accent: true,
      glow: m.grafanaHealthy == true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.insights_outlined, gradient: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text.trim(), style: Theme.of(context).textTheme.titleMedium),
                    if (url != null) ...[
                      const SizedBox(height: 2),
                      SelectableText(
                        url.toString(),
                        style: moavMono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: MoavColors.textSecondary,
                        ),
                      ),
                    ],
                    if (m.grafanaCdnUrl != null)
                      SelectableText(
                        'via CDN: ${m.grafanaCdnUrl}',
                        style: moavMono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: MoavColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              pill,
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // The in-app view goes through the SSH tunnel and signs in with
              // the .env password; the charts below are the native summary.
              GradientButton(
                onPressed: () =>
                    Navigator.of(context).push(GrafanaScreen.route(profile)),
                icon: Icons.dashboard_outlined,
                label: 'Open Grafana',
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: url == null
                    ? null
                    : () => launchUrl(url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('In browser'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles});

  final List<MetricTile> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: tiles,
    );
  }
}

/// Turns the flat headline [Metric] list into styled tiles: known metrics get
/// an icon and, where two metrics belong together (RAM available / total),
/// one tile; anything unknown falls back to a plain tile.
List<MetricTile> analyticsTiles(List<Metric> metrics) {
  final byName = {for (final m in metrics) m.name: m};
  final used = <String>{};
  final tiles = <MetricTile>[];

  MetricTile? take(
    String name, {
    required IconData icon,
    String? sub,
    bool accent = false,
    StatusTone? tone,
  }) {
    final m = byName[name];
    if (m == null) return null;
    used.add(name);
    return MetricTile(
      label: m.name,
      value: m.value,
      unit: m.unit,
      icon: icon,
      sub: sub,
      accent: accent,
      tone: tone,
    );
  }

  final exporters = take('Exporters up', icon: Icons.sensors, accent: true, sub: 'prometheus targets');
  final load = take('Load (1m)', icon: Icons.speed, sub: 'node_load1');
  final total = byName['RAM total'];
  if (total != null) used.add('RAM total');
  final ram = take(
    'RAM available',
    icon: Icons.memory,
    sub: total == null ? null : 'of ${total.value} total',
  );
  final rx = take('Inbound', icon: Icons.south_west, sub: '5m rate, all NICs');
  final tx = take('Outbound', icon: Icons.north_east, sub: '5m rate, all NICs');
  final disk = take('Disk free', icon: Icons.storage_outlined, sub: 'root filesystem');
  tiles.addAll([exporters, load, ram, disk, rx, tx].whereType<MetricTile>());

  for (final m in metrics) {
    if (used.contains(m.name)) continue;
    tiles.add(MetricTile(label: m.name, value: m.value, unit: m.unit, icon: Icons.data_usage));
  }
  return tiles;
}

/// Which client protocols a `moav status` service backs.
const protocolsByService = <String, List<String>>{
  'sing-box': ['reality', 'trojan', 'hysteria2', 'shadowsocks'],
  'xray': ['xhttp', 'xdns'],
  'wireguard': ['wireguard'],
  'wstunnel': ['wg-wstunnel'],
  'amneziawg': ['amneziawg'],
  'trusttunnel': ['trusttunnel'],
  'telemt': ['mtproxy'],
  'dnstt': ['dnstt'],
  'snowflake': ['snowflake'],
  'psiphon-conduit': ['conduit'],
  'slipstream': ['slipstream'],
};

/// One `(protocol, service, state)` row per protocol whose service is listed.
List<({String protocol, String service, ServiceState state})> protocolRows(
  ServiceStatusReport report,
) =>
    [
      for (final s in report.services)
        for (final p in protocolsByService[s.name] ?? const <String>[])
          (protocol: p, service: s.name, state: s.state),
    ];

StatusTone toneForService(ServiceState s) => switch (s) {
      ServiceState.running => StatusTone.pass,
      ServiceState.unhealthy || ServiceState.starting => StatusTone.warn,
      ServiceState.exited || ServiceState.stopped => StatusTone.fail,
      ServiceState.never => StatusTone.neutral,
      ServiceState.unknown => StatusTone.warn,
    };

class _ProtocolMatrix extends StatelessWidget {
  const _ProtocolMatrix({required this.report});

  final ServiceStatusReport report;

  @override
  Widget build(BuildContext context) {
    final rows = protocolRows(report);
    final up = rows.where((r) => r.state.isUp).length;
    if (rows.isEmpty) {
      return const MoavCard(child: Text('No protocol services listed by moav status.'));
    }
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text.rich(
                TextSpan(
                  text: '$up',
                  style: moavMono(size: 22, weight: FontWeight.w600),
                  children: [
                    TextSpan(
                      text: ' / ${rows.length} protocols up',
                      style: moavMono(size: 12, color: MoavColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${report.runningCount}/${report.services.length} services',
                style: moavLabel(size: 10, color: MoavColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rows)
                StatusPill(r.protocol, tone: toneForService(r.state)),
            ],
          ),
        ],
      ),
    );
  }
}
