import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../security/app_log.dart';

/// One decoy note. Plain text, local only.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Note copyWith({String? title, String? body, DateTime? updatedAt}) => Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, Object?> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime(0),
      );
}

/// Where the decoy notes live. Deliberately **not** the secure store: the
/// notes must never share storage with server profiles or keys, and they
/// are not secret, so a plain JSON file in app support is right.
abstract class NotesStore {
  Future<List<Note>> load();

  Future<void> save(List<Note> notes);
}

class FileNotesStore implements NotesStore {
  FileNotesStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'notes.json';

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');

  @override
  Future<List<Note>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .map((e) => Note.fromJson(e as Map<String, Object?>))
          .toList(growable: false);
    } on Object catch (e) {
      AppLog.warn('notes', 'not loaded: ${e.runtimeType}');
      return const [];
    }
  }

  @override
  Future<void> save(List<Note> notes) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Write next to the target and rename so a crash never leaves half a file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(notes.map((n) => n.toJson()).toList()));
    await tmp.rename(file.path);
  }
}

class MemoryNotesStore implements NotesStore {
  List<Note> notes = [];

  @override
  Future<List<Note>> load() async => notes;

  @override
  Future<void> save(List<Note> notes) async => this.notes = notes;
}

final notesStoreProvider = Provider<NotesStore>((_) => FileNotesStore());

/// Notes, newest first.
class NotesNotifier extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() async =>
      _sorted(await ref.read(notesStoreProvider).load());

  /// Inserts or replaces [note]. Empty notes are dropped instead.
  Future<void> put(Note note) async {
    final current = state.value ?? const <Note>[];
    final rest = current.where((n) => n.id != note.id);
    await _commit([if (!note.isEmpty) note, ...rest]);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? const <Note>[];
    await _commit(current.where((n) => n.id != id).toList());
  }

  Future<void> _commit(List<Note> notes) async {
    final sorted = _sorted(notes);
    state = AsyncData(sorted);
    try {
      await ref.read(notesStoreProvider).save(sorted);
    } on Object catch (e) {
      AppLog.warn('notes', 'not saved: ${e.runtimeType}');
    }
  }

  static List<Note> _sorted(List<Note> notes) => [...notes]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
