import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';

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
  Db._(this._path, this._users);

  final String _path;
  final Map<String, User> _users; // keyed by username

  factory Db.open(String path) {
    final file = File(path);
    final users = <String, User>{};
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final u in (json['users'] as List? ?? const [])) {
        final user = User.fromJson((u as Map).cast<String, dynamic>());
        users[user.username] = user;
      }
    } else {
      file.parent.createSync(recursive: true);
    }
    return Db._(path, users);
  }

  void _persist() {
    File(_path).writeAsStringSync(jsonEncode({
      'users': [for (final u in _users.values) u.toJson()],
    }));
  }

  User? findByUsername(String username) => _users[username];

  bool get isEmpty => _users.isEmpty;

  List<String> listUsernames() => _users.keys.toList()..sort();

  /// Creates a user, returning its id. Throws if the username already exists.
  String addUser(String username, String password) {
    if (_users.containsKey(username)) {
      throw StateError('User "$username" already exists.');
    }
    final user = User(
      id: _genId(),
      username: username,
      passwordHash: _hash(password),
    );
    _users[username] = user;
    _persist();
    return user.id;
  }

  void setPassword(String username, String password) {
    final user = _users[username];
    if (user == null) throw StateError('User "$username" not found.');
    _users[username] = User(
      id: user.id,
      username: username,
      passwordHash: _hash(password),
    );
    _persist();
  }

  static bool verifyPassword(User user, String password) =>
      BCrypt.checkpw(password, user.passwordHash);

  static String _hash(String password) =>
      BCrypt.hashpw(password, BCrypt.gensalt());

  static String _genId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
