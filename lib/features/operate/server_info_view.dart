import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/log_view.dart';
import '../admin/admin_panel_screen.dart';
import 'operate_provider.dart';
import 'operate_screen.dart';

/// Server tab: MoaV + component versions, a check-for-updates / update
/// flow that streams the detached `moav update` log, and host CPU, RAM,
/// swap and disk.
class ServerInfoView extends ConsumerWidget {
  const ServerInfoView({super.key, required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = profile.id;
    final info = ref.watch(serverInfoProvider(id));
    final infoNotifier = ref.read(serverInfoProvider(id).notifier);
    final update = ref.watch(updateProvider(id));
    final updateNotifier = ref.read(updateProvider(id).notifier);

    return StaleRefresher(
      onOpen: (ref) => ref
          .read(serverInfoProvider(id).notifier)
          .refreshIfStale(tabStaleAfter),
      child: CachedView<ServerInfo>(
        state: info,
        onRefresh: infoNotifier.refresh,
        loadingLabel: 'Reading host metrics and versions… (a few seconds)',
        builder: (context, s) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _VersionCard(
              info: s,
              fetchedAt: info.fetchedAt,
              update: update,
              onCheck: updateNotifier.check,
              onUpdate: () => _confirmUpdate(context, update, updateNotifier),
            ),
            if (update.job != null) ...[
              const SectionHeader('Update job'),
              _UpdateJobCard(
                state: update,
                onRefresh: updateNotifier.poll,
                onDismiss: updateNotifier.dismiss,
              ),
            ],
            const SectionHeader('Host'),
            _HostGrid(host: s.host),
            const SectionHeader('Web panel'),
            _AdminDashboardRow(profile: profile),
            if (s.version.components.isNotEmpty) ...[
              const SectionHeader('Components'),
              MoavCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, c) in s.version.components.indexed) ...[
                      if (i > 0) const Divider(),
                      _ComponentRow(component: c),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUpdate(
    BuildContext context,
    UpdateState state,
    UpdateNotifier notifier,
  ) async {
    final latest = state.check?.latestVersion;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(latest == null ? 'Update MoaV?' : 'Update MoaV to v$latest?'),
        content: const Text(
          'Runs moav update on the server in the background: git pull on the '
          'current branch, then the post-update checks. Local edits in '
          '/opt/moav are stashed, never discarded. Services are not rebuilt '
          'or restarted; the log lists any steps to apply afterwards.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );
    if (ok == true) await notifier.start();
  }
}

/// Opens the MoaV admin dashboard in-app, over the SSH session.
class _AdminDashboardRow extends StatelessWidget {
  const _AdminDashboardRow({required this.profile});

  final ServerProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => Navigator.of(context).push(AdminPanelScreen.route(profile)),
      child: Row(
        children: [
          const IconBadge(Icons.admin_panel_settings_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin dashboard', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'The MoaV web panel, through this SSH connection',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: MoavColors.textMuted),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.info,
    required this.fetchedAt,
    required this.update,
    required this.onCheck,
    required this.onUpdate,
  });

  final ServerInfo info;
  final DateTime? fetchedAt;
  final UpdateState update;
  final Future<void> Function() onCheck;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final v = info.version;
    final check = update.check;
    final theme = Theme.of(context);
    final busy = update.checking || update.starting || update.jobRunning;

    final Widget verdict;
    if (update.checkError != null) {
      verdict = ErrorBanner(error: update.checkError!);
    } else if (check == null) {
      verdict = Text(
        update.checking ? 'Asking GitHub for the latest release…' : 'Not checked yet',
        style: theme.textTheme.bodySmall,
      );
    } else {
      final (tone, icon) = check.updateAvailable
          ? (StatusTone.warn, Icons.new_releases_outlined)
          : check.unknown
              ? (StatusTone.neutral, Icons.help_outline)
              : (StatusTone.pass, Icons.check_circle_outline);
      verdict = Row(
        children: [
          Icon(icon, size: 16, color: tone.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              check.message ?? '',
              style: const TextStyle(color: MoavColors.text, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            TimeOfDay.fromDateTime(check.checkedAt).format(context),
            style: moavLabel(size: 10, color: MoavColors.textMuted),
          ),
        ],
      );
    }

    return MoavCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.dns_outlined, gradient: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.moavVersion == null ? 'MoaV' : 'MoaV v${v.moavVersion}',
                      style: moavMono(size: 20, weight: FontWeight.w600),
                    ),
                    if (v.branch != null || v.commit != null)
                      Text(
                        [v.branch, v.commit].whereType<String>().join(' @ '),
                        style: moavMono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: MoavColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (check?.updateAvailable == true)
                StatusPill('v${check!.latestVersion} available', tone: StatusTone.warn)
              else
                updatedAt(context, fetchedAt),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          verdict,
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onCheck,
                icon: update.checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt, size: 18),
                label: const Text('Check for updates'),
              ),
              if (check?.updateAvailable == true)
                GradientButton(
                  onPressed: busy ? null : onUpdate,
                  busy: update.starting,
                  icon: Icons.upgrade,
                  label: 'Update to v${check!.latestVersion}',
                ),
            ],
          ),
          if (update.jobError != null && update.job == null) ...[
            const SizedBox(height: 10),
            ErrorBanner(error: update.jobError!),
          ],
        ],
      ),
    );
  }
}

class _UpdateJobCard extends StatelessWidget {
  const _UpdateJobCard({
    required this.state,
    required this.onRefresh,
    required this.onDismiss,
  });

  final UpdateState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final job = state.job!;
    final lines = job.logTail;
    final (label, tone, icon) = switch (job.phase) {
      InstallPhase.pending => ('Starting', StatusTone.neutral, Icons.schedule),
      InstallPhase.running => ('Running', StatusTone.accent, Icons.sync),
      InstallPhase.succeeded => ('Done', StatusTone.pass, Icons.check_circle_outline),
      InstallPhase.failed => ('Failed', StatusTone.fail, Icons.error_outline),
      InstallPhase.unknown => ('Unknown', StatusTone.warn, Icons.help_outline),
    };
    final progress = job.phase == InstallPhase.succeeded ? 1.0 : job.progress;
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label, tone: tone, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  job.message ?? 'Waiting for the server…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: MoavColors.text,
                      ),
                ),
              ),
              if (state.jobRunning)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRefresh,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(minHeight: 6, value: progress),
          ),
          if (state.jobError != null) ...[
            const SizedBox(height: 10),
            ErrorBanner(
              error: state.jobError!,
              trailing: state.polling ? 'Retrying automatically.' : null,
            ),
          ],
          const SizedBox(height: 12),
          LogView(
            lines: lines,
            height: 220,
            title: 'update.log',
            highlightPrefix: '[moav-deploy]',
          ),
          if (job.isTerminal || job.phase == InstallPhase.unknown) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Warn from 80 % use, red from 90 %.
StatusTone? toneForUsage(double? usage) {
  if (usage == null) return null;
  if (usage >= 0.9) return StatusTone.fail;
  if (usage >= 0.8) return StatusTone.warn;
  return null;
}

String percent(double v) => '${(v * 100).round()}';

String formatBytes(int? b) {
  if (b == null) return '?';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String formatUptime(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

/// The host metric tiles, in display order. Only metrics the box reported.
List<MetricTile> hostTiles(HostMetrics h) {
  final tiles = <MetricTile>[];
  final cpu = h.cpuUsage;
  if (cpu != null) {
    tiles.add(MetricTile(
      label: 'CPU',
      value: percent(cpu),
      unit: '%',
      icon: Icons.developer_board,
      sub: h.cpuCount == null ? '1 s sample' : '${h.cpuCount} vCPU, 1 s sample',
      tone: toneForUsage(cpu),
      accent: true,
    ));
  }
  if (h.load1 != null) {
    final perCpu = h.cpuCount == null || h.cpuCount == 0
        ? null
        : h.load1! / h.cpuCount!;
    tiles.add(MetricTile(
      label: 'Load',
      value: h.load1!.toStringAsFixed(2),
      icon: Icons.speed,
      sub: '5m ${h.load5?.toStringAsFixed(2) ?? '?'} · 15m ${h.load15?.toStringAsFixed(2) ?? '?'}',
      tone: perCpu == null ? null : (perCpu >= 1.5 ? StatusTone.fail : perCpu >= 1 ? StatusTone.warn : null),
    ));
  }
  final mem = h.memUsage;
  if (mem != null) {
    tiles.add(MetricTile(
      label: 'RAM',
      value: percent(mem),
      unit: '%',
      icon: Icons.memory,
      sub: '${formatBytes(h.memAvailableBytes)} free of ${formatBytes(h.memTotalBytes)}',
      tone: toneForUsage(mem),
    ));
  }
  final disk = h.diskUsage;
  if (disk != null) {
    tiles.add(MetricTile(
      label: 'Disk',
      value: percent(disk),
      unit: '%',
      icon: Icons.storage_outlined,
      sub: '${formatBytes(h.diskAvailableBytes)} free of ${formatBytes(h.diskTotalBytes)}',
      tone: toneForUsage(disk),
    ));
  }
  final swap = h.swapUsage;
  if (swap != null && (h.swapTotalBytes ?? 0) > 0) {
    tiles.add(MetricTile(
      label: 'Swap',
      value: percent(swap),
      unit: '%',
      icon: Icons.swap_vert,
      sub: '${formatBytes((h.swapTotalBytes ?? 0) - (h.swapFreeBytes ?? 0))} of ${formatBytes(h.swapTotalBytes)}',
      tone: swap >= 0.5 ? StatusTone.warn : null,
    ));
  }
  if (h.uptime != null) {
    tiles.add(MetricTile(
      label: 'Uptime',
      value: formatUptime(h.uptime!),
      icon: Icons.timer_outlined,
      sub: 'since last boot',
    ));
  }
  return tiles;
}

class _HostGrid extends StatelessWidget {
  const _HostGrid({required this.host});

  final HostMetrics host;

  @override
  Widget build(BuildContext context) {
    final tiles = hostTiles(host);
    if (tiles.isEmpty) {
      return const MoavCard(
        child: Text('The server did not report host metrics (/proc unreadable?).'),
      );
    }
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

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component});

  final ComponentVersion component;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(component.name, style: moavMono(size: 13, weight: FontWeight.w600)),
                if (component.source != null)
                  Text(
                    component.source!,
                    style: moavMono(size: 10.5, weight: FontWeight.w400, color: MoavColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            component.version,
            style: moavMono(size: 12, color: MoavColors.cyan),
          ),
        ],
      ),
    );
  }
}
