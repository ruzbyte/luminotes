import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/storage_service.dart';
import '../services/sync/sync_api_client.dart';
import '../services/sync/sync_service.dart';

enum SyncStatus { disconnected, idle, syncing, error }

/// Owns sync configuration + lifecycle and exposes status to the UI.
///
/// Config (server URL, username, token, last sync, device id, base manifest)
/// lives in the StorageService sync-state file, which sits outside the synced
/// tree. A debounced push runs whenever local data changes.
class SyncProvider extends ChangeNotifier {
  SyncProvider(this._storage, {Future<void> Function()? onRemoteChange}) {
    _onRemoteChange = onRemoteChange;
  }

  final StorageService _storage;

  /// Called after a sync that changed local files (pulls/deletes/conflicts), so
  /// in-memory providers (e.g. the library index) can reload from disk.
  Future<void> Function()? _onRemoteChange;

  static const _debounce = Duration(seconds: 5);

  SyncStatus _status = SyncStatus.disconnected;
  String? _serverUrl;
  String? _username;
  DateTime? _lastSyncTime;
  String? _lastError;

  SyncService? _service;
  StreamSubscription<void>? _changes;
  Timer? _debounceTimer;
  bool _busy = false;

  SyncStatus get status => _status;
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;
  bool get isConnected => _status != SyncStatus.disconnected;

  /// Restores a previous session and kicks off an initial sync if connected.
  Future<void> init() async {
    final state = await _storage.loadSyncState();
    _serverUrl = state['serverUrl'] as String?;
    _username = state['username'] as String?;
    final lastMs = state['lastSyncMs'] as int?;
    _lastSyncTime =
        lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

    final token = state['token'] as String?;
    if (_serverUrl != null && _username != null && token != null) {
      await _activate(SyncApiClient(baseUrl: _serverUrl!, token: token));
      _status = SyncStatus.idle;
      notifyListeners();
      unawaited(syncNow());
    } else {
      _status = SyncStatus.disconnected;
      notifyListeners();
    }
  }

  /// Logs in to [serverUrl] and begins syncing. Returns null on success or an
  /// error message to show the user.
  Future<String?> connect({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final api = SyncApiClient(baseUrl: serverUrl);
    try {
      final canonicalName = await api.login(username, password);

      final state = await _storage.loadSyncState();
      state['serverUrl'] = api.baseUrl;
      state['username'] = canonicalName;
      state['token'] = api.token;
      await _storage.saveSyncState(state);

      _serverUrl = api.baseUrl;
      _username = canonicalName;
      await _activate(api);
      _status = SyncStatus.idle;
      notifyListeners();

      unawaited(syncNow());
      return null;
    } on SyncAuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not connect: $e';
    }
  }

  Future<void> disconnect() async {
    _debounceTimer?.cancel();
    await _changes?.cancel();
    _changes = null;
    _service = null;

    final state = await _storage.loadSyncState();
    state.remove('serverUrl');
    state.remove('username');
    state.remove('token');
    state.remove('baseManifest');
    state.remove('revision');
    state.remove('lastSyncMs');
    await _storage.saveSyncState(state);

    _status = SyncStatus.disconnected;
    _serverUrl = null;
    _username = null;
    _lastSyncTime = null;
    _lastError = null;
    notifyListeners();
  }

  /// Runs a full reconcile now. Safe to call repeatedly; overlapping calls are
  /// coalesced via [_busy].
  Future<void> syncNow() async {
    final service = _service;
    if (service == null || _busy) return;
    _busy = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();
    try {
      final outcome = await service.sync();
      _lastSyncTime = DateTime.now();
      final state = await _storage.loadSyncState();
      state['lastSyncMs'] = _lastSyncTime!.millisecondsSinceEpoch;
      await _storage.saveSyncState(state);
      _status = SyncStatus.idle;
      // If anything arrived from the server, refresh in-memory providers so the
      // UI reflects it without an app restart.
      if (outcome.pulled > 0 ||
          outcome.deletedLocal > 0 ||
          outcome.conflicts > 0) {
        await _onRemoteChange?.call();
      }
    } catch (e) {
      _lastError = '$e';
      _status = SyncStatus.error;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _activate(SyncApiClient api) async {
    final state = await _storage.loadSyncState();
    var deviceId = state['deviceId'] as String?;
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      state['deviceId'] = deviceId;
      await _storage.saveSyncState(state);
    }
    _service =
        SyncService(storage: _storage, api: api, deviceId: deviceId);

    await _changes?.cancel();
    _changes = _storage.onChanged.listen((_) => _scheduleSync());
  }

  void _scheduleSync() {
    // Ignore our own writes while a sync is applying pulls.
    if (_busy) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, syncNow);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}
