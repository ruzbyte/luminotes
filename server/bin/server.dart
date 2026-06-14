import 'dart:io';

import 'package:luminotes_server/cli.dart';
import 'package:luminotes_server/config.dart';
import 'package:luminotes_server/server.dart';

/// Entry point. Without arguments it serves HTTP; `user ...` runs admin commands.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'user') {
    exit(await runUserCommand(args.sublist(1)));
  }
  if (args.isNotEmpty && args.first != 'serve') {
    stderr.writeln('usage: luminotes-server [serve | user <add|list|passwd>]');
    exit(64);
  }
  await serve(Config.fromEnv());
}
