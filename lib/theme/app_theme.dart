import 'package:flutter/material.dart';

/// App theme constants and styles for the Music Player Dashboard.
/// Designed with the Hallmark anti-AI-slop standard:
/// Tactile, grounded paper/surface tones, 1px hairline borders,
/// high-contrast typography, and restrained accent colors in both Dark and Light modes.
class AppTheme {
  /// Global notifier for reactive theme mode switching.
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isLight => themeModeNotifier.value == ThemeMode.light;

  static void setThemeMode(ThemeMode mode) {
    themeModeNotifier.value = mode;
  }

  // Background & Surface colors (Muted, tactile tones)
  static Color get background =>
      isLight ? const Color(0xFFF6F6F8) : const Color(0xFF0A0A0A);
  static Color get surface =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111111);
  static Color get cardSurface =>
      isLight ? const Color(0xFFEFEFF2) : const Color(0xFF161616);
  static Color get cardSurfaceHover =>
      isLight ? const Color(0xFFE4E4E9) : const Color(0xFF1E1E1E);
  static Color get border =>
      isLight ? const Color(0xFFDCDCE2) : const Color(0xFF262626);
  static Color get borderActive =>
      isLight ? const Color(0xFFBCBCC4) : const Color(0xFF3A3A3A);

  // Accents
  static Color get primary =>
      isLight ? const Color(0xFF141416) : const Color(0xFFE2E2E2);
  static Color get secondary =>
      isLight ? const Color(0xFF6E6E73) : const Color(0xFF888888);
  static Color get accentPink =>
      isLight ? const Color(0xFFC44569) : const Color(0xFFD4B1B8);
  static Color get accentAmber =>
      isLight ? const Color(0xFFB8860B) : const Color(0xFFD2BCA0);
  static Color get accentGreen =>
      isLight ? const Color(0xFF2E7D32) : const Color(0xFF9FBFA5);

  // Text colors
  static Color get textPrimary =>
      isLight ? const Color(0xFF111111) : const Color(0xFFEBEBEB);
  static Color get textSecondary =>
      isLight ? const Color(0xFF555558) : const Color(0xFFA1A1A1);
  static Color get textMuted =>
      isLight ? const Color(0xFF8E8E93) : const Color(0xFF6B6B6B);

  // Solid surface palettes (Backward-compatibility, solid tones)
  static LinearGradient get primaryGradient => LinearGradient(
        colors: isLight
            ? const [Color(0xFFE0E0E5), Color(0xFFE0E0E5)]
            : const [Color(0xFF222222), Color(0xFF222222)],
      );

  static LinearGradient get heroGradient => LinearGradient(
        colors: isLight
            ? const [Color(0xFFEFEFF2), Color(0xFFEFEFF2)]
            : const [Color(0xFF161616), Color(0xFF161616)],
      );

  static LinearGradient get cardGlowGradient => LinearGradient(
        colors: isLight
            ? const [Color(0xFFEFEFF2), Color(0xFFEFEFF2)]
            : const [Color(0xFF161616), Color(0xFF161616)],
      );

  static ThemeData get darkTheme {
    const darkBackground = Color(0xFF0A0A0A);
    const darkSurface = Color(0xFF111111);
    const darkCardSurface = Color(0xFF161616);
    const darkBorder = Color(0xFF262626);
    const darkPrimary = Color(0xFFE2E2E2);
    const darkSecondary = Color(0xFF888888);
    const darkTextPrimary = Color(0xFFEBEBEB);
    const darkTextSecondary = Color(0xFFA1A1A1);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: darkPrimary,
      colorScheme: const ColorScheme.dark(
        primary: darkPrimary,
        onPrimary: Colors.black,
        secondary: darkSecondary,
        onSecondary: Colors.white,
        surface: darkSurface,
        onSurface: darkTextPrimary,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.5, color: darkTextPrimary),
        displayMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.0, color: darkTextPrimary),
        displaySmall: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: darkTextPrimary),
        headlineMedium: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: darkTextPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2, color: darkTextPrimary),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: darkTextPrimary),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: darkTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkTextSecondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: darkPrimary,
        inactiveTrackColor: darkBorder,
        thumbColor: darkPrimary,
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      cardTheme: CardThemeData(
        color: darkCardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dividerColor: darkBorder,
    );
  }

  static ThemeData get lightTheme {
    const lightBackground = Color(0xFFF6F6F8);
    const lightSurface = Color(0xFFFFFFFF);
    const lightCardSurface = Color(0xFFEFEFF2);
    const lightBorder = Color(0xFFDCDCE2);
    const lightPrimary = Color(0xFF141416);
    const lightSecondary = Color(0xFF6E6E73);
    const lightTextPrimary = Color(0xFF111111);
    const lightTextSecondary = Color(0xFF555558);

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      primaryColor: lightPrimary,
      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        onPrimary: Colors.white,
        secondary: lightSecondary,
        onSecondary: Colors.black,
        surface: lightSurface,
        onSurface: lightTextPrimary,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.5, color: lightTextPrimary),
        displayMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.0, color: lightTextPrimary),
        displaySmall: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: lightTextPrimary),
        headlineMedium: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: lightTextPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2, color: lightTextPrimary),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: lightTextPrimary),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: lightTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightTextSecondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: lightPrimary,
        inactiveTrackColor: lightBorder,
        thumbColor: lightPrimary,
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      cardTheme: CardThemeData(
        color: lightCardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      dividerColor: lightBorder,
    );
  }
}
