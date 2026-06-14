import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/folder.dart';
import '../models/note.dart';
import 'sync/sync_store.dart';

/// On-disk layout (under the app documents directory):
///
/// ```
/// luminotes/
///   library.json            // folders + note summaries (index)
///   notes/<noteId>/
///     note.json             // full note: pages, strokes, images
///     assets/<file>         // embedded images & rasterized PDF backgrounds
/// ```
class StorageService implements SyncStore {
  StorageService._(this._root);

  final Directory _root;

  /// Absolute path to the synced tree root (the `luminotes/` directory).
  @override
  String get rootPath => _root.path;

  /// Fires after every successful write so the sync layer can schedule a push.
  /// Broadcast so multiple listeners (or none) are fine.
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changes.stream;
  void _notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  static Future<StorageService> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/luminotes');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final service = StorageService._(root);
    await Directory(service._notesPath).create(recursive: true);
    return service;
  }

  String get _libraryPath => '${_root.path}/library.json';
  String get _settingsPath => '${_root.path}/settings.json';

  // --- Settings ------------------------------------------------------------

  Future<Map<String, dynamic>> loadSettings() async {
    final file = File(_settingsPath);
    if (!await file.exists()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await File(_settingsPath).writeAsString(jsonEncode(settings));
    _notifyChanged();
  }

  String get _notesPath => '${_root.path}/notes';
  String _noteDir(String id) => '$_notesPath/$id';
  String _notePath(String id) => '${_noteDir(id)}/note.json';
  String assetsDirPath(String noteId) => '${_noteDir(noteId)}/assets';

  /// Absolute path to an embedded asset, for display via [File].
  String assetPath(String noteId, String fileName) =>
      '${assetsDirPath(noteId)}/$fileName';

  // --- Library index -------------------------------------------------------

  Future<({List<Folder> folders, List<NoteSummary> notes})>
      loadLibrary() async {
    final file = File(_libraryPath);
    if (!await file.exists()) {
      return (folders: <Folder>[], notes: <NoteSummary>[]);
    }
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final folders = [
        for (final f in (json['folders'] as List? ?? []))
          Folder.fromJson(f as Map<String, dynamic>),
      ];
      final notes = [
        for (final n in (json['notes'] as List? ?? []))
          NoteSummary.fromJson(n as Map<String, dynamic>),
      ];
      return (folders: folders, notes: notes);
    } catch (_) {
      return (folders: <Folder>[], notes: <NoteSummary>[]);
    }
  }

  Future<void> saveLibrary(
    List<Folder> folders,
    List<NoteSummary> notes,
  ) async {
    final json = {
      'folders': [for (final f in folders) f.toJson()],
      'notes': [for (final n in notes) n.toJson()],
    };
    await File(_libraryPath).writeAsString(jsonEncode(json));
    _notifyChanged();
  }

  // --- Notes ---------------------------------------------------------------

  Future<Note?> loadNote(String id) async {
    final file = File(_notePath(id));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Note.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNote(Note note) async {
    await Directory(_noteDir(note.id)).create(recursive: true);
    await File(_notePath(note.id)).writeAsString(jsonEncode(note.toJson()));
    _notifyChanged();
  }

  Future<void> deleteNote(String id) async {
    final dir = Directory(_noteDir(id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _notifyChanged();
  }

  /// Writes [bytes] into the note's assets directory.
  Future<void> saveAsset(
    String noteId,
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = Directory(assetsDirPath(noteId));
    await dir.create(recursive: true);
    await File('${dir.path}/$fileName').writeAsBytes(bytes);
    _notifyChanged();
  }

  /// Copies an external file into the note's assets without loading it fully
  /// into memory (used for large PDFs).
  Future<void> copyAsset(
    String noteId,
    String fileName,
    String sourcePath,
  ) async {
    final dir = Directory(assetsDirPath(noteId));
    await dir.create(recursive: true);
    await File(sourcePath).copy('${dir.path}/$fileName');
    _notifyChanged();
  }

  // --- Generic tree access (used by the sync engine) -----------------------

  /// Reads bytes at a POSIX [rel]ative path under the root, or null if missing.
  @override
  Future<Uint8List?> readBytes(String rel) async {
    final file = File('${_root.path}/$rel');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Writes [bytes] at a POSIX [rel]ative path under the root, creating dirs.
  @override
  Future<void> writeBytes(String rel, Uint8List bytes) async {
    final file = File('${_root.path}/$rel');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    _notifyChanged();
  }

  /// Deletes the file at [rel] and prunes now-empty parent dirs up to the root.
  @override
  Future<void> deleteRelative(String rel) async {
    final file = File('${_root.path}/$rel');
    if (await file.exists()) await file.delete();
    var dir = file.parent;
    while (dir.path.length > _root.path.length && await dir.exists()) {
      if (await dir.list().isEmpty) {
        await dir.delete();
        dir = dir.parent;
      } else {
        break;
      }
    }
    _notifyChanged();
  }

  // --- Sync state ----------------------------------------------------------
  // Stored as a sibling of the synced tree so it never becomes sync content.

  String get _syncStatePath => '${_root.parent.path}/luminotes_sync.json';

  @override
  Future<Map<String, dynamic>> loadSyncState() async {
    final file = File(_syncStatePath);
    if (!await file.exists()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveSyncState(Map<String, dynamic> state) async {
    await File(_syncStatePath).writeAsString(jsonEncode(state));
  }
}
