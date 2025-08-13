import 'package:filesfer/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

const _themeModeKey = 'themeMode';

class ThemeService extends StateNotifier<ThemeMode> {
  ThemeService(this._prefs) : super(ThemeMode.system) {
    _loadThemeMode();
  }

  final SharedPreferences _prefs;

  void _loadThemeMode() {
    final themeString = _prefs.getString(_themeModeKey);
    if (themeString == 'light') {
      state = ThemeMode.light;
    } else if (themeString == 'dark') {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.system;
    }
  }

 
  Future<void> toggleTheme() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _prefs.setString(_themeModeKey, state.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeService, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeService(prefs);
});