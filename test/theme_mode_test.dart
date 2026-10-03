import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/theme/app_theme.dart';

void main() {
  setUp(() {
    AppTheme.setThemeMode(ThemeMode.dark);
  });

  tearDown(() {
    AppTheme.setThemeMode(ThemeMode.dark);
  });

  test('AppTheme defaults to dark mode and switches cleanly to light mode', () {
    expect(AppTheme.themeModeNotifier.value, ThemeMode.dark);
    expect(AppTheme.isLight, isFalse);

    // Dark mode colors check
    expect(AppTheme.background, const Color(0xFF0A0A0A));
    expect(AppTheme.surface, const Color(0xFF111111));

    // Switch to light mode
    AppTheme.setThemeMode(ThemeMode.light);
    expect(AppTheme.themeModeNotifier.value, ThemeMode.light);
    expect(AppTheme.isLight, isTrue);

    // Light mode colors check
    expect(AppTheme.background, const Color(0xFFF6F6F8));
    expect(AppTheme.surface, const Color(0xFFFFFFFF));
    expect(AppTheme.textPrimary, const Color(0xFF111111));

    // Switch back to dark mode
    AppTheme.setThemeMode(ThemeMode.dark);
    expect(AppTheme.isLight, isFalse);
    expect(AppTheme.background, const Color(0xFF0A0A0A));
  });

  test('AppTheme lightTheme and darkTheme configurations are valid', () {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF6F6F8));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
  });
}
