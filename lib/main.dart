import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'providers/library_provider.dart';
import 'providers/note_provider.dart';
import 'screens/home_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize pdfrx (pdfium) for PDF rasterization.
  pdfrxFlutterInitialize();

  final storage = await StorageService.create();
  final library = LibraryProvider(storage)..load();

  runApp(LuminotesApp(storage: storage, library: library));
}

class LuminotesApp extends StatelessWidget {
  const LuminotesApp({
    super.key,
    required this.storage,
    required this.library,
  });

  final StorageService storage;
  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider(
          create: (_) => NoteProvider(storage, library),
        ),
      ],
      child: MaterialApp(
        title: 'Luminotes',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C6FFF)),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
