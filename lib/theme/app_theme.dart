import 'package:flutter/material.dart';

// Ported 1:1 from the CSS custom properties in style.css (:root block)
// so every screen matches the PWA's colors exactly.
class AppTheme {
  static const Color brand = Color(0xFF0D5C42);        // --clr-primary
  static const Color brandLight = Color(0xFF14875F);   // --clr-primary-light
  static const Color brandDark = Color(0xFF083D2C);    // --clr-primary-dark
  static const Color accent = Color(0xFF1EBF7E);       // --clr-accent
  static const Color accentSoft = Color(0xFFE6F9F2);   // --clr-accent-soft
  static const Color gold = Color(0xFFF4A820);         // --clr-gold
  static const Color danger = Color(0xFFE53935);       // --clr-danger

  static const Color bgMain = Color(0xFFF5F5F5);       // --bg-main
  static const Color bgCard = Color(0xFFFFFFFF);       // --bg-card
  static const Color textPrimary = Color(0xFF1A1A1A);  // --text-primary
  static const Color textSecondary = Color(0xFF555555);// --text-secondary
  static const Color border = Color(0xFFE0E0E0);       // --border

  static const double radius = 14;    // --radius
  static const double radiusSm = 8;   // --radius-sm
  static const double radiusLg = 20;  // --radius-lg

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light),
    scaffoldBackgroundColor: bgMain,
    appBarTheme: const AppBarTheme(
      backgroundColor: brand,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: brand,
      unselectedItemColor: Colors.grey,
      backgroundColor: Colors.white,
    ),
    fontFamily: 'NotoSansEthiopic',
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark),
    fontFamily: 'NotoSansEthiopic',
  );
}
