import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:luminotes_sync_core/luminotes_sync_core.dart';
import 'package:path/path.dart' as p;

/// Raised when a commit's `ifMatch` revision is stale.
class RevisionConflict implements Exception {
  RevisionConflict(this.currentRevision);
  final int currentRevision;
}

/// Per-user file storage on disk:
///
/// ```
/// <userDir>/files/<mirrored tree>
/// <userDir>/manifest.json   // { "revision": N, "entries": { path: {...} } }
/// ```
///
/// All mutations for a given user are serialized through an in-memory mutex so
/// concurrent requests can't interleave a manifest read/modify/write.
class UserStore {
  UserStore(this.userDir);

  final String userDir;

  String get _filesDir => p.join(userDir, 'files');
  String get _manifestPath => p.join(userDir, 'manifest.json');

  static final Map<String, _Mutex> _locks = {};
  _Mutex get _lock => _locks.putIfAbsent(userDir, () => _Mutex());

  /// Rejects absolute paths and any `.`/`..`/empty segment, then returns the
  /// real on-disk path. Returns null if the relative path is unsafe.
  String? _resolve(String rel) {
    final parts = p.posix.split(rel);
    if (rel.isEmpty || p.posix.isAbsolute(rel)) return null;
    for (final s in parts) {
      if (s.isEmpty || s == '.' || s == '..') return null;
    }
    return p.joinAll([_filesDir, ...parts]);
  }

  ({int revision, Manifest manifest}) _readManifest() {
    final file = File(_manifestPath);
    if (!file.existsSync()) return (revision: 0, manifest: Manifest());
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        manifest: Manifest.fromJson(json),
      );
    } catch (_) {
      return (revision: 0, manifest: Manifest());
    }
  }

  void _writeManifest(int revision, Manifest manifest) {
    final file = File(_manifestPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'revision': revision, ...manifest.toJson()}),
    );
  }

  Map<String, dynamic> manifestJson() {
    final state = _readManifest();
    return {'revision': state.revision, ...state.manifest.toJson()};
  }

  /// Stores uploaded [bytes] at [rel] without touching the manifest. The bytes
  /// are made "live" only when a later [commit] references the path.
  Future<ManifestEntry?> putFile(String rel, Uint8List bytes) async {
    final path = _resolve(rel);
    if (path == null) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return ManifestEntry(
      size: bytes.length,
      sha256: sha256OfBytes(bytes),
      modifiedMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Uint8List? readFile(String rel) {
    final path = _resolve(rel);
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  /// Atomically applies a set of [upserts] (already uploaded via [putFile]) and
  /// [deletes], guarded by optimistic concurrency on [ifMatch].
  Future<int> commit({
    required int ifMatch,
    required List<String> upserts,
    required List<String> deletes,
  }) {
    return _lock.run(() async {
      final state = _readManifest();
      if (ifMatch != state.revision) {
        throw RevisionConflict(state.revision);
      }
      final entries = state.manifest.entries;

      for (final rel in deletes) {
        final path = _resolve(rel);
        if (path == null) continue;
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
        entries.remove(rel);
      }

      for (final rel in upserts) {
        final path = _resolve(rel);
        if (path == null) continue;
        final file = File(path);
        if (!file.existsSync()) continue; // upload must precede commit
        final bytes = file.readAsBytesSync();
        entries[rel] = ManifestEntry(
          size: bytes.length,
          sha256: sha256OfBytes(bytes),
          modifiedMs: file.statSync().modified.millisecondsSinceEpoch,
        );
      }

      final next = state.revision + 1;
      _writeManifest(next, state.manifest);
      return next;
    });
  }
}

/// Minimal async mutex: chains operations so they run one at a time.
class _Mutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final prior = _tail;
    _tail = completer.future;
    return prior.then((_) => action()).whenComplete(completer.complete);
  }
}
