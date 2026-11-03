import 'package:flutter/material.dart';

/// Central theme definition for MedLink Connect.
///
/// Uses Material 3 with a clean, professional colour scheme suited to a
/// hospital IT tool.
class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF00E5FF); // Vibrant Cyan
  static const Color _secondary = Color(0xFF1DE9B6); // Teal Accent
  static const Color _lightText = Color(0xFF0B1726);
  static const Color _lightMuted = Color(0xFF415462);
  static const Color _darkText = Color(0xFFF4F8FA);
  static const Color _darkMuted = Color(0xFFC3D0D9);
  static const Color _lightSurface = Color(0xFFF7FCFD);
  static const Color _darkSurface = Color(0xFF101A28);
  static const Color _darkSurfaceContainer = Color(0xFF172538);

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

  static Color successColor(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xFF69F0AE)
        : const Color(0xFF1B5E20);
  }

  static ThemeData get light => _buildTheme(Brightness.light);

  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _primary,
      secondary: _secondary,
      brightness: brightness,
    ).copyWith(
      surface: isDark ? _darkSurface : _lightSurface,
      onSurface: isDark ? _darkText : _lightText,
      onSurfaceVariant: isDark ? _darkMuted : _lightMuted,
      outline: isDark ? const Color(0xFF8398A6) : const Color(0xFF627581),
      outlineVariant:
          isDark ? const Color(0xFF455A68) : const Color(0xFFB7C6CC),
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseTextTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          bodySmall:
              baseTextTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          labelSmall: baseTextTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        );

    final fieldFill = isDark
        ? _darkSurfaceContainer.withValues(alpha: 0.88)
        : _lightSurface.withValues(alpha: 0.86);
    final fieldBorder = scheme.outline.withValues(alpha: isDark ? 0.72 : 0.6);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      canvasColor: scheme.surface,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: const CardTheme(
        color: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: TextStyle(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: fieldBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      textTheme: textTheme,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}
