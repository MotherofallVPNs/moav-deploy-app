import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'grafana_screen.dart';
import 'operate_provider.dart';

/// Analytics tab: Grafana health, a grid of headline metric tiles from
/// Prometheus, per-protocol status derived from `moav status`, and Grafana
/// embedded inline. Read-only; everything comes from existing providers.
class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key, required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mon = ref.watch(monitoringProvider(profile.id));
    final status = ref.watch(statusProvider(profile.id));
    return mon.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(monitoringProvider(profile.id)),
      ),
      data: (m) => RefreshIndicator(
        onRefresh: () {
          ref.invalidate(statusProvider(profile.id));
          return ref.refresh(monitoringProvider(profile.id).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _GrafanaCard(monitoring: m),
            SectionHeader(
              'Headline metrics',
              trailing: m.collectedAt == null
                  ? null
                  : Text(
                      TimeOfDay.fromDateTime(m.collectedAt!).format(context),
                      style: moavLabel(size: 10, color: MoavColors.textMuted),
                    ),
            ),
            if (m.metrics.isNotEmpty)
              _MetricGrid(tiles: analyticsTiles(m.metrics))
            else
              const MoavCard(
                child: Text(
                  'No Prometheus metrics. Enable the monitoring profile '
                  '(moav start monitoring) to see headline numbers here.',
                ),
              ),
            const SectionHeader('Protocols'),
            status.when(
              loading: () => const MoavCard(
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
              ),
              error: (e, _) => MoavCard(child: ErrorBanner(error: e)),
              data: (s) => _ProtocolMatrix(report: s),
            ),
            if (m.grafanaUrl != null) ...[
              SectionHeader(
                'Grafana',
                trailing: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(GrafanaScreen.route(m.grafanaUrl!)),
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: const Text('Full screen'),
                ),
              ),
              MoavCard(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 320,
                  child: GrafanaPanel(url: m.grafanaUrl!, compact: true),
                ),
              ),
            ],
            if (m.adminUrl != null) ...[
              const SizedBox(height: 12),
              MoavCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                onTap: () => launchUrl(m.adminUrl!, mode: LaunchMode.externalApplication),
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
                    const Icon(Icons.open_in_new, size: 18, color: MoavColors.textMuted),
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

class _GrafanaCard extends StatelessWidget {
  const _GrafanaCard({required this.monitoring});

  final Monitoring monitoring;

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
              GradientButton(
                onPressed: url == null
                    ? null
                    : () => Navigator.of(context).push(GrafanaScreen.route(url)),
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
    final up = rows.where((r) => r.state == ServiceState.running).length;
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
