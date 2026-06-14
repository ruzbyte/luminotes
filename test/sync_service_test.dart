import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luminotes_sync_core/luminotes_sync_core.dart';
import 'package:luminotes/services/sync/sync_remote.dart';
import 'package:luminotes/services/sync/sync_service.dart';
import 'package:luminotes/services/sync/sync_store.dart';

/// A device's local store, backed by a real temp directory (so the engine's
/// directory walk runs for real) with in-memory sync state.
class DiskStore implements SyncStore {
  DiskStore(this._root);
  final String _root;
  Map<String, dynamic> _state = {};

  @override
  String get rootPath => _root;

  @override
  Future<Uint8List?> readBytes(String rel) async {
    final f = File('$_root/$rel');
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String rel, Uint8List bytes) async {
    final f = File('$_root/$rel');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  @override
  Future<void> deleteRelative(String rel) async {
    final f = File('$_root/$rel');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<Map<String, dynamic>> loadSyncState() async => _state;
  @override
  Future<void> saveSyncState(Map<String, dynamic> state) async =>
      _state = state;
}

/// In-memory stand-in for the server, mirroring its commit/revision semantics.
class FakeRemote implements SyncRemote {
  final Map<String, Uint8List> _committed = {};
  final Map<String, Uint8List> _staged = {};
  int _revision = 0;

  @override
  Future<({int revision, Manifest manifest})> getManifest() async {
    final entries = {
      for (final e in _committed.entries)
        e.key: ManifestEntry(
            size: e.value.length, sha256: sha256OfBytes(e.value), modifiedMs: 0),
    };
    return (revision: _revision, manifest: Manifest(entries));
  }

  @override
  Future<void> uploadFile(String relPath, Uint8List bytes) async =>
      _staged[relPath] = bytes;

  @override
  Future<Uint8List> downloadFile(String relPath) async => _committed[relPath]!;

  @override
  Future<int> commit({
    required int ifMatch,
    required List<String> upserts,
    required List<String> deletes,
  }) async {
    if (ifMatch != _revision) throw StaleRevisionException(_revision);
    for (final d in deletes) {
      _committed.remove(d);
    }
    for (final u in upserts) {
      _committed[u] = _staged[u] ?? _committed[u]!;
    }
    return ++_revision;
  }
}

void main() {
  late Directory tmpA;
  late Directory tmpB;
  late DiskStore storeA;
  late DiskStore storeB;
  late FakeRemote remote;
  late SyncService deviceA;
  late SyncService deviceB;

  setUp(() {
    tmpA = Directory.systemTemp.createTempSync('lumi_a_');
    tmpB = Directory.systemTemp.createTempSync('lumi_b_');
    storeA = DiskStore(tmpA.path);
    storeB = DiskStore(tmpB.path);
    remote = FakeRemote();
    deviceA = SyncService(storage: storeA, api: remote, deviceId: 'A');
    deviceB = SyncService(storage: storeB, api: remote, deviceId: 'B');
  });

  tearDown(() {
    tmpA.deleteSync(recursive: true);
    tmpB.deleteSync(recursive: true);
  });

  Future<void> write(DiskStore s, String path, String content) =>
      s.writeBytes(path, Uint8List.fromList(utf8.encode(content)));

  Future<String?> read(DiskStore s, String path) async {
    final b = await s.readBytes(path);
    return b == null ? null : utf8.decode(b);
  }

  Future<List<String>> paths(DiskStore s) async =>
      (await Manifest.fromDirectory(s.rootPath)).entries.keys.toList();

  test('push then pull propagates a new file', () async {
    await write(storeA, 'library.json', 'v1');
    await deviceA.sync();
    await deviceB.sync();
    expect(await read(storeB, 'library.json'), 'v1');
  });

  test('edits propagate', () async {
    await write(storeA, 'notes/n1/note.json', 'first');
    await deviceA.sync();
    await deviceB.sync();

    await write(storeB, 'notes/n1/note.json', 'edited on B');
    await deviceB.sync();
    await deviceA.sync();
    expect(await read(storeA, 'notes/n1/note.json'), 'edited on B');
  });

  test('deletion propagates', () async {
    await write(storeA, 'notes/n1/note.json', 'x');
    await deviceA.sync();
    await deviceB.sync();
    expect(await read(storeB, 'notes/n1/note.json'), 'x');

    await storeA.deleteRelative('notes/n1/note.json');
    await deviceA.sync();
    await deviceB.sync();
    expect(await read(storeB, 'notes/n1/note.json'), isNull);
  });

  test('concurrent edits keep both copies, no data loss', () async {
    // Common ancestor on both devices.
    await write(storeA, 'note', 'base');
    await deviceA.sync();
    await deviceB.sync();

    // Both edit the same file while "offline".
    await write(storeA, 'note', 'A-version');
    await write(storeB, 'note', 'B-version');

    // A commits first; B then sees a conflict and keeps both.
    await deviceA.sync();
    await deviceB.sync();
    // A re-syncs to converge with B's resolution.
    await deviceA.sync();

    final aPaths = await paths(storeA);
    final bPaths = await paths(storeB);

    // Both devices agree on the canonical file (B resolved the conflict last).
    expect(await read(storeA, 'note'), 'B-version');
    expect(await read(storeB, 'note'), 'B-version');

    // Exactly one conflict copy, holding the overwritten A-version, on both.
    final aConflicts = aPaths.where((p) => p.startsWith('conflicts/')).toList();
    final bConflicts = bPaths.where((p) => p.startsWith('conflicts/')).toList();
    expect(aConflicts, hasLength(1));
    expect(bConflicts, hasLength(1));
    expect(await read(storeA, aConflicts.single), 'A-version');
    expect(await read(storeB, bConflicts.single), 'A-version');
  });

  test('stale revision triggers retry and still converges', () async {
    // A remote that rejects the very first commit as stale (as if another
    // device committed in between), then behaves normally.
    final flaky = _FlakyOnceRemote(remote);
    final device = SyncService(storage: storeA, api: flaky, deviceId: 'A');

    await write(storeA, 'f', 'a');
    await device.sync(); // first commit throws stale -> retry -> succeeds

    expect(flaky.commitAttempts, 2);
    // The file made it to the server despite the stale rejection.
    await deviceB.sync();
    expect(await read(storeB, 'f'), 'a');
  });
}

/// Wraps a remote and throws [StaleRevisionException] on the first commit only.
class _FlakyOnceRemote implements SyncRemote {
  _FlakyOnceRemote(this._inner);
  final SyncRemote _inner;
  int commitAttempts = 0;

  @override
  Future<({int revision, Manifest manifest})> getManifest() =>
      _inner.getManifest();
  @override
  Future<void> uploadFile(String relPath, Uint8List bytes) =>
      _inner.uploadFile(relPath, bytes);
  @override
  Future<Uint8List> downloadFile(String relPath) =>
      _inner.downloadFile(relPath);

  @override
  Future<int> commit({
    required int ifMatch,
    required List<String> upserts,
    required List<String> deletes,
  }) async {
    commitAttempts++;
    if (commitAttempts == 1) throw StaleRevisionException(ifMatch);
    return _inner.commit(ifMatch: ifMatch, upserts: upserts, deletes: deletes);
  }
}
