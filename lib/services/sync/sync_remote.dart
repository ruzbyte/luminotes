import 'dart:typed_data';

import 'package:luminotes_sync_core/luminotes_sync_core.dart';

/// Thrown when a commit's optimistic revision is stale; carries the server's
/// current revision so the caller can re-pull and retry.
class StaleRevisionException implements Exception {
  StaleRevisionException(this.currentRevision);
  final int currentRevision;
}

/// Remote transport the [SyncService] talks to. Implemented by `SyncApiClient`;
/// an interface so the engine can be tested against an in-memory fake.
abstract class SyncRemote {
  Future<({int revision, Manifest manifest})> getManifest();
  Future<void> uploadFile(String relPath, Uint8List bytes);
  Future<Uint8List> downloadFile(String relPath);
  Future<int> commit({
    required int ifMatch,
    required List<String> upserts,
    required List<String> deletes,
  });
}
