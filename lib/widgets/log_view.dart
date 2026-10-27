import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/moav_theme.dart';

/// The one way the app shows command output and job logs: a mono block that
/// scrolls, follows new lines, can be selected, and has a Copy button.
///
/// With [height] set it is a fixed box for cards and dialogs; without it the
/// box fills the parent (wrap the widget in `Expanded`).
class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.lines,
    this.height,
    this.title,
    this.emptyText = 'No output yet',
    this.highlightPrefix,
    this.autoScroll = true,
    this.fontSize = 11,
  });

  final List<String> lines;
  final double? height;

  /// Optional caption above the block; the line count sits beside it.
  final String? title;
  final String emptyText;

  /// Lines starting with this are tinted cyan (the app's own markers).
  final String? highlightPrefix;

  /// Jump to the newest line whenever lines are added.
  final bool autoScroll;
  final double fontSize;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant LogView old) {
    super.didUpdateWidget(old);
    if (widget.autoScroll && old.lines.length != widget.lines.length) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final header = Row(
      children: [
        if (widget.title != null)
          Expanded(
            child: Text(widget.title!.toUpperCase(), style: moavLabel(size: 10)),
          )
        else
          const Spacer(),
        Text(
          '${lines.length} ${lines.length == 1 ? 'line' : 'lines'}',
          style: moavLabel(size: 10, color: MoavColors.textMuted),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('log-copy'),
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'Copy log',
          visualDensity: VisualDensity.compact,
          onPressed: lines.isEmpty ? null : () => _copy(context),
        ),
      ],
    );

    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: MoavColors.codeBg,
        borderRadius: MoavRadius.control,
        border: Border.all(color: MoavColors.border),
      ),
      child: lines.isEmpty
          ? Center(
              child: Text(
                widget.emptyText,
                style: moavMono(size: 12, color: MoavColors.textMuted),
              ),
            )
          : SelectionArea(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: lines.length,
                itemBuilder: (_, i) => Text(
                  lines[i],
                  style: moavMono(
                    size: widget.fontSize,
                    weight: FontWeight.w400,
                    color: widget.highlightPrefix != null &&
                            lines[i].startsWith(widget.highlightPrefix!)
                        ? MoavColors.cyan
                        : MoavColors.codeText,
                    height: 1.4,
                  ),
                ),
              ),
            ),
    );

    final height = widget.height;
    return Column(
      mainAxisSize: height == null ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (height == null)
          Expanded(child: body)
        else
          SizedBox(height: height, child: body),
      ],
    );
  }
}
