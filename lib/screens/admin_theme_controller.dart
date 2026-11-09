import 'package:flutter/material.dart';

/// Global admin dark-mode state. Singleton — one source of truth.
class AdminThemeController extends ChangeNotifier {
  AdminThemeController._();
  static final AdminThemeController instance = AdminThemeController._();

  bool _isDark = false;
  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setDark(bool value) {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
  }
}