import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/cached_view.dart';
import 'analytics_view.dart';
import 'operate_provider.dart';
import 'server_info_view.dart';

enum OperateTab { services, health, monitoring, server }

/// Operate & monitor one server: service controls, doctor health, analytics,
/// host info and updates. Every tab reads a cached [FetchState]: switching
/// away never cancels a fetch, coming back renders the last result at once.
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
      child: MoavScaffold(
        appBar: AppBar(
          title: Text(profile.label),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => _refreshTab(ref, DefaultTabController.of(ctx).index),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Services'),
              Tab(text: 'Health'),
              Tab(text: 'Analytics'),
              Tab(text: 'Server'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _ServicesTab(profile: profile),
          _HealthTab(profile: profile),
          AnalyticsView(profile: profile),
          ServerInfoView(profile: profile),
        ]),
      ),
    );
  }

  void _refreshTab(WidgetRef ref, int index) {
    final id = profile.id;
    switch (OperateTab.values[index]) {
      case OperateTab.services:
        ref.read(statusProvider(id).notifier).refresh();
      case OperateTab.health:
        ref.read(doctorProvider(id).notifier).refresh();
      case OperateTab.monitoring:
        ref.read(monitoringProvider(id).notifier).refresh();
        ref.read(metricsProvider(id).notifier).refresh();
        ref.read(statusProvider(id).notifier).refresh();
      case OperateTab.server:
        ref.read(serverInfoProvider(id).notifier).refresh();
    }
  }
}

/// Kicks a background refresh when a tab (re)opens with a stale cache.
class StaleRefresher extends ConsumerStatefulWidget {
  const StaleRefresher({super.key, required this.onOpen, required this.child});

  final void Function(WidgetRef ref) onOpen;
  final Widget child;

  @override
  ConsumerState<StaleRefresher> createState() => _StaleRefresherState();
}

class _StaleRefresherState extends ConsumerState<StaleRefresher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOpen(ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// --- Services ---

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusProvider(profile.id));
    final statusNotifier = ref.read(statusProvider(profile.id).notifier);
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

    return StaleRefresher(
      onOpen: (ref) => ref
          .read(statusProvider(profile.id).notifier)
          .refreshIfStale(tabStaleAfter),
      child: CachedView<ServiceStatusReport>(
        state: status,
        onRefresh: statusNotifier.refresh,
        loadingLabel: 'Reading moav status…',
        builder: (context, s) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (actions.busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MoavCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${ServiceActionsNotifier.describe(actions.running!)}…'),
                            Text('This can take a minute', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _SummaryCard(report: s, fetchedAt: status.fetchedAt),
            const SectionHeader('Actions', padding: EdgeInsets.only(top: 16, bottom: 8)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: actions.busy ? null : () => confirmAndRun(ServiceAction.start),
                  icon: const Icon(Icons.play_arrow, size: 18),
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
                  icon: const Icon(Icons.restart_alt, size: 18),
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
                  icon: const Icon(Icons.stop, size: 18),
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
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Regenerate users'),
                ),
              ],
            ),
            const SectionHeader('Services', padding: EdgeInsets.only(top: 20, bottom: 8)),
            MoavCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, svc) in s.services.indexed) ...[
                    if (i > 0) const Divider(),
                    _ServiceRow(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report, this.fetchedAt});

  final ServiceStatusReport report;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final s = report;
    final allUp = s.runningCount == s.services.length;
    return MoavCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s.runningCount} / ${s.services.length}',
                style: moavMono(size: 30, weight: FontWeight.w600, height: 1),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('services running', style: moavLabel(size: 10)),
              ),
              const Spacer(),
              StatusPill(
                allUp ? 'all up' : '${s.services.length - s.runningCount} down',
                tone: allUp ? StatusTone.pass : StatusTone.warn,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (s.version != null)
                Text('MoaV v${s.version}', style: moavMono(size: 12, color: MoavColors.cyan)),
              if (s.version != null && s.defaultProfiles.isNotEmpty)
                Text('  ·  ', style: moavMono(size: 12, color: MoavColors.textMuted)),
              if (s.defaultProfiles.isNotEmpty)
                Expanded(
                  child: Text(
                    s.defaultProfiles.join(' '),
                    style: moavMono(size: 12, weight: FontWeight.w400, color: MoavColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (s.defaultProfiles.isEmpty) const Spacer(),
              updatedAt(context, fetchedAt),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.busy,
    required this.onAction,
  });

  final ServiceStatus service;
  final bool busy;
  final void Function(ServiceActionKind) onAction;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = switch (service.state) {
      ServiceState.running => (StatusTone.pass, 'running'),
      ServiceState.unhealthy => (StatusTone.warn, 'unhealthy'),
      ServiceState.starting => (StatusTone.warn, 'starting'),
      ServiceState.exited => (StatusTone.neutral, 'exited'),
      ServiceState.stopped => (StatusTone.fail, 'stopped'),
      ServiceState.never => (StatusTone.neutral, 'never'),
      ServiceState.unknown => (StatusTone.warn, 'unknown'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name, style: moavMono(size: 13, weight: FontWeight.w600)),
                if (service.ports.isNotEmpty)
                  Text(
                    service.ports.join(', '),
                    style: moavMono(size: 10.5, weight: FontWeight.w400, color: MoavColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              service.uptime ?? '-',
              textAlign: TextAlign.right,
              style: moavMono(size: 11, weight: FontWeight.w400, color: MoavColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          StatusPill(label, tone: tone),
          PopupMenuButton<ServiceActionKind>(
            enabled: !busy,
            onSelected: onAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: ServiceActionKind.restart, child: Text('Restart')),
              PopupMenuItem(value: ServiceActionKind.stop, child: Text('Stop')),
              PopupMenuItem(value: ServiceActionKind.start, child: Text('Start')),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Health (moav doctor) ---

class _HealthTab extends ConsumerWidget {
  const _HealthTab({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(profile.id));
    final notifier = ref.read(doctorProvider(profile.id).notifier);
    return StaleRefresher(
      onOpen: (ref) => ref
          .read(doctorProvider(profile.id).notifier)
          .refreshIfStale(tabStaleAfter),
      child: CachedView<DoctorReport>(
        state: doctor,
        onRefresh: notifier.refresh,
        loadingLabel: 'Running moav doctor… (about 30 s)',
        builder: (context, r) {
          final pass = r.checks.where((c) => c.result == CheckResult.pass).length;
          final fails = r.checks.where((c) => c.result == CheckResult.fail).length;
          final warns = r.checks.where((c) => c.result == CheckResult.warn).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              MoavCard(
                accent: true,
                glow: r.healthy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.healthy
                                ? (warns > 0
                                    ? '$warns ${warns == 1 ? 'warning' : 'warnings'}, nothing failing'
                                    : 'All checks passing')
                                : '$fails ${fails == 1 ? 'check' : 'checks'} failing',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusPill.result(
                          r.healthy
                              ? (warns > 0 ? CheckResult.warn : CheckResult.pass)
                              : CheckResult.fail,
                          label: r.healthy ? (warns > 0 ? 'degraded' : 'healthy') : 'unhealthy',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r.checks.length} checks · moav doctor · '
                      '${TimeOfDay.fromDateTime(r.collectedAt).format(context)}',
                      style: moavMono(size: 11, weight: FontWeight.w400, color: MoavColors.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _Count('pass', pass, MoavColors.pass),
                        _Count('warn', warns, MoavColors.warn),
                        _Count('fail', fails, MoavColors.fail),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionHeader('Checks'),
              MoavCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, c) in r.checks.indexed) ...[
                      if (i > 0) const Divider(),
                      _CheckTile(check: c),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.n, this.color);

  final String label;
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$n', style: moavMono(size: 20, weight: FontWeight.w600, color: n == 0 ? MoavColors.textMuted : MoavColors.text)),
          const SizedBox(width: 6),
          Text(label, style: moavLabel(size: 10, color: MoavColors.textMuted)),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final DoctorCheck check;

  @override
  Widget build(BuildContext context) {
    final lines = (check.detail ?? '').split('\n');
    final description = lines.first;
    final body = lines.skip(1).join('\n');
    return ExpansionTile(
      tilePadding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      leading: StatusPill.result(check.result),
      title: Text(check.name, style: moavMono(size: 13, weight: FontWeight.w600)),
      subtitle: Text(
        description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        if (body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: CodeBlock(body, size: 11),
          ),
      ],
    );
  }
}
