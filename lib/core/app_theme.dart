import 'package:flutter/material.dart';

/// Central theme definition for MedLink Connect.
///
/// Uses Material 3 with a clean, professional colour scheme suited to a
/// hospital IT tool.
class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF00E5FF); // Vibrant Cyan
  static const Color _onPrimary = Colors.white;
  static const Color _secondary = Color(0xFF1DE9B6); // Teal Accent
  static const Color _lightText = Color(0xFF0F172A);
  static const Color _darkText = Colors.white;

  static const List<Color> _lightBackground = [
    Color(0xFFE0F7FA),
    Color(0xFFD6ECF7),
    Color(0xFFE3F2FD),
    Color(0xFFE8F5E9),
  ];

  static const List<Color> _darkBackground = [
    Color(0xFF0F172A),
    Color(0xFF003049),
    Color(0xFF1565C0),
    Color(0xFF00897B),
  ];

  /// Gradient used by the app shell for the active brightness.
  static LinearGradient backgroundGradient(Brightness brightness) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors:
          brightness == Brightness.dark ? _darkBackground : _lightBackground,
    );
  }

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        secondary: _secondary,
        surface: Colors.transparent,
        brightness: Brightness.light,
      ).copyWith(onPrimary: _onPrimary),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _lightText,
      ),
      scaffoldBackgroundColor: Colors.transparent, // Let gradient show
      cardTheme: const CardTheme(
        color: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        labelStyle: TextStyle(color: _lightText.withValues(alpha: 0.75)),
        hintStyle: TextStyle(color: _lightText.withValues(alpha: 0.55)),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: _lightText),
        bodySmall: TextStyle(color: Color(0xCC0F172A)),
        titleMedium: TextStyle(color: _lightText),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        secondary: _secondary,
        surface: Colors.transparent,
        brightness: Brightness.dark,
      ).copyWith(onPrimary: _onPrimary),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _darkText,
      ),
      scaffoldBackgroundColor: Colors.transparent, // Let gradient show
      cardTheme: const CardTheme(
        color: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: _darkText),
        bodySmall: TextStyle(color: Colors.white70),
        titleMedium: TextStyle(color: _darkText),
      ),
    );
  }
}
