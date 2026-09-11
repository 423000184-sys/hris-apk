import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  Brightness _systemBrightness = Brightness.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;
  bool get isSystem => _themeMode == ThemeMode.system;
  Brightness get systemBrightness => _systemBrightness;

  bool get effectiveIsDark {
    if (_themeMode == ThemeMode.system) {
      return _systemBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeNotifier() {
    _systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    debugPrint('🌗 Initial system brightness: $_systemBrightness');

    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
      final newBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      debugPrint('🌗 System brightness changed to: $newBrightness');
      _systemBrightness = newBrightness;
      notifyListeners();
    };

    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _themeMode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    debugPrint('🌗 Loaded theme mode from prefs: $_themeMode (saved: $saved)');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    debugPrint('🌗 Theme mode changed to: $mode');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> toggle() async {
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
    null;
    super.dispose();
  }
}