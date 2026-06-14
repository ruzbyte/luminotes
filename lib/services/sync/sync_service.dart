import 'package:luminotes_sync_core/luminotes_sync_core.dart';

import 'sync_remote.dart';
import 'sync_store.dart';

/// Tally of what a sync run did, for surfacing in the UI.
class SyncOutcome {
  const SyncOutcome({
    this.pushed = 0,
    this.pulled = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = 0,
  });

  final int pushed;
  final int pulled;
  final int deletedLocal;
  final int deletedRemote;
  final int conflicts;
}

/// Reconciles the local note tree with the server using the shared 3-way diff.
///
/// The server is a content-addressed file store; this class decides per file
/// whether to pull, push, delete, or keep-both, then applies the result both
/// locally (via [StorageService]) and remotely (via [SyncApiClient]).
class SyncService {
  SyncService({
    required this.storage,
    required this.api,
    required this.deviceId,
  });

  final SyncStore storage;
  final SyncRemote api;
  final String deviceId;

  /// Device-local files that must never sync (per-device / churny metadata).
  static const _excluded = {'settings.json'};

  Future<SyncOutcome> sync({int retriesLeft = 2}) async {
    final local = await _localManifest();
    final remoteState = await api.getManifest();
    final base = await _loadBase();

    final actions = diffManifests(
      local: local,
      remote: remoteState.manifest,
      base: base,
    );

    final upserts = <String>[];
    final deletes = <String>[];
    var pulled = 0;
    var deletedLocal = 0;
    var conflicts = 0;

    for (final action in actions) {
      switch (action.op) {
        case SyncOp.pull:
          await storage.writeBytes(
              action.path, await api.downloadFile(action.path));
          pulled++;
        case SyncOp.deleteLocal:
          await storage.deleteRelative(action.path);
          deletedLocal++;
        case SyncOp.push:
          upserts.add(action.path);
        case SyncOp.deleteRemote:
          deletes.add(action.path);
        case SyncOp.conflict:
          // Keep both: local stays canonical; the remote version is preserved
          // as a conflict copy. Both get pushed so every device has both.
          final remoteBytes = await api.downloadFile(action.path);
          final copyPath = _conflictPath(action.path);
          await storage.writeBytes(copyPath, remoteBytes);
          upserts.add(action.path);
          upserts.add(copyPath);
          conflicts++;
      }
    }

    var newRevision = remoteState.revision;
    if (upserts.isNotEmpty || deletes.isNotEmpty) {
      for (final path in upserts) {
        final bytes = await storage.readBytes(path);
        if (bytes == null) continue; // removed mid-sync; skip
        await api.uploadFile(path, bytes);
      }
      try {
        newRevision = await api.commit(
          ifMatch: remoteState.revision,
          upserts: upserts,
          deletes: deletes,
        );
      } on StaleRevisionException {
        // Another device committed first; re-pull and reconcile against it.
        if (retriesLeft <= 0) rethrow;
        return sync(retriesLeft: retriesLeft - 1);
      }
    }

    // After a successful run local and remote agree; snapshot local as the new
    // base so the next diff has an accurate common ancestor.
    await _saveBase(await _localManifest(), newRevision);

    return SyncOutcome(
      pushed: upserts.length,
      pulled: pulled,
      deletedLocal: deletedLocal,
      deletedRemote: deletes.length,
      conflicts: conflicts,
    );
  }

  Future<Manifest> _localManifest() async {
    final manifest = await Manifest.fromDirectory(storage.rootPath);
    for (final excluded in _excluded) {
      manifest.entries.remove(excluded);
    }
    return manifest;
  }

  String _conflictPath(String path) {
    final ts = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    return 'conflicts/$deviceId-$ts/$path';
  }

  Future<Manifest> _loadBase() async {
    final raw = (await storage.loadSyncState())['baseManifest'];
    if (raw is Map) return Manifest.fromJson(raw.cast<String, dynamic>());
    return Manifest();
  }

  Future<void> _saveBase(Manifest base, int revision) async {
    final state = await storage.loadSyncState();
    state['baseManifest'] = base.toJson();
    state['revision'] = revision;
    await storage.saveSyncState(state);
  }
}
