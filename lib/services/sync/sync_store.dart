import 'dart:typed_data';

/// Storage surface the [SyncService] needs. Implemented by `StorageService`;
/// keeping it an interface lets the engine be tested without Flutter plugins.
abstract class SyncStore {
  /// Absolute path to the synced tree root.
  String get rootPath;

  Future<Uint8List?> readBytes(String rel);
  Future<void> writeBytes(String rel, Uint8List bytes);
  Future<void> deleteRelative(String rel);

  Future<Map<String, dynamic>> loadSyncState();
  Future<void> saveSyncState(Map<String, dynamic> state);
}
