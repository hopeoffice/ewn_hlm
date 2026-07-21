import 'package:flutter/material.dart';

// Same brand color as manifest.json / meta-theme-color in the PWA: #0d5c42
class AppTheme {
  static const Color brand = Color(0xFF0D5C42);

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light),
    scaffoldBackgroundColor: const Color(0xFFF7F7F7),
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
