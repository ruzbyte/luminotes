/// Shared sync primitives used by both the Luminotes app and the sync server.
///
/// The sync model is deliberately simple: each side describes its file tree as a
/// [Manifest] (relative path -> [ManifestEntry]). A file's identity is its
/// content hash, so identical bytes never re-transfer. [diffManifests] performs a
/// 3-way reconcile (local vs. remote vs. last-synced base) into a list of
/// [SyncAction]s the orchestrator applies.
library;

export 'src/manifest.dart';
export 'src/diff.dart';
export 'src/hashing.dart';
