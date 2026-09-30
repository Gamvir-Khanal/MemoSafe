import 'package:container/helper_pages/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Theme controller toggles between light and dark modes', () async {
    SharedPreferences.setMockInitialValues({});
    themeNotifier.value = ThemeMode.light;
    expect(themeNotifier.value, equals(ThemeMode.light));

    toggleTheme();
    expect(themeNotifier.value, equals(ThemeMode.dark));

    toggleTheme();
    expect(themeNotifier.value, equals(ThemeMode.light));
  });
}
