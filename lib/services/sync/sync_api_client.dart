import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:luminotes_sync_core/luminotes_sync_core.dart';

import 'sync_remote.dart';

/// Thrown when login fails (bad credentials or unreachable server).
class SyncAuthException implements Exception {
  SyncAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncApiException implements Exception {
  SyncApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// REST client for the self-hosted Luminotes sync server. Transport only — the
/// reconcile logic lives in [SyncService].
class SyncApiClient implements SyncRemote {
  SyncApiClient({required String baseUrl, this.token, http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  String? token;
  final http.Client _client;

  Map<String, String> get _authHeaders =>
      token == null ? {} : {'authorization': 'Bearer $token'};

  Uri _filesUri(String relPath) {
    final encoded = relPath.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('$baseUrl/api/files/$encoded');
  }

  /// Logs in and stores the returned [token]. Returns the canonical username.
  Future<String> login(String username, String password) async {
    http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e) {
      throw SyncAuthException('Could not reach server: $e');
    }
    if (res.statusCode == 401) {
      throw SyncAuthException('Invalid username or password.');
    }
    if (res.statusCode != 200) {
      throw SyncAuthException('Login failed (HTTP ${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    token = body['token'] as String;
    return body['username'] as String? ?? username;
  }

  @override
  Future<({int revision, Manifest manifest})> getManifest() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/manifest'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw SyncApiException('Failed to fetch manifest (HTTP ${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      revision: (body['revision'] as num?)?.toInt() ?? 0,
      manifest: Manifest.fromJson(body),
    );
  }

  @override
  Future<void> uploadFile(String relPath, Uint8List bytes) async {
    final res = await _client.put(
      _filesUri(relPath),
      headers: {..._authHeaders, 'content-type': 'application/octet-stream'},
      body: bytes,
    );
    if (res.statusCode != 200) {
      throw SyncApiException('Upload of $relPath failed (HTTP ${res.statusCode}).');
    }
  }

  @override
  Future<Uint8List> downloadFile(String relPath) async {
    final res = await _client.get(_filesUri(relPath), headers: _authHeaders);
    if (res.statusCode != 200) {
      throw SyncApiException('Download of $relPath failed (HTTP ${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  /// Atomically applies [upserts]/[deletes] against [ifMatch]. Returns the new
  /// revision, or throws [StaleRevisionException] on a 409.
  @override
  Future<int> commit({
    required int ifMatch,
    required List<String> upserts,
    required List<String> deletes,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/commit'),
      headers: {..._authHeaders, 'content-type': 'application/json'},
      body: jsonEncode({
        'ifMatch': ifMatch,
        'upserts': upserts,
        'deletes': deletes,
      }),
    );
    if (res.statusCode == 409) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw StaleRevisionException((body['revision'] as num?)?.toInt() ?? 0);
    }
    if (res.statusCode != 200) {
      throw SyncApiException('Commit failed (HTTP ${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['revision'] as num).toInt();
  }

  void close() => _client.close();
}
