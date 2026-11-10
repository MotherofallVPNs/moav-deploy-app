import 'package:flutter/material.dart';

import '../../theme/moav_theme.dart';

/// Copy shared by the Add Server screen and the servers empty state.
const tryDemoLabel = 'Try a demo server';
const demoHintTitle = 'New here?';
const demoHintBody = 'Install a dummy server to explore';

/// The badge every demo surface wears, so it can never pass for a real box.
class DemoPill extends StatelessWidget {
  const DemoPill({super.key});

  @override
  Widget build(BuildContext context) => const StatusPill(
        'demo',
        tone: StatusTone.accent,
        icon: Icons.science_outlined,
      );
}

/// What the Grafana and admin screens show for the demo instead of opening
/// a tunnel: there is nothing behind the demo to load.
class DemoUnavailable extends StatelessWidget {
  const DemoUnavailable({super.key, required this.what});

  /// `Grafana` or `the admin dashboard`.
  final String what;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: MoavCard(
            accent: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    IconBadge(Icons.science_outlined, gradient: true),
                    SizedBox(width: 12),
                    Expanded(child: Text('Demo server')),
                    DemoPill(),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Nothing runs behind the demo, so there is no $what to '
                  'open here. On a real server this page loads it through '
                  'the SSH connection, signed in with the password from .env.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The nudge on the Add Server screen: a short line for newcomers and the
/// demo button, with an arrow that beckons a few times and then rests.
class DemoHint extends StatefulWidget {
  const DemoHint({super.key, required this.onTry, this.busy = false});

  final VoidCallback onTry;
  final bool busy;

  /// How often the arrow beckons before it settles. Finite so the screen
  /// can settle in tests and the hint stays calm.
  static const nudges = 4;

  @override
  State<DemoHint> createState() => _DemoHintState();
}

class _DemoHintState extends State<DemoHint> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );
  var _cycles = 0;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      } else if (status == AnimationStatus.dismissed &&
          ++_cycles < DemoHint.nudges) {
        _controller.forward();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      key: const ValueKey('demo-hint'),
      accent: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Icons.auto_awesome, size: 30, gradient: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(demoHintTitle, style: theme.textTheme.titleSmall),
                    Text(demoHintBody, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedBuilder(
                animation: _slide,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_slide.value * 6, 0),
                  child: child,
                ),
                child: Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: MoavColors.cyan,
                  shadows: moavGlow(blur: 10, alpha: 0.6),
                ),
              ),
              const SizedBox(width: 10),
              GradientButton(
                key: const ValueKey('try-demo'),
                onPressed: widget.busy ? null : widget.onTry,
                busy: widget.busy,
                icon: Icons.science_outlined,
                label: tryDemoLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
