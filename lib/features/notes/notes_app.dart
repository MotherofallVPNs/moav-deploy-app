import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../security/decoy/decoy_config.dart';
import '../../security/decoy/decoy_pin.dart';
import '../../security/decoy/decoy_provider.dart';
import 'notes_store.dart';

/// Colours of the Notes decoy. Warm paper tones, nothing from the MoaV
/// palette, no bundled brand font: it must read as an ordinary notes app.
abstract final class NotesColors {
  static const seed = Color(0xFFF2B705);
  static const paper = Color(0xFFFFFDF7);
  static const paperDark = Color(0xFF1C1B18);
}

ThemeData notesTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: NotesColors.seed,
    brightness: brightness,
  );
  final surface =
      brightness == Brightness.light ? NotesColors.paper : NotesColors.paperDark;
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    useMaterial3: true,
  );
}

/// The decoy front: a small, working notes app. [onReveal] is not used by
/// the UI directly; the passcode check in [DecoyNotifier] flips the gate.
class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Also the task-switcher label on Android.
      title: 'Notes',
      theme: notesTheme(Brightness.light),
      darkTheme: notesTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const NotesHomeScreen(),
    );
  }
}

class NotesHomeScreen extends ConsumerWidget {
  const NotesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final gesture = ref.watch(decoyProvider.select((c) => c.gesture));
    return Scaffold(
      appBar: AppBar(
        title: NotesTitle(
          gesture: gesture,
          onTrigger: () => showPasscodeSheet(context),
        ),
      ),
      body: notes.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const _NotesEmpty(),
        data: (list) => list.isEmpty
            ? const _NotesEmpty()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NoteTile(note: list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New note',
        onPressed: () => Navigator.of(context).push(NoteEditorScreen.route()),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

/// The app bar title that doubles as the secret trigger.
class NotesTitle extends StatefulWidget {
  const NotesTitle({super.key, required this.gesture, required this.onTrigger});

  final DecoyGesture gesture;
  final VoidCallback onTrigger;

  /// Taps further apart than this restart the five-tap count.
  static const tapWindow = Duration(milliseconds: 600);
  static const tapsNeeded = 5;

  @override
  State<NotesTitle> createState() => _NotesTitleState();
}

class _NotesTitleState extends State<NotesTitle> {
  int _taps = 0;
  DateTime? _lastTap;

  void _tap() {
    if (widget.gesture != DecoyGesture.tapTitleFiveTimes) return;
    final now = DateTime.now();
    final last = _lastTap;
    _taps = last != null && now.difference(last) <= NotesTitle.tapWindow
        ? _taps + 1
        : 1;
    _lastTap = now;
    if (_taps >= NotesTitle.tapsNeeded) {
      _taps = 0;
      _lastTap = null;
      widget.onTrigger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      onLongPress: widget.gesture == DecoyGesture.longPressTitle
          ? widget.onTrigger
          : null,
      // A generic label: screen readers must not announce anything else.
      child: const Text('Notes'),
    );
  }
}

class _NotesEmpty extends StatelessWidget {
  const _NotesEmpty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 56, color: muted),
            const SizedBox(height: 16),
            Text('No notes yet', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Tap the pencil to write your first note.',
              style: text.bodyMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    final snippet = note.body.trim().split('\n').first;
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => ref.read(notesProvider.notifier).remove(note.id),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              Navigator.of(context).push(NoteEditorScreen.route(note: note)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      formatNoteDate(note.updatedAt),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          snippet,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "14:05" for today, "3 Mar" this year, "3 Mar 2025" otherwise.
String formatNoteDate(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final local = when.toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  final day = '${local.day} ${_months[local.month - 1]}';
  return local.year == today.year ? day : '$day ${local.year}';
}

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.note});

  final Note? note;

  static Route<void> route({Note? note}) =>
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note));

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final String _id =
      widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');

  bool get _dirty =>
      _title.text != (widget.note?.title ?? '') ||
      _body.text != (widget.note?.body ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    if (!_dirty) return;
    ref.read(notesProvider.notifier).put(Note(
          id: _id,
          title: _title.text,
          body: _body.text,
          updatedAt: DateTime.now(),
        ));
  }

  Future<void> _delete() async {
    await ref.read(notesProvider.notifier).remove(_id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              TextField(
                controller: _title,
                autofocus: widget.note == null,
                style: text.headlineSmall,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
              ),
              TextField(
                controller: _body,
                style: text.bodyLarge,
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Start writing',
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "locked notes" passcode sheet: the secret unlock's second step.
Future<void> showPasscodeSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PasscodeSheet(),
    );

class PasscodeSheet extends ConsumerStatefulWidget {
  const PasscodeSheet({super.key});

  @override
  ConsumerState<PasscodeSheet> createState() => _PasscodeSheetState();
}

class _PasscodeSheetState extends ConsumerState<PasscodeSheet> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text;
    if (pin.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(decoyProvider.notifier);
    final result = await notifier.verifyPin(pin);
    // On success the gate replaces this whole app; nothing to do here.
    if (!mounted || result == PinCheck.ok) return;
    setState(() {
      _busy = false;
      _pin.clear();
      _error = switch (result) {
        PinCheck.lockedOut =>
          'Try again in ${formatWait(notifier.lockoutRemaining)}',
        _ => 'Incorrect passcode',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Locked notes', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Enter your passcode to open them.',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: DecoyPin.maxLength,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Passcode',
              counterText: '',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}

/// "45 seconds", "3 minutes", "1 hour", always rounded up.
String formatWait(Duration d) {
  if (d.inSeconds < 60) {
    final s = (d.inMilliseconds / 1000).ceil().clamp(1, 60);
    return s == 1 ? '1 second' : '$s seconds';
  }
  if (d.inMinutes < 60) {
    final m = (d.inSeconds / 60).ceil();
    return m == 1 ? '1 minute' : '$m minutes';
  }
  final h = (d.inMinutes / 60).ceil();
  return h == 1 ? '1 hour' : '$h hours';
}
