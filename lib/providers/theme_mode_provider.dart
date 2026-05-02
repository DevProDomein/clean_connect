import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeProvider extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  ThemeModeProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();
      if (v == 'dark') _mode = ThemeMode.dark;
      if (v == 'light') _mode = ThemeMode.light;
      notifyListeners();
    } catch (_) {
      // Ignore persistence errors; default theme still works.
    }
  }

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, isDark ? 'dark' : 'light');
    } catch (_) {
      // Ignore persistence errors.
    }
  }
}

