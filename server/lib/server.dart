import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'auth.dart';
import 'config.dart';
import 'db.dart';
import 'routes.dart';

/// Starts the HTTP server. Bootstraps an admin account from env on first run.
Future<void> serve(Config config) async {
  Directory(config.dataDir).createSync(recursive: true);
  final db = Db.open(config.dbPath);

  if (db.isEmpty && config.adminUser != null && config.adminPassword != null) {
    db.addUser(config.adminUser!, config.adminPassword!);
    stdout.writeln('Bootstrapped admin user "${config.adminUser}".');
  }

  final tokens = TokenService(config.jwtSecret);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildApi(config, db, tokens));

  final server = await shelf_io.serve(handler, '0.0.0.0', config.port);
  stdout.writeln('Luminotes server listening on ${server.address.host}:${server.port}');
}
