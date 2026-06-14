import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'config.dart';
import 'db.dart';
import 'user_store.dart';

Response _json(Object? body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

/// Builds the HTTP API. Authenticated routes receive the resolved userId.
Handler buildApi(Config config, Db db, TokenService tokens) {
  final router = Router();

  router.get('/health', (Request r) => _json({'ok': true}));

  router.post('/api/auth/login', (Request r) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final username = (body['username'] as String?)?.trim() ?? '';
    final password = body['password'] as String? ?? '';
    final user = db.findByUsername(username);
    if (user == null || !Db.verifyPassword(user, password)) {
      return _json({'error': 'invalid_credentials'}, status: 401);
    }
    final issued = tokens.issue(userId: user.id, username: user.username);
    return _json({
      'token': issued.token,
      'expiresAt': issued.expiresAt.toIso8601String(),
      'username': user.username,
    });
  });

  Handler auth(Future<Response> Function(Request, String userId) handler) {
    return (Request r) async {
      final header = r.headers['authorization'] ?? '';
      if (!header.startsWith('Bearer ')) {
        return _json({'error': 'unauthorized'}, status: 401);
      }
      final userId = tokens.verify(header.substring(7));
      if (userId == null) {
        return _json({'error': 'unauthorized'}, status: 401);
      }
      return handler(r, userId);
    };
  }

  UserStore storeFor(String userId) => UserStore(config.userDir(userId));

  router.get('/api/me', auth((r, userId) async => _json({'userId': userId})));

  router.get('/api/manifest', auth((r, userId) async {
    return _json(storeFor(userId).manifestJson());
  }));

  router.get('/api/files/<path|.*>', auth((r, userId) async {
    final rel = r.params['path']!;
    final bytes = storeFor(userId).readFile(rel);
    if (bytes == null) return Response.notFound('not found');
    return Response.ok(bytes,
        headers: {'content-type': 'application/octet-stream'});
  }));

  router.put('/api/files/<path|.*>', auth((r, userId) async {
    final rel = r.params['path']!;
    final bytes = await r.read().expand((c) => c).toList();
    final entry =
        await storeFor(userId).putFile(rel, Uint8List.fromList(bytes));
    if (entry == null) return _json({'error': 'bad_path'}, status: 400);
    return _json(entry.toJson());
  }));

  router.post('/api/commit', auth((r, userId) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final ifMatch = (body['ifMatch'] as num?)?.toInt() ?? 0;
    final upserts =
        (body['upserts'] as List? ?? const []).map((e) => e as String).toList();
    final deletes =
        (body['deletes'] as List? ?? const []).map((e) => e as String).toList();
    try {
      final revision = await storeFor(userId)
          .commit(ifMatch: ifMatch, upserts: upserts, deletes: deletes);
      return _json({'revision': revision});
    } on RevisionConflict catch (e) {
      return _json(
        {'error': 'revision_conflict', 'revision': e.currentRevision},
        status: 409,
      );
    }
  }));

  return router.call;
}
