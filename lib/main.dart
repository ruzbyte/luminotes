import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'providers/library_provider.dart';
import 'providers/note_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/home_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize pdfrx (pdfium) for PDF rasterization.
  pdfrxFlutterInitialize();

  final storage = await StorageService.create();
  final library = LibraryProvider(storage)..load();
  final settings = SettingsProvider(storage)..load();
  final sync = SyncProvider(storage)..init();

  runApp(LuminotesApp(
    storage: storage,
    library: library,
    settings: settings,
    sync: sync,
  ));
}

class LuminotesApp extends StatelessWidget {
  const LuminotesApp({
    super.key,
    required this.storage,
    required this.library,
    required this.settings,
    required this.sync,
  });

  final StorageService storage;
  final LibraryProvider library;
  final SettingsProvider settings;
  final SyncProvider sync;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4C6FFF);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider(
          create: (_) => NoteProvider(storage, library),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Luminotes',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: settings.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
