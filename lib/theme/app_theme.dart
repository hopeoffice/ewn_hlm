import 'package:flutter/material.dart';

/// Ported 1:1 from the CSS custom properties in style.css (:root and
/// [data-theme="dark"] blocks) so every screen matches the PWA's colors,
/// radii and fonts exactly.
class AppTheme {
  // ---- Brand palette (same in light & dark) ----
  static const Color brand = Color(0xFF0D5C42);        // --clr-primary
  static const Color brandLight = Color(0xFF14875F);   // --clr-primary-light
  static const Color brandDark = Color(0xFF083D2C);    // --clr-primary-dark
  static const Color accent = Color(0xFF1EBF7E);       // --clr-accent
  static const Color accentSoft = Color(0xFFE6F9F2);   // --clr-accent-soft (light only)
  static const Color gold = Color(0xFFF4A820);         // --clr-gold
  static const Color danger = Color(0xFFE53935);       // --clr-danger

  // ---- Light theme tokens ----
  static const Color bgMainLight = Color(0xFFF5F5F5);
  static const Color bgCardLight = Color(0xFFFFFFFF);
  static const Color bgHeaderLight = Color(0xFF0D5C42);
  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textSecondaryLight = Color(0xFF555555);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color inputBgLight = Color(0xFFFFFFFF);
  static const Color navBgLight = Color(0xFFFFFFFF);
  static const Color navBorderLight = Color(0xFFE8E8E8);
  static const Color tagBgLight = Color(0xFFE6F9F2);
  static const Color tagTextLight = Color(0xFF0D5C42);
  static const Color skeletonLight = Color(0xFFE8E8E8);
  static const Color splashBgLight = Color(0xFF0D5C42);

  // ---- Dark theme tokens ----
  static const Color bgMainDark = Color(0xFF0F1117);
  static const Color bgCardDark = Color(0xFF1A1D27);
  static const Color bgHeaderDark = Color(0xFF0D5C42);
  static const Color textPrimaryDark = Color(0xFFF0F0F0);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color borderDark = Color(0xFF2A2D3A);
  static const Color inputBgDark = Color(0xFF1E2130);
  static const Color navBgDark = Color(0xFF131520);
  static const Color navBorderDark = Color(0xFF1F2235);
  static const Color tagBgDark = Color(0xFF0D2E22);
  static const Color tagTextDark = Color(0xFF1EBF7E);
  static const Color skeletonDark = Color(0xFF1E2130);
  static const Color splashBgDark = Color(0xFF071A12);

  // ---- Order status chip colors (.order-status.*) ----
  static const Color statusPendingBgLight = Color(0xFFFFF3CD);
  static const Color statusPendingTextLight = Color(0xFF856404);
  static const Color statusDeliveredBgLight = Color(0xFFD1FAE5);
  static const Color statusDeliveredTextLight = Color(0xFF065F46);
  static const Color statusProcessingBgLight = Color(0xFFDBEAFE);
  static const Color statusProcessingTextLight = Color(0xFF1E40AF);

  static const Color statusPendingBgDark = Color(0xFF3A2A00);
  static const Color statusDeliveredBgDark = Color(0xFF0D2E22);
  static const Color statusProcessingBgDark = Color(0xFF0D1F3C);
  static const Color statusProcessingTextDark = Color(0xFF60A5FA);

  // ---- Back-compat aliases (existing screens reference these directly) ----
  // NOTE: these currently always resolve to the LIGHT palette because every
  // screen in this codebase still hardcodes `AppTheme.xxx` instead of reading
  // from `Theme.of(context)` — meaning dark mode doesn't actually change
  // in-screen colors today, even though the ThemeData for dark exists and
  // the toggle in the profile screen appears to work. We are migrating this
  // screen-by-screen (next files in the plan); once every screen is switched
  // over to context-aware colors, these aliases will be removed.
  static const Color bgMain = bgMainLight;
  static const Color bgCard = bgCardLight;
  static const Color textPrimary = textPrimaryLight;
  static const Color textSecondary = textSecondaryLight;
  static const Color border = borderLight;

  // ---- Radii (--radius / --radius-sm / --radius-lg) ----
  static const double radius = 14;
  static const double radiusSm = 8;
  static const double radiusLg = 20;

  // ---- Fonts ----
  // --font-am is used for almost all UI copy (labels, titles, buttons, nav).
  // --font-en (Inter) is used only for the splash brand wordmark / raw
  // English/number-heavy text. Default the whole app to Noto Sans Ethiopic
  // to match the PWA's overwhelming use of `.am` text, and reach for
  // fontFamilyInter explicitly where the web CSS does the same.
  static const String fontAm = 'NotoSansEthiopic';
  static const String fontEn = 'Inter';

  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      primary: brand,
      secondary: accent,
      error: danger,
      surface: bgCardLight,
    ),
    scaffoldBackgroundColor: bgMainLight,
    fontFamily: fontAm,
    appBarTheme: const AppBarTheme(
      backgroundColor: bgHeaderLight,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardColor: bgCardLight,
    dividerColor: borderLight,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: brand,
      unselectedItemColor: Color(0xFF9AA0A6),
      backgroundColor: navBgLight,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputBgLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: borderLight),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
    ),
    textTheme: const TextTheme().apply(
      bodyColor: textPrimaryLight,
      displayColor: textPrimaryLight,
    ),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
      primary: accent,
      secondary: accent,
      error: danger,
      surface: bgCardDark,
    ),
    scaffoldBackgroundColor: bgMainDark,
    fontFamily: fontAm,
    appBarTheme: const AppBarTheme(
      backgroundColor: bgHeaderDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardColor: bgCardDark,
    dividerColor: borderDark,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: accent,
      unselectedItemColor: textSecondaryDark,
      backgroundColor: navBgDark,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputBgDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: borderDark),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
    ),
    textTheme: const TextTheme().apply(
      bodyColor: textPrimaryDark,
      displayColor: textPrimaryDark,
    ),
  );

  /// Helper to pick the right order-status colors for the current theme,
  /// mirroring the `.order-status.pending/.delivered/.processing` rules
  /// (and their `[data-theme="dark"]` overrides) from style.css.
  static (Color bg, Color fg) orderStatusColors(String status, {required bool isDark}) {
    switch (status) {
      case 'pending':
        return isDark ? (statusPendingBgDark, gold) : (statusPendingBgLight, statusPendingTextLight);
      case 'delivered':
        return isDark ? (statusDeliveredBgDark, accent) : (statusDeliveredBgLight, statusDeliveredTextLight);
      case 'processing':
        return isDark ? (statusProcessingBgDark, statusProcessingTextDark) : (statusProcessingBgLight, statusProcessingTextLight);
      default:
        return isDark ? (bgCardDark, textSecondaryDark) : (bgCardLight, textSecondaryLight);
    }
  }
}
