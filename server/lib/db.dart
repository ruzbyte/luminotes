import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class User {
  User({required this.id, required this.username, required this.passwordHash});
  final String id;
  final String username;
  final String passwordHash;

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'passwordHash': passwordHash};

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        passwordHash: j['passwordHash'] as String,
      );
}

/// Pure-Dart user store backed by a single JSON file (no native dependencies).
///
/// Account management is low-volume and off the sync hot path (file transfer is
/// all filesystem), so a JSON file keeps self-hosting and backups trivial.
class Db {
  Db._(this._path);

  final String _path;

  factory Db.open(String path) {
    final parent = File(path).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    return Db._(path);
  }

  // Read the file on every operation so the running server and the CLI (which
  // run as separate processes) always agree. Account ops are rare, so the cost
  // is irrelevant — and it avoids stale in-memory caches across processes.
  Map<String, User> _readAll() {
    final file = File(_path);
    final users = <String, User>{};
    if (!file.existsSync()) return users;
    final contents = file.readAsStringSync().trim();
    if (contents.isEmpty) return users;
    final json = jsonDecode(contents) as Map<String, dynamic>;
    for (final u in (json['users'] as List? ?? const [])) {
      final user = User.fromJson((u as Map).cast<String, dynamic>());
      users[user.username] = user;
    }
    return users;
  }

  void _writeAll(Map<String, User> users) {
    File(_path).writeAsStringSync(jsonEncode({
      'users': [for (final u in users.values) u.toJson()],
    }));
  }

  User? findByUsername(String username) => _readAll()[username];

  bool get isEmpty => _readAll().isEmpty;

  List<String> listUsernames() => _readAll().keys.toList()..sort();

  /// Creates a user, returning its id. Throws if the username already exists.
  String addUser(String username, String password) {
    final users = _readAll();
    if (users.containsKey(username)) {
      throw StateError('User "$username" already exists.');
    }
    final user = User(
      id: _genId(),
      username: username,
      passwordHash: _hash(password),
    );
    users[username] = user;
    _writeAll(users);
    return user.id;
  }

  void setPassword(String username, String password) {
    final users = _readAll();
    final user = users[username];
    if (user == null) throw StateError('User "$username" not found.');
    users[username] = User(
      id: user.id,
      username: username,
      passwordHash: _hash(password),
    );
    _writeAll(users);
  }

  // Password hashing: PBKDF2-HMAC-SHA256, encoded as
  // `pbkdf2_sha256$<iterations>$<saltB64>$<dkB64>`. Pure Dart via package:crypto
  // so behaviour is identical regardless of build environment.
  static const _iterations = 120000;

  static bool verifyPassword(User user, String password) {
    final parts = user.passwordHash.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final iterations = int.tryParse(parts[1]) ?? 0;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final actual = _pbkdf2(utf8.encode(password), salt, iterations, expected.length);
    return _constantTimeEquals(actual, expected);
  }

  static String _hash(String password) {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final dk = _pbkdf2(utf8.encode(password), salt, _iterations, 32);
    return 'pbkdf2_sha256\$$_iterations\$${base64.encode(salt)}\$${base64.encode(dk)}';
  }

  static List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    const hLen = 32;
    final blocks = (dkLen / hLen).ceil();
    final out = <int>[];
    for (var i = 1; i <= blocks; i++) {
      final block = [...salt, (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff];
      var u = hmac.convert(block).bytes;
      final t = List<int>.from(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.addAll(t);
    }
    return out.sublist(0, dkLen);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _genId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
