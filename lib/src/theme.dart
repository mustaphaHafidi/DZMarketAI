import 'package:flutter/material.dart';

ThemeData buildTheme() {
  const primary = Color(0xFF4CAF50); // soft forest green
  const accent = Color(0xFF66BB6A); // minty accent
  const background = Color(0xFFF1FDF3); // pale green background

  final baseScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    secondary: accent,
    surface: Colors.white,
  );

  final base = ThemeData(
    colorScheme: baseScheme,
    useMaterial3: true,
  );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: base.colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: base.colorScheme.surface,
      foregroundColor: base.colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: base.colorScheme.surface,
      indicatorColor: base.colorScheme.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(
          fontWeight: FontWeight.w600,
          color: base.colorScheme.onSurface,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: base.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
