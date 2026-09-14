import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../core/ssh_moav_controller.dart';
import 'grafana_screen.dart';
import 'operate_provider.dart';

enum OperateTab { services, health, monitoring }

/// Operate & monitor one server: service controls, doctor health, Grafana.
class OperateScreen extends ConsumerWidget {
  const OperateScreen({
    super.key,
    required this.profile,
    this.initialTab = OperateTab.services,
  });

  final ServerProfile profile;
  final OperateTab initialTab;

  static Route<void> route(ServerProfile profile, {OperateTab tab = OperateTab.services}) =>
      MaterialPageRoute(
        builder: (_) => OperateScreen(profile: profile, initialTab: tab),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: OperateTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Operate · ${profile.label}'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Services', icon: Icon(Icons.settings_outlined)),
            Tab(text: 'Health', icon: Icon(Icons.monitor_heart_outlined)),
            Tab(text: 'Monitoring', icon: Icon(Icons.insights_outlined)),
          ]),
        ),
        body: TabBarView(children: [
          _ServicesTab(profile: profile),
          _HealthTab(profile: profile),
          _MonitoringTab(profile: profile),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusProvider(profile.id));
    final actions = ref.watch(serviceActionsProvider(profile.id));
    final notifier = ref.read(serviceActionsProvider(profile.id).notifier);

    ref.listen(serviceActionsProvider(profile.id), (prev, next) {
      final text = next.error ?? next.message;
      if (text != null && text != (prev?.error ?? prev?.message)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    });

    Future<void> confirmAndRun(ServiceAction a, {String? warning}) async {
      if (warning != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${ServiceActionsNotifier.describe(a)}?'),
            content: Text(warning),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (ok != true) return;
      }
      await notifier.run(a);
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(statusProvider(profile.id).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (actions.busy)
            ListTile(
              leading: const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('${ServiceActionsNotifier.describe(actions.running!)}…'),
              subtitle: const Text('This can take a minute'),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: actions.busy ? null : () => confirmAndRun(ServiceAction.start),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start all'),
              ),
              FilledButton.tonalIcon(
                onPressed: actions.busy
                    ? null
                    : () => confirmAndRun(
                          ServiceAction.restart,
                          warning: 'Every client will briefly disconnect while '
                              'services restart.',
                        ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart all'),
              ),
              FilledButton.tonalIcon(
                onPressed: actions.busy
                    ? null
                    : () => confirmAndRun(
                          ServiceAction.stop,
                          warning: 'All VPN services stop and every client '
                              'loses connectivity until you start them again.',
                        ),
                icon: const Icon(Icons.stop),
                label: const Text('Stop all'),
              ),
              OutlinedButton.icon(
                onPressed: actions.busy
                    ? null
                    : () => confirmAndRun(
                          ServiceAction.regenerateUsers,
                          warning: 'Rebuilds every user bundle from the current '
                              '.env. Existing keys are kept; users may need to '
                              're-import configs if server settings changed.',
                        ),
                icon: const Icon(Icons.autorenew),
                label: const Text('Regenerate users'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          status.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            error: (e, _) => _ErrorTile(
              message: SshMoavController.describeError(e),
              onRetry: () => ref.invalidate(statusProvider(profile.id)),
            ),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MoaV ${s.version ?? ''} · ${s.runningCount} of ${s.services.length} running',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (s.defaultProfiles.isNotEmpty)
                  Text('Profiles: ${s.defaultProfiles.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final svc in s.services)
                  _ServiceTile(
                    service: svc,
                    busy: actions.busy,
                    onAction: (kind) => confirmAndRun(
                      ServiceAction(kind, service: svc.name),
                      warning: kind == ServiceActionKind.start
                          ? null
                          : '${svc.name} will ${kind == ServiceActionKind.stop ? 'stop' : 'restart'}. '
                              'Clients on it will disconnect.',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.busy,
    required this.onAction,
  });

  final ServiceStatus service;
  final bool busy;
  final void Function(ServiceActionKind) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (service.state) {
      ServiceState.running => (Icons.circle, Colors.green, 'running'),
      ServiceState.exited => (Icons.circle_outlined, scheme.outline, 'exited'),
      ServiceState.stopped => (Icons.circle, scheme.error, 'stopped'),
      ServiceState.never => (Icons.remove, scheme.outline, 'never started'),
      ServiceState.unknown => (Icons.help_outline, scheme.outline, 'unknown'),
    };
    final parts = [
      label,
      if (service.uptime != null) 'up ${service.uptime}',
      if (service.ports.isNotEmpty) 'ports ${service.ports.join(', ')}',
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 16),
      title: Text(service.name),
      subtitle: Text(parts.join(' · ')),
      trailing: PopupMenuButton<ServiceActionKind>(
        enabled: !busy,
        onSelected: onAction,
        itemBuilder: (_) => const [
          PopupMenuItem(value: ServiceActionKind.restart, child: Text('Restart')),
          PopupMenuItem(value: ServiceActionKind.stop, child: Text('Stop')),
          PopupMenuItem(value: ServiceActionKind.start, child: Text('Start')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Health (moav doctor)
// ---------------------------------------------------------------------------

class _HealthTab extends ConsumerWidget {
  const _HealthTab({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(profile.id));
    return doctor.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Running moav doctor… (about 30 s)'),
          ],
        ),
      ),
      error: (e, _) => _ErrorTile(
        message: SshMoavController.describeError(e),
        onRetry: () => ref.invalidate(doctorProvider(profile.id)),
      ),
      data: (r) {
        final fails = r.checks.where((c) => c.result == CheckResult.fail).length;
        final warns = r.checks.where((c) => c.result == CheckResult.warn).length;
        return RefreshIndicator(
          onRefresh: () => ref.refresh(doctorProvider(profile.id).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.healthy ? Icons.check_circle : Icons.error,
                  color: r.healthy ? Colors.green : Theme.of(context).colorScheme.error,
                  size: 32,
                ),
                title: Text(r.healthy ? 'Healthy' : '$fails check(s) failing'),
                subtitle: Text(
                  '${r.checks.length} checks · $warns warning(s) · '
                  '${TimeOfDay.fromDateTime(r.collectedAt).format(context)}',
                ),
              ),
              for (final c in r.checks) _CheckTile(check: c),
            ],
          ),
        );
      },
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final DoctorCheck check;

  @override
  Widget build(BuildContext context) {
    final lines = (check.detail ?? '').split('\n');
    final description = lines.isEmpty ? '' : lines.first;
    final body = lines.skip(1).join('\n');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: ResultIcon(check.result),
      title: Text(check.name),
      subtitle: Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        if (body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            child: SelectableText(
              body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }
}

/// Coloured pass/warn/fail/skip icon shared by health and test views.
class ResultIcon extends StatelessWidget {
  const ResultIcon(this.result, {super.key});

  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (result) {
      CheckResult.pass => const Icon(Icons.check_circle, color: Colors.green),
      CheckResult.warn => const Icon(Icons.warning_amber, color: Colors.orange),
      CheckResult.fail => Icon(Icons.cancel, color: scheme.error),
      CheckResult.skip => Icon(Icons.remove_circle_outline, color: scheme.outline),
    };
  }
}

// ---------------------------------------------------------------------------
// Monitoring (Grafana)
// ---------------------------------------------------------------------------

class _MonitoringTab extends ConsumerWidget {
  const _MonitoringTab({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mon = ref.watch(monitoringProvider(profile.id));
    return mon.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorTile(
        message: SshMoavController.describeError(e),
        onRetry: () => ref.invalidate(monitoringProvider(profile.id)),
      ),
      data: (m) => RefreshIndicator(
        onRefresh: () => ref.refresh(monitoringProvider(profile.id).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _GrafanaCard(monitoring: m),
            if (m.metrics.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Headline metrics', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [for (final x in m.metrics) _MetricTile(metric: x)],
              ),
            ] else ...[
              const SizedBox(height: 16),
              const Text(
                'No Prometheus metrics. Enable the monitoring profile '
                '(moav start monitoring) to see headline numbers here.',
              ),
            ],
            if (m.adminUrl != null) ...[
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Admin dashboard'),
                subtitle: Text(m.adminUrl.toString()),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(m.adminUrl!, mode: LaunchMode.externalApplication),
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
    final (icon, text) = switch (m.grafanaHealthy) {
      true => (const Icon(Icons.check_circle, color: Colors.green),
          'Grafana ${m.grafanaVersion ?? ''} is up'),
      false => (Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
          'Grafana is not responding'),
      null => (const Icon(Icons.help_outline), 'Grafana status unknown'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              icon,
              const SizedBox(width: 8),
              Expanded(child: Text(text.trim(), style: Theme.of(context).textTheme.titleMedium)),
            ]),
            if (url != null) ...[
              const SizedBox(height: 4),
              SelectableText(url.toString(), style: Theme.of(context).textTheme.bodySmall),
            ],
            if (m.grafanaCdnUrl != null)
              SelectableText('via CDN: ${m.grafanaCdnUrl}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: url == null
                    ? null
                    : () => Navigator.of(context).push(GrafanaScreen.route(url)),
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Open Grafana'),
              ),
              OutlinedButton.icon(
                onPressed: url == null
                    ? null
                    : () => launchUrl(url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('In browser'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final Metric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(metric.name, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '${metric.value}${metric.unit ?? ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
