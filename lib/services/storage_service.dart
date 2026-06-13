import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/folder.dart';
import '../models/note.dart';

/// On-disk layout (under the app documents directory):
///
/// ```
/// luminotes/
///   library.json            // folders + note summaries (index)
///   notes/<noteId>/
///     note.json             // full note: pages, strokes, images
///     assets/<file>         // embedded images & rasterized PDF backgrounds
/// ```
class StorageService {
  StorageService._(this._root);

  final Directory _root;

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
  }

  Future<void> deleteNote(String id) async {
    final dir = Directory(_noteDir(id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Writes [bytes] into the note's assets directory and returns the file name.
  Future<void> saveAsset(
    String noteId,
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = Directory(assetsDirPath(noteId));
    await dir.create(recursive: true);
    await File('${dir.path}/$fileName').writeAsBytes(bytes);
  }
}
