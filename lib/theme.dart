import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFEF4444), // Crimson neon alert
    secondary: Color(0xFF3B82F6), // Tech blue
    surface: Color(0xFF0F172A), // Midnight background
    error: Color(0xFFEF4444),
  ),
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFF020617),
  cardTheme: CardThemeData(
    color: const Color(0xFF0F172A),
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0B1329),
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.2,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFEF4444),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 6,
      shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.4),
    ),
  ),
);
