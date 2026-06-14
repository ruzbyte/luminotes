import 'dart:io';

import 'package:path/path.dart' as p;

/// Runtime configuration, sourced from environment variables.
class Config {
  Config({
    required this.dataDir,
    required this.jwtSecret,
    required this.port,
    this.adminUser,
    this.adminPassword,
  });

  /// Root directory for all persisted state (SQLite db + per-user files).
  final String dataDir;
  final String jwtSecret;
  final int port;

  /// Optional bootstrap admin, created on first run if no users exist.
  final String? adminUser;
  final String? adminPassword;

  String get dbPath => p.join(dataDir, 'users.json');
  String userDir(String userId) => p.join(dataDir, 'users', userId);

  /// Full config for serving (requires a JWT secret).
  factory Config.fromEnv() {
    final env = Platform.environment;
    final secret = env['JWT_SECRET'];
    if (secret == null || secret.trim().isEmpty) {
      throw StateError('JWT_SECRET environment variable is required.');
    }
    return Config(
      dataDir: env['DATA_DIR'] ?? '/data',
      jwtSecret: secret,
      port: int.parse(env['PORT'] ?? '8080'),
      adminUser: _blankToNull(env['ADMIN_USER']),
      adminPassword: _blankToNull(env['ADMIN_PASSWORD']),
    );
  }

  /// Lightweight config for CLI commands that only touch the database.
  factory Config.forCli() {
    final env = Platform.environment;
    return Config(
      dataDir: env['DATA_DIR'] ?? '/data',
      jwtSecret: env['JWT_SECRET'] ?? 'cli',
      port: 0,
    );
  }

  static String? _blankToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v;
}
