import 'package:flutter/material.dart' show BoxShadow, Color, Colors, LinearGradient, Alignment, Offset;

class AppColors {
  AppColors._();

  // Primary Sage System — Azile brand color RGB(89,155,129)
  static const Color primary = Color(0xFF599B81);        // sage
  static const Color violetLight = Color(0xFF82BBA3);    // sage-hi
  static const Color violetDark = Color(0xFF2C5942);     // sage-lo

  // Legacy aliases (kept for compile compatibility)
  static const Color darkGreen = Color(0xFF2C5942);      // sage-lo
  static const Color lightGreen = Color(0xFF82BBA3);     // sage-hi
  static const Color mintAccent = Color(0xFF82BBA3);     // sage-hi

  // Accent / data colors
  static const Color cyan = Color(0xFF00D9FF);
  static const Color cyanDark = Color(0xFF0099BB);

  // Background System — near-black with sage undertone
  static const Color navyBackground = Color(0xFF070E0B);   // void — chosen green-black
  static const Color surface = Color(0xFF0C1410);
  static const Color cardSurface = Color(0xFF111C16);
  static const Color elevatedCard = Color(0xFF16211A);
  static const Color sidebarBackground = Color(0xFF090D0B);
  static const Color sidebarSelected = Color(0x16599B81);  // rgba(89,155,129,0.086)
  static const Color sidebarHover = Color(0x0E599B81);     // rgba(89,155,129,0.055)

  // Divider / input fill
  static const Color divider = Color(0x14FFFFFF);          // rgba(255,255,255,0.08)
  static const Color inputFill = Color(0x4D000000);        // rgba(0,0,0,0.3)

  // Text System
  static const Color primaryText = Color(0xFFEBF3EF);      // sage-tinted off-white
  static const Color secondaryText = Color(0xFF789A89);    // sage grey
  static const Color mutedText = Color(0xFF3D5547);        // dark sage muted
  static const Color hintText = Color(0xFF3D5547);         // alias for mutedText

  // Semantic Colors
  static const Color error = Color(0xFFFF3366);
  static const Color errorLight = Color(0x1AFF3366);
  static const Color success = Color(0xFF10F090);
  static const Color successLight = Color(0x1A10F090);
  static const Color warning = Color(0xFFFFB800);
  static const Color warningLight = Color(0x1AFFB800);
  static const Color info = Color(0xFF00D9FF);
  static const Color infoLight = Color(0x1A00D9FF);

  // AI Teal accent — distinct from brand sage for AI Prism feature surfaces
  static const Color aiPurple = Color(0xFF3DB89A);         // teal
  static const Color aiPurpleLight = Color(0xFF6DD4BE);    // teal-light
  static const Color aiPurpleDark = Color(0xFF1A8A6E);     // teal-dark

  // Status Colors
  static const Color statusActive = Color(0xFF10F090);
  static const Color statusGolden = Color(0xFFFFB800);
  static const Color statusReview = Color(0xFFFFB800);
  static const Color statusMerged = Color(0xFF3DB89A);
  static const Color statusInactive = Color(0xFF3D5547);

  // Chart Colors
  static const List<Color> chartPalette = [
    Color(0xFF599B81),  // sage
    Color(0xFF00D9FF),  // cyan
    Color(0xFF3DB89A),  // teal
    Color(0xFFFFB800),  // amber
    Color(0xFFFF3366),  // coral
    Color(0xFF82BBA3),  // sage-hi
    Color(0xFF2C5942),  // sage-lo
    Color(0xFF0099BB),  // cyan-dark
  ];

  // Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF599B81), Color(0xFF82BBA3)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF111C16), Color(0xFF070E0B)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF599B81), Color(0xFF82BBA3)],
  );

  static const LinearGradient warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB800), Color(0xFFCC8800)],
  );

  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF3366), Color(0xFFCC0033)],
  );

  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00D9FF), Color(0xFF0099BB)],
  );

  // Overlay
  static const Color overlay = Color(0x80000000);
  static const Color modalBackground = Color(0xFF111C16);

  // Glass / Blur surfaces  (use with BackdropFilter)
  static const Color glassSurface = Color(0xED111C16);    // ~93% opaque cardSurface
  static const Color glassBorder  = Color(0x40FFFFFF);    // subtle at 25%

  // Aurora accent colors
  static const Color auroraBlue   = Color(0xFF00D9FF);    // cyan
  static const Color auroraGreen  = Color(0xFF82BBA3);    // sage-hi
  static const Color auroraPurple = Color(0xFF3DB89A);    // teal

  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF82BBA3),  // sage-hi
      Color(0xFF599B81),  // sage
      Color(0xFF3DB89A),  // teal
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static List<BoxShadow> glowShadow({Color? color, double intensity = 1.0}) => [
    BoxShadow(
      color: (color ?? primary).withValues(alpha: 0.08 * intensity),
      blurRadius: 80,
      spreadRadius: -10,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      blurRadius: 48,
      offset: const Offset(0, 20),
    ),
  ];
}
