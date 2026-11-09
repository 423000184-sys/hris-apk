// lib/theme/theme_notifier.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  // ✅ Storage key (may version suffix para safe sa future migrations)
  static const String _kThemeModeKey = 'theme_mode_v1';

  ThemeMode _themeMode = ThemeMode.system;
  Brightness _systemBrightness = Brightness.light;
  bool _loaded = false;

  // ═══════════════════════════════════════════════════════════════
  // ✅ GETTERS
  // ═══════════════════════════════════════════════════════════════
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;
  bool get isSystem => _themeMode == ThemeMode.system;
  bool get isLoaded => _loaded;
  Brightness get systemBrightness => _systemBrightness;

  /// Returns the actual "dark or not" based on selected mode + system brightness
  bool get effectiveIsDark {
    if (_themeMode == ThemeMode.system) {
      return _systemBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════
  ThemeNotifier() {
    _init();
  }

  void _init() {
    // 1. Read system brightness (safe — may catch in case binding not ready)
    try {
      _systemBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      debugPrint('🌗 [Theme] Initial system brightness: $_systemBrightness');
    } catch (e) {
      debugPrint('⚠️ [Theme] Could not read system brightness: $e');
      _systemBrightness = Brightness.light;
    }

    // 2. Listen to system brightness changes
    try {
      WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
          () {
        final newBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        debugPrint('🌗 [Theme] System brightness changed: $newBrightness');
        _systemBrightness = newBrightness;
        notifyListeners();
      };
    } catch (e) {
      debugPrint('⚠️ [Theme] Could not set brightness listener: $e');
    }

    // 3. Load saved theme mode from SharedPreferences
    _loadFromPrefs();
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ LOAD FROM PREFS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemeModeKey);

      _themeMode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.system,
      };

      debugPrint('🌗 [Theme] Loaded: $_themeMode (raw: "$saved")');
    } catch (e) {
      debugPrint('❌ [Theme] Load failed: $e');
      _themeMode = ThemeMode.system;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ SET THEME MODE (permanent — saved sa SharedPreferences)
  // ═══════════════════════════════════════════════════════════════
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;

    _themeMode = mode;
    debugPrint('🌗 [Theme] Mode changed: $mode');
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _themeModeToString(mode));
      debugPrint('💾 [Theme] Saved: ${_themeModeToString(mode)}');
    } catch (e) {
      debugPrint('❌ [Theme] Save failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ TOGGLE (light <-> dark) — backward compatible
  // ═══════════════════════════════════════════════════════════════
  Future<void> toggle() async {
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ RESET TO SYSTEM
  // ═══════════════════════════════════════════════════════════════
  Future<void> resetToSystem() async {
    await setThemeMode(ThemeMode.system);
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ DISPOSE
  // ═══════════════════════════════════════════════════════════════
  @override
  void dispose() {
    try {
      WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
      null;
    } catch (_) {}
    super.dispose();
  }
}