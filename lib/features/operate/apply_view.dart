import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../../widgets/log_view.dart';
import 'operate_provider.dart';

/// The detached rebuild job of one server, wherever a tab wants to show it:
/// progress and log tail while it runs, the result (with its exit code)
/// once it has ended, nothing when there is no job.
///
/// It also owns the "come back" moment: when the app returns to the
/// foreground the job is read again from the server's files, so a locked
/// phone or a dropped connection costs nothing but the time away.
class ApplyJobPanel extends ConsumerStatefulWidget {
  const ApplyJobPanel({super.key, required this.serverId, this.header});

  final String serverId;

  /// Section title shown above the card, only while there is one.
  final String? header;

  @override
  ConsumerState<ApplyJobPanel> createState() => _ApplyJobPanelState();
}

class _ApplyJobPanelState extends ConsumerState<ApplyJobPanel>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(applyProvider(widget.serverId).notifier).poll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final apply = ref.watch(applyProvider(widget.serverId));
    final notifier = ref.read(applyProvider(widget.serverId).notifier);
    final job = apply.job;
    final Widget body;
    if (job != null) {
      body = ApplyJobCard(
        state: apply,
        job: job,
        onRefresh: notifier.poll,
        onDismiss: notifier.dismiss,
      );
    } else if (apply.starting) {
      body = const MoavCard(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Starting the rebuild on the server…')),
          ],
        ),
      );
    } else if (apply.error != null) {
      body = ErrorBanner(error: apply.error!);
    } else {
      return const SizedBox.shrink();
    }
    final header = widget.header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) SectionHeader(header),
        body,
        const SizedBox(height: 12),
      ],
    );
  }
}

class ApplyJobCard extends StatelessWidget {
  const ApplyJobCard({
    super.key,
    required this.state,
    required this.job,
    required this.onRefresh,
    required this.onDismiss,
  });

  final ApplyState state;
  final InstallStatus job;
  final Future<void> Function() onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = state.running;
    final exit = state.status?.exitCode;
    final (label, tone, icon) = switch (job.phase) {
      InstallPhase.pending => ('Starting', StatusTone.neutral, Icons.schedule),
      InstallPhase.running => ('Running', StatusTone.accent, Icons.sync),
      InstallPhase.succeeded => ('Done', StatusTone.pass, Icons.check_circle_outline),
      InstallPhase.failed => ('Failed', StatusTone.fail, Icons.error_outline),
      InstallPhase.unknown => ('Unknown', StatusTone.warn, Icons.help_outline),
    };
    final step = job.step != null && job.totalSteps != null
        ? 'Step ${job.step} of ${job.totalSteps}: '
        : '';
    final message = switch (job.phase) {
      InstallPhase.pending || InstallPhase.running =>
        '$step${job.message ?? 'Waiting for the server…'}',
      _ => job.message ?? 'No result reported',
    };
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
                  state.spec?.label ?? 'Rebuild and restart',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (running)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRefresh,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: MoavColors.text),
          ),
          if (running) ...[
            const SizedBox(height: 4),
            Text(
              'Runs on the server. Safe to leave the app or lock the phone: '
              'the result will be here when you come back.',
              style: theme.textTheme.bodySmall,
            ),
          ] else if (exit != null) ...[
            const SizedBox(height: 4),
            Text('Exit code $exit', style: moavMono(size: 11, color: MoavColors.textMuted)),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              // A build has no honest percentage: animate while it runs.
              value: running ? null : (job.phase == InstallPhase.succeeded ? 1.0 : job.progress ?? 0),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            ErrorBanner(
              error: state.error!,
              trailing: state.polling
                  ? 'The job keeps running on the server. Retrying automatically.'
                  : null,
            ),
          ],
          const SizedBox(height: 12),
          LogView(
            lines: job.logTail,
            height: 220,
            title: 'apply.log',
            highlightPrefix: '[moav-deploy]',
          ),
          if (!running) ...[
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

/// Shown while a pulled update has not been applied: the one prominent way
/// out of "updated but still on the old images".
class ApplyPendingCard extends StatelessWidget {
  const ApplyPendingCard({super.key, required this.onApply});

  final VoidCallback onApply;

  static const applyLabel = 'Apply now (rebuild + restart)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Icons.pending_actions_outlined, color: MoavColors.warn),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Update not applied yet', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'MoaV was updated on disk, but the services still run the previous '
            'images. Applying rebuilds the images, regenerates the user bundles '
            'and restarts the services. It runs on the server, so you can leave '
            'the app meanwhile.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          GradientButton(
            icon: Icons.build_circle_outlined,
            label: applyLabel,
            expand: true,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

/// Asks what to rebuild and how; `null` when cancelled. With [service] the
/// job is scoped to that one service, otherwise to every enabled profile.
Future<ApplySpec?> showRebuildDialog(BuildContext context, {String? service}) =>
    showDialog<ApplySpec>(
      context: context,
      builder: (_) => _RebuildDialog(service: service),
    );

class _RebuildDialog extends StatefulWidget {
  const _RebuildDialog({this.service});

  final String? service;

  @override
  State<_RebuildDialog> createState() => _RebuildDialogState();
}

class _RebuildDialogState extends State<_RebuildDialog> {
  bool _noCache = false;
  bool _regenerate = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final target = service ?? 'all services';
    return AlertDialog(
      title: Text('Rebuild and restart $target?'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service == null
                  ? 'Builds the images of every enabled profile, then starts '
                      'the services on them. Clients disconnect briefly while '
                      'containers are recreated.'
                  : 'Builds the image of $service, then starts it on the new '
                      'image. Clients on it disconnect briefly.',
            ),
            const SizedBox(height: 8),
            Text(
              'The job runs on the server and keeps going if you leave the app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Force rebuild'),
              subtitle: const Text('--no-cache: ignore cached layers. Slower.'),
              value: _noCache,
              onChanged: (v) => setState(() => _noCache = v),
            ),
            if (service == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Regenerate user bundles'),
                subtitle: const Text('moav regenerate-users before the start. Keys are kept.'),
                value: _regenerate,
                onChanged: (v) => setState(() => _regenerate = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ApplySpec(
              services: [?service],
              noCache: _noCache,
              regenerateUsers: _regenerate,
            ),
          ),
          child: const Text('Rebuild'),
        ),
      ],
    );
  }
}
