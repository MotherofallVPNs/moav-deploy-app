import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/moav_theme.dart';
import '../../widgets/log_view.dart';
import '../../widgets/moav_app_bar.dart';
import 'activity_provider.dart';

/// What the app is doing right now and what it did last: one operation's
/// streamed log, with the recent ones a tap away.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const ActivityScreen());

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    // Latch what was current on open so a follow-up fetch (status re-read
    // after a service action) does not steal the view.
    _selected = ref.read(activityProvider).current?.id;
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityProvider);
    final op = (_selected == null ? null : activity.byId(_selected!)) ??
        activity.current;
    return MoavScaffold(
      appBar: const MoavAppBar(title: Text('Activity'), showActivity: false),
      body: op == null
          ? const EmptyState(
              icon: Icons.sync,
              title: 'Nothing running',
              body: 'Service actions, updates and installs show their '
                  'output here while they run.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _OperationCard(op: op),
                ),
                if (activity.operations.length > 1)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      children: [
                        for (final o in activity.operations)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                o.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                              avatar: o.running
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                              selected: o.id == op.id,
                              onSelected: (_) =>
                                  setState(() => _selected = o.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: LogView(
                      key: ValueKey('activity-log-${op.id}'),
                      lines: op.lines,
                      title: 'output',
                      highlightPrefix: '[moav-deploy]',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.op});

  final Operation op;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (op.phase) {
      OperationPhase.running => ('Running', StatusTone.accent, Icons.sync),
      OperationPhase.done => ('Done', StatusTone.pass, Icons.check_circle_outline),
      OperationPhase.failed => ('Failed', StatusTone.fail, Icons.error_outline),
      OperationPhase.detached => ('Detached', StatusTone.neutral, Icons.link_off),
    };
    final elapsed = op.elapsed();
    final when = TimeOfDay.fromDateTime(op.startedAt).format(context);
    return MoavCard(
      accent: op.running,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label, tone: tone, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  op.label,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'started $when · ${_format(elapsed)}',
            style: moavMono(
              size: 11,
              weight: FontWeight.w400,
              color: MoavColors.textMuted,
            ),
          ),
          if (op.error != null) ...[
            const SizedBox(height: 8),
            Text(
              op.error!,
              style: const TextStyle(color: MoavColors.fail, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}
