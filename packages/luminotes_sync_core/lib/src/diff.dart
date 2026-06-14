import 'manifest.dart';

/// What to do with a single path during reconcile.
enum SyncOp {
  /// Remote has newer content; download and write locally.
  pull,

  /// Local has newer content; upload to the server.
  push,

  /// Remote deleted the file; delete it locally.
  deleteLocal,

  /// Local deleted the file; delete it on the server.
  deleteRemote,

  /// Both sides changed the same path to different content. The orchestrator
  /// keeps both (writes a "conflicted copy") and picks a canonical winner.
  conflict,
}

class SyncAction {
  const SyncAction(this.op, this.path);
  final SyncOp op;
  final String path;

  @override
  String toString() => '${op.name} $path';
}

bool _same(ManifestEntry? a, ManifestEntry? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return a.sameContentAs(b);
}

/// 3-way reconcile of [local] vs [remote] using [base] (the manifest captured at
/// the last successful sync) as the common ancestor.
///
/// On a first sync `base` is empty: anything present on only one side propagates,
/// and a path present on both with differing content becomes a [SyncOp.conflict].
List<SyncAction> diffManifests({
  required Manifest local,
  required Manifest remote,
  required Manifest base,
}) {
  final paths = <String>{
    ...local.entries.keys,
    ...remote.entries.keys,
    ...base.entries.keys,
  };

  final actions = <SyncAction>[];
  for (final path in paths) {
    final l = local.entries[path];
    final r = remote.entries[path];
    final b = base.entries[path];

    if (_same(l, r)) continue; // already in sync

    final localChanged = !_same(l, b);
    final remoteChanged = !_same(r, b);

    if (localChanged && !remoteChanged) {
      // Only the local side moved since base.
      actions.add(SyncAction(l == null ? SyncOp.deleteRemote : SyncOp.push, path));
    } else if (remoteChanged && !localChanged) {
      // Only the remote side moved since base.
      actions.add(SyncAction(r == null ? SyncOp.deleteLocal : SyncOp.pull, path));
    } else {
      // Both moved. Delete/modify resolves toward keeping content; a true
      // content/content clash is a conflict for the orchestrator to keep-both.
      if (l == null) {
        actions.add(SyncAction(SyncOp.pull, path)); // local deleted, remote edited
      } else if (r == null) {
        actions.add(SyncAction(SyncOp.push, path)); // remote deleted, local edited
      } else {
        actions.add(SyncAction(SyncOp.conflict, path));
      }
    }
  }
  return actions;
}
