// lib/theme/theme_notifier.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _key = 'is_dark_mode';

<<<<<<< HEAD
  bool _isDark = false;
=======
  bool _isDark = true;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  ThemeNotifier() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
<<<<<<< HEAD
    _isDark = prefs.getBool(_key) ?? false; // default to light mode
=======
    _isDark = prefs.getBool(_key) ?? true;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    notifyListeners(); // ← notify after loading so UI updates
  }

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDark);
  }
}