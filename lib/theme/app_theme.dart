import 'package:flutter/material.dart';

/// App theme constants and styles for the Music Player Dashboard.
/// Designed with the Hallmark 'Atmospheric' genre in mind:
/// Deep, muted backgrounds, subtle borders, high-contrast typography,
/// and restrained, intentional accent colors.
class AppTheme {
  // Background & Surface colors (Muted, dark OKLCH-inspired tones)
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF111111);
  static const Color cardSurface = Color(0xFF161616);
  static const Color cardSurfaceHover = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF262626);
  static const Color borderActive = Color(0xFF3A3A3A);

  // Restrained Accents (No harsh neon, more subtle and atmospheric)
  static const Color primary = Color(0xFFE2E2E2); // Soft white as primary
  static const Color secondary = Color(0xFF888888); // Muted gray
  static const Color accentPink = Color(0xFFD4B1B8); // Desaturated blush
  static const Color accentAmber = Color(0xFFD2BCA0); // Soft sand
  static const Color accentGreen = Color(0xFF9FBFA5); // Muted sage

  // Text colors (High contrast reading, low contrast metadata)
  static const Color textPrimary = Color(0xFFEBEBEB);
  static const Color textSecondary = Color(0xFFA1A1A1);
  static const Color textMuted = Color(0xFF6B6B6B);

  // Gradients (Very subtle, almost imperceptible)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [
      Color(0xFF18181B),
      Color(0xFF111111),
      Color(0xFF0A0A0A),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0xFF1C1C1C), Color(0xFF111111)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.black,
        secondary: secondary,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
      fontFamily: 'Inter', // Try to use system sans-serif (Inter/San Francisco/Roboto)
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.5, color: textPrimary),
        displayMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -1.0, color: textPrimary),
        displaySmall: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: textPrimary),
        headlineMedium: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.5, color: textPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2, color: textPrimary),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: textPrimary),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6), // Less rounded, more brutalist/modern
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: border,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.1),
        trackHeight: 2, // Thinner track
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), // Less rounded
          side: const BorderSide(color: border, width: 1), // Hairline border
        ),
      ),
      dividerColor: border,
    );
  }
}
