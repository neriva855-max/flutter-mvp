import 'package:flutter/material.dart';

/// Centralized dark theme for the app.
/// Use Theme.of(context) in screens instead of hardcoded colors.
class AppTheme {
  AppTheme._();

  // Dark palette
  static const Color _scaffoldBackground = Color(0xFF121212);
  static const Color _surface = Color(0xFF1E1E1E);
  static const Color _surfaceVariant = Color(0xFF2C2C2C);
  static const Color _onSurface = Color(0xFFE8E8E8);
  static const Color _onSurfaceVariant = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF64B5F6);
  static const Color _accentVariant = Color(0xFF42A5F5);
  static const Color _error = Color(0xFFCF6679);
  static const Color _errorContainer = Color(0xFF3D1F24);
  static const Color _outline = Color(0xFF5C5C5C);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        onPrimary: Color(0xFF0D1B2A),
        primaryContainer: _accentVariant,
        secondary: _accentVariant,
        surface: _surface,
        onSurface: _onSurface,
        surfaceContainerHighest: _surfaceVariant,
        onSurfaceVariant: _onSurfaceVariant,
        error: _error,
        onError: Color(0xFF1D0F12),
        errorContainer: _errorContainer,
        onErrorContainer: Color(0xFFF8B4BD),
        outline: _outline,
      ),
      scaffoldBackgroundColor: _scaffoldBackground,
      cardColor: _surfaceVariant,
      cardTheme: CardThemeData(
        color: _surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _scaffoldBackground,
        foregroundColor: _onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceVariant,
        labelStyle: const TextStyle(color: _onSurfaceVariant),
        hintStyle: const TextStyle(color: _onSurfaceVariant),
        floatingLabelStyle: const TextStyle(color: _accent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF0D1B2A),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _accent,
        foregroundColor: Color(0xFF0D1B2A),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _onSurface, fontSize: 16),
        bodyMedium: TextStyle(color: _onSurface, fontSize: 14),
        titleLarge: TextStyle(color: _onSurface, fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: _onSurface, fontSize: 16, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: _onSurface, fontWeight: FontWeight.w600),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _accent,
        circularTrackColor: _surfaceVariant,
      ),
    );
  }
}
