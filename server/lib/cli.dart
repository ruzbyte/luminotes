import 'dart:io';

import 'config.dart';
import 'db.dart';

/// Admin commands for managing accounts: `user add|list|passwd`.
/// Used by the host to invite people (e.g. via `docker compose exec`).
Future<int> runUserCommand(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: luminotes-server user <add|list|passwd> [username]');
    return 64;
  }

  final config = Config.forCli();
  final db = Db.open(config.dbPath);
  final sub = args.first;

  switch (sub) {
    case 'list':
      final names = db.listUsernames();
      stdout.writeln(names.isEmpty ? '(no users)' : names.join('\n'));
      return 0;

    case 'add':
    case 'passwd':
      if (args.length < 2) {
        stderr.writeln('usage: luminotes-server user $sub <username>');
        return 64;
      }
      final username = args[1];
      final password = _readPassword();
      if (password.isEmpty) {
        stderr.writeln('Password must not be empty.');
        return 1;
      }
      try {
        if (sub == 'add') {
          db.addUser(username, password);
          stdout.writeln('Created user "$username".');
        } else {
          db.setPassword(username, password);
          stdout.writeln('Updated password for "$username".');
        }
        return 0;
      } on StateError catch (e) {
        stderr.writeln(e.message);
        return 1;
      }

    default:
      stderr.writeln('Unknown user command: $sub');
      return 64;
  }
}

String _readPassword() {
  stdout.write('Password: ');
  // Disable echo only on a real terminal; piped/redirected input has none.
  final interactive = stdin.hasTerminal;
  if (interactive) stdin.echoMode = false;
  final value = stdin.readLineSync() ?? '';
  if (interactive) {
    stdin.echoMode = true;
    stdout.writeln();
  }
  return value.trim();
}
