import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global theme mode notifier shared between main.dart and any screen
/// that needs to toggle / read the current theme.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

const String _themeModeKey = 'theme_mode';

/// Call once at app startup (before runApp) to restore whichever theme
/// the user had selected last time the app was open.
Future<void> loadSavedThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_themeModeKey);
  if (saved == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else if (saved == 'light') {
    themeNotifier.value = ThemeMode.light;
  }
  // If nothing was saved yet (first launch ever), keep the default light theme.
}

Future<void> toggleTheme() async {
  themeNotifier.value = themeNotifier.value == ThemeMode.light
      ? ThemeMode.dark
      : ThemeMode.light;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _themeModeKey,
    themeNotifier.value == ThemeMode.dark ? 'dark' : 'light',
  );
}
