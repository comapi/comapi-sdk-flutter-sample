import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// DOTDIGITAL BRAND DESIGN SYSTEM (2026 V1.1)
// ============================================================================
// Core Primary Palette:
// - Ink Black:   #000000
// - Warm Sand:   #E2DBBF
// - Bright Sand: #FEFBEC (Default background)
// - Electric Pink: #EC58C4
// - Signal Pink: #FFC5F0
// - Neon:        #E9FF42
//
// Amplified Neutrals & Sands:
// - Soft Sand:   #F3EEDA
// - Deep Sand:   #8C825B
// - Dark Sand:   #403B26
// - Charcoal:    #2A2A2A
// - Muted Gray:  #737373
// - Soft Pink:   #FFE8F9
// - Deep Pink:   #5C0A46
//
// Typography:
// - Headlines & Headers: system serif, -1% letter-spacing, 95-100% height
// - Body Copy:           system sans-serif, 140-150% height
// - Eyebrows & Buttons:  system sans-serif, Eyebrows +15% letter-spacing uppercase
// ============================================================================

class DotdigitalBrand {
  // Primary Palette (Core)
  static const Color inkBlack = Color(0xFF000000);
  static const Color warmSand = Color(0xFFE2DBBF);
  static const Color brightSand = Color(0xFFFEFBEC);
  static const Color electricPink = Color(0xFFEC58C4);
  static const Color signalPink = Color(0xFFFFC5F0);
  static const Color neon = Color(0xFFE9FF42);

  // Amplified Palette (Sands, Pinks, Neutrals)
  static const Color softSand = Color(0xFFF3EEDA);
  static const Color midSand = Color(0xFF8C825B);
  static const Color darkSand = Color(0xFF403B26);

  static const Color deepPink = Color(0xFF5C0A46);
  static const Color berryPink = Color(0xFFBC158F);
  static const Color palePink = Color(0xFFFFE8F9);
  static const Color blushWhite = Color(0xFFFFF5FC);

  static const Color charcoal = Color(0xFF2A2A2A);
  static const Color coolGray = Color(0xFF737373);
  static const Color lightBorder = Color(0xFFDDDDDD);
  static const Color white = Color(0xFFFFFFFF);

  // Secondary Palette Accents (Status & Categories)
  static const Color greenStep1 = Color(0xFF2B923C);
  static const Color greenStep2 = Color(0xFF55CD69);
  static const Color greenStep4 = Color(0xFFCCF0D2);
  static const Color coralStep1 = Color(0xFFED4B26);
  static const Color coralStep4 = Color(0xFFFBD4CB);
  static const Color goldStep2 = Color(0xFFE5AE37);
  static const Color goldStep4 = Color(0xFFF7E5C0);
  static const Color purpleStep2 = Color(0xFFB755CD);
  static const Color purpleStep4 = Color(0xFFE9CCF0);

  // Font Families
  static bool get _usesNamedSystemFonts => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };
  static String get fontHeadline => _usesNamedSystemFonts ? 'Georgia' : 'serif';
  static String get fontBody => _usesNamedSystemFonts ? 'Arial' : 'sans-serif';

  // Asset Paths
  static const String pinkLogoAsset = 'resources/brand/Pink logo.png';

  /// Eyebrow text style: sans-serif semibold, uppercase, +15% letter-spacing, 100% line-height.
  static TextStyle eyebrowStyle({
    double fontSize = 11,
    Color color = inkBlack,
  }) {
    return TextStyle(
      fontFamily: fontBody,
      fontWeight: FontWeight.w600,
      fontSize: fontSize,
      letterSpacing: fontSize * 0.15,
      height: 1.0,
      color: color,
    );
  }

  /// Headline text style: serif medium, -1% letter-spacing, 95% line-height.
  static TextStyle headlineStyle({
    double fontSize = 26,
    Color color = inkBlack,
  }) {
    return TextStyle(
      fontFamily: fontHeadline,
      fontWeight: FontWeight.w500,
      fontSize: fontSize,
      letterSpacing: fontSize * -0.01,
      height: 0.95,
      color: color,
    );
  }

  /// Header text style: serif medium, -1% letter-spacing, 100% line-height.
  static TextStyle headerStyle({
    double fontSize = 19,
    Color color = inkBlack,
  }) {
    return TextStyle(
      fontFamily: fontHeadline,
      fontWeight: FontWeight.w500,
      fontSize: fontSize,
      letterSpacing: fontSize * -0.01,
      height: 1.0,
      color: color,
    );
  }

  /// Subhead text style: sans-serif medium, 0% letter-spacing, 130% line-height.
  static TextStyle subheadStyle({
    double fontSize = 15,
    Color color = inkBlack,
  }) {
    return TextStyle(
      fontFamily: fontBody,
      fontWeight: FontWeight.w500,
      fontSize: fontSize,
      letterSpacing: 0,
      height: 1.3,
      color: color,
    );
  }

  /// Body text style: sans-serif medium, 0% letter-spacing, 150% line-height.
  static TextStyle bodyStyle({
    double fontSize = 14,
    Color color = inkBlack,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return TextStyle(
      fontFamily: fontBody,
      fontWeight: fontWeight,
      fontSize: fontSize,
      letterSpacing: 0,
      height: 1.5,
      color: color,
    );
  }

  /// Builds the global Material 3 ThemeData adhering to the Dotdigital 2026 Design System.
  static ThemeData buildTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: brightSand,
      fontFamily: fontBody,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: inkBlack,
        onPrimary: white,
        secondary: electricPink,
        onSecondary: inkBlack,
        tertiary: neon,
        onTertiary: inkBlack,
        error: coralStep1,
        onError: white,
        surface: brightSand,
        onSurface: inkBlack,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: inkBlack,
        foregroundColor: white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontHeadline,
          fontWeight: FontWeight.w500,
          fontSize: 20,
          letterSpacing: -0.2,
          color: white,
        ),
      ),
      cardTheme: CardThemeData(
        color: softSand,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: warmSand, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: inkBlack,
          foregroundColor: white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: fontBody,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkBlack,
          side: const BorderSide(color: inkBlack, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: fontBody,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        labelStyle: TextStyle(
          fontFamily: fontBody,
          color: charcoal,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          fontFamily: fontBody,
          color: coolGray,
        ),
        helperStyle: TextStyle(
          fontFamily: fontBody,
          color: darkSand,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: warmSand, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: warmSand, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: inkBlack, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: inkBlack,
        contentTextStyle: TextStyle(
          fontFamily: fontBody,
          color: white,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
