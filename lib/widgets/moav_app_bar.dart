import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/activity_provider.dart';
import '../features/activity/activity_screen.dart';
import '../theme/moav_theme.dart';

/// The app bar every screen uses: a plain [AppBar] with the global activity
/// indicator appended to its actions.
class MoavAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MoavAppBar({
    super.key,
    this.title,
    this.actions = const [],
    this.bottom,
    this.leading,
    this.showActivity = true,
  });

  final Widget? title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;

  /// Off on the activity screen itself.
  final bool showActivity;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      bottom: bottom,
      actions: [
        ...actions,
        if (showActivity) const ActivityIndicatorButton(),
      ],
    );
  }
}

/// Spins while any background operation is in flight; tapping opens the
/// activity screen with the current or last operation's log.
class ActivityIndicatorButton extends ConsumerStatefulWidget {
  const ActivityIndicatorButton({super.key});

  @override
  ConsumerState<ActivityIndicatorButton> createState() =>
      _ActivityIndicatorButtonState();
}

class _ActivityIndicatorButtonState extends ConsumerState<ActivityIndicatorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityProvider);
    final busy = activity.busy;
    if (busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!busy && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
    final n = activity.runningCount;
    final tooltip = busy
        ? '$n ${n == 1 ? 'operation' : 'operations'} running'
        : 'Activity';
    return IconButton(
      key: ValueKey(busy ? 'activity-busy' : 'activity-idle'),
      tooltip: tooltip,
      onPressed: () => Navigator.of(context).push(ActivityScreen.route()),
      icon: RotationTransition(
        turns: _spin,
        child: Icon(
          Icons.sync,
          size: 20,
          color: busy ? MoavColors.cyan : MoavColors.textMuted,
        ),
      ),
    );
  }
}
