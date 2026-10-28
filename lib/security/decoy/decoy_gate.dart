import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notes/notes_app.dart';
import 'decoy_provider.dart';

/// Chooses between the Notes decoy and the real app.
///
/// With disguise off this is transparent. With it on, the Notes app is the
/// only thing on screen until the passcode check sets
/// [decoyRevealedProvider]; the real app (with its own lock gate) is then
/// built in its place. Leaving the app ([AppLifecycleState.paused]) drops
/// the reveal, so the next resume starts at Notes again and no MoaV lock
/// prompt can appear over the decoy. While the app is merely inactive (the
/// task-switcher snapshot) a plain cover hides the real content.
class DecoyGate extends ConsumerStatefulWidget {
  const DecoyGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DecoyGate> createState() => _DecoyGateState();
}

class _DecoyGateState extends ConsumerState<DecoyGate>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(decoyProvider.notifier).reconcileIdentity();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        setState(() => _obscured = false);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        setState(() => _obscured = true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        setState(() => _obscured = true);
        if (ref.read(decoyProvider).enabled) {
          ref.read(decoyRevealedProvider.notifier).hide();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(decoyProvider.select((c) => c.enabled));
    final revealed = ref.watch(decoyRevealedProvider);
    final showNotes = enabled && !revealed;
    final covered = enabled && revealed && _obscured;
    // Always the same tree shape: toggling disguise from inside the real
    // app must not rebuild it (that would drop the settings screen).
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        if (showNotes)
          const NotesApp()
        else
          // Offstage under the cover: not painted, not read by screen readers.
          Visibility(
            visible: !covered,
            maintainState: true,
            child: widget.child,
          ),
        if (covered) const DecoyCover(),
      ],
    );
  }
}

/// Plain paper-coloured cover: what the task switcher sees while the real
/// app is revealed.
class DecoyCover extends StatelessWidget {
  const DecoyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    return ColoredBox(
      color: dark ? NotesColors.paperDark : NotesColors.paper,
    );
  }
}
