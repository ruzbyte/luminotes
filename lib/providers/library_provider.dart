import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/canvas_page.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../services/storage_service.dart';

/// Manages the folder tree and note index, and persists them to disk.
class LibraryProvider extends ChangeNotifier {
  LibraryProvider(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  final List<Folder> _folders = [];
  final List<NoteSummary> _notes = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Folder> get folders => List.unmodifiable(_folders);
  List<NoteSummary> get notes => List.unmodifiable(_notes);

  StorageService get storage => _storage;

  Future<void> load() async {
    final data = await _storage.loadLibrary();
    _folders
      ..clear()
      ..addAll(data.folders);
    _notes
      ..clear()
      ..addAll(data.notes);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => _storage.saveLibrary(_folders, _notes);

  // --- Queries -------------------------------------------------------------

  /// Direct child folders of [parentId] (root when null).
  List<Folder> foldersIn(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Notes directly inside [folderId] (root when null), newest first.
  List<NoteSummary> notesIn(String? folderId) =>
      _notes.where((n) => n.folderId == folderId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Folder? folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  // --- Folder CRUD ---------------------------------------------------------

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final folder = Folder(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? 'New Folder' : name.trim(),
      parentId: parentId,
      createdAt: DateTime.now(),
    );
    _folders.add(folder);
    notifyListeners();
    await _persist();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final folder = folderById(id);
    if (folder == null) return;
    folder.name = name.trim().isEmpty ? folder.name : name.trim();
    notifyListeners();
    await _persist();
  }

  /// Deletes a folder, its descendant folders, and all contained notes.
  Future<void> deleteFolder(String id) async {
    final toRemove = <String>{id};
    bool changed = true;
    while (changed) {
      changed = false;
      for (final f in _folders) {
        if (f.parentId != null &&
            toRemove.contains(f.parentId) &&
            !toRemove.contains(f.id)) {
          toRemove.add(f.id);
          changed = true;
        }
      }
    }
    final orphanNotes =
        _notes.where((n) => toRemove.contains(n.folderId)).toList();
    for (final n in orphanNotes) {
      await _storage.deleteNote(n.id);
    }
    _notes.removeWhere((n) => toRemove.contains(n.folderId));
    _folders.removeWhere((f) => toRemove.contains(f.id));
    notifyListeners();
    await _persist();
  }

  // --- Note CRUD -----------------------------------------------------------

  /// Creates an empty note (with one blank page) and persists it.
  Future<Note> createNote({String? folderId, String title = 'Untitled'}) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    )..pages.add(CanvasPage(id: _uuid.v4()));
    await _storage.saveNote(note);
    _notes.add(NoteSummary.fromNote(note));
    notifyListeners();
    await _persist();
    return note;
  }

  /// Refreshes the index entry for [note] after it was edited & saved.
  Future<void> syncSummary(Note note) async {
    final idx = _notes.indexWhere((n) => n.id == note.id);
    final summary = NoteSummary.fromNote(note);
    if (idx >= 0) {
      _notes[idx] = summary;
    } else {
      _notes.add(summary);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> renameNote(String id, String title) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx].title = title.trim().isEmpty ? _notes[idx].title : title.trim();
    notifyListeners();
    final note = await _storage.loadNote(id);
    if (note != null) {
      note.title = _notes[idx].title;
      await _storage.saveNote(note);
    }
    await _persist();
  }

  Future<void> moveNote(String id, String? folderId) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx].folderId = folderId;
    notifyListeners();
    final note = await _storage.loadNote(id);
    if (note != null) {
      note.folderId = folderId;
      await _storage.saveNote(note);
    }
    await _persist();
  }

  Future<void> deleteNote(String id) async {
    await _storage.deleteNote(id);
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
    await _persist();
  }
}
