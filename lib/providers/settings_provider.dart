import 'package:flutter/material.dart';

import '../services/storage_service.dart';

/// App-wide preferences (currently the theme mode), persisted to disk.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._storage);

  final StorageService _storage;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final settings = await _storage.loadSettings();
    switch (settings['themeMode'] as String?) {
      case 'light':
        _themeMode = ThemeMode.light;
      case 'dark':
        _themeMode = ThemeMode.dark;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _storage.saveSettings({'themeMode': mode.name});
  }

  /// Cycles light -> dark (treating "system" as a starting point).
  Future<void> toggle(Brightness platformBrightness) async {
    final effectiveDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);
    await setThemeMode(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }
}
