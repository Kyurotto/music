import 'package:flutter/material.dart';

/// App theme constants and styles for the Music Player Dashboard.
class AppTheme {
  // Background & Surface colors
  static const Color background = Color(0xFF0B0E14);
  static const Color surface = Color(0xFF131722);
  static const Color cardSurface = Color(0xFF1A202E);
  static const Color cardSurfaceHover = Color(0xFF232A3B);
  static const Color border = Color(0x1FFFFFFF);
  static const Color borderActive = Color(0x408B5CF6);

  // Vibrant Brand & Accent colors
  static const Color primary = Color(0xFF8B5CF6); // Electric Violet
  static const Color secondary = Color(0xFF06B6D4); // Cyber Cyan
  static const Color accentPink = Color(0xFFEC4899); // Neon Pink
  static const Color accentAmber = Color(0xFFF59E0B); // Amber glow
  static const Color accentGreen = Color(0xFF10B981); // Emerald

  // Text colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [
      Color(0xFF4C1D95),
      Color(0xFF1E1B4B),
      Color(0xFF131722),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x158B5CF6), Color(0x0506B6D4)],
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
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackHeight: 4,
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerColor: border,
    );
  }
}
