import 'package:flutter/material.dart';

/// Central theme definition for MedLink Connect.
///
/// Uses Material 3 with a clean, professional colour scheme suited to a
/// hospital IT tool.
class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF1565C0); // Blue 800
  static const Color _onPrimary = Colors.white;
  static const Color _secondary = Color(0xFF00897B); // Teal 600
  static const Color _surface = Color(0xFFF5F5F5);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        secondary: _secondary,
        surface: _surface,
        brightness: Brightness.light,
      ).copyWith(onPrimary: _onPrimary),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
