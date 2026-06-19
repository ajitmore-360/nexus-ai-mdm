import 'package:flutter/material.dart' show BoxShadow, Color, Colors, LinearGradient, Alignment, Offset;

class AppColors {
  AppColors._();

  // Primary Violet System (Gen-Z dark aesthetic)
  static const Color primary = Color(0xFF7C3AED);        // violet — replaces green
  static const Color violetLight = Color(0xFFA855F7);
  static const Color violetDark = Color(0xFF5B21B6);

  // Legacy aliases kept so existing code compiles unchanged
  static const Color darkGreen = Color(0xFF5B21B6);      // remapped → violetDark
  static const Color lightGreen = Color(0xFFA855F7);     // remapped → violetLight
  static const Color mintAccent = Color(0xFFA855F7);     // remapped → violetLight

  // Accent / data colors
  static const Color cyan = Color(0xFF00D9FF);
  static const Color cyanDark = Color(0xFF0099BB);

  // Background System
  static const Color navyBackground = Color(0xFF08080F);   // deep dark
  static const Color surface = Color(0xFF0E0E1A);
  static const Color cardSurface = Color(0xFF14142A);
  static const Color elevatedCard = Color(0xFF1A1A2E);
  static const Color sidebarBackground = Color(0xFF0A0A16);
  static const Color sidebarSelected = Color(0x147C3AED);  // rgba(124,58,237,0.08)
  static const Color sidebarHover = Color(0x0C7C3AED);

  // Divider / input fill
  static const Color divider = Color(0x14FFFFFF);          // rgba(255,255,255,0.08)
  static const Color inputFill = Color(0x4D000000);        // rgba(0,0,0,0.3)

  // Text System
  static const Color primaryText = Color(0xFFF0F0FF);
  static const Color secondaryText = Color(0xFF8888AA);
  static const Color mutedText = Color(0xFF44445A);
  static const Color hintText = Color(0xFF44445A);         // alias for mutedText

  // Semantic Colors
  static const Color error = Color(0xFFFF3366);            // coral
  static const Color errorLight = Color(0x1AFF3366);       // rgba(255,51,102,0.1)
  static const Color success = Color(0xFF10F090);          // green
  static const Color successLight = Color(0x1A10F090);     // rgba(16,240,144,0.1)
  static const Color warning = Color(0xFFFFB800);          // amber
  static const Color warningLight = Color(0x1AFFB800);     // rgba(255,184,0,0.1)
  static const Color info = Color(0xFF00D9FF);             // remapped → cyan
  static const Color infoLight = Color(0x1A00D9FF);

  // AI Purple (kept for AI features)
  static const Color aiPurple = Color(0xFFA855F7);
  static const Color aiPurpleLight = Color(0xFF7C3AED);
  static const Color aiPurpleDark = Color(0xFF5B21B6);

  // Status Colors
  static const Color statusActive = Color(0xFF10F090);     // green
  static const Color statusGolden = Color(0xFFFFB800);     // amber
  static const Color statusReview = Color(0xFFFFB800);     // amber
  static const Color statusMerged = Color(0xFFA855F7);     // violet light
  static const Color statusInactive = Color(0xFF44445A);   // mutedText

  // Chart Colors
  static const List<Color> chartPalette = [
    Color(0xFF7C3AED),  // violet
    Color(0xFF00D9FF),  // cyan
    Color(0xFFA855F7),  // violet light
    Color(0xFFFFB800),  // amber
    Color(0xFFFF3366),  // coral
    Color(0xFF10F090),  // green
    Color(0xFF5B21B6),  // violet dark
    Color(0xFF0099BB),  // cyan dark
  ];

  // Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14142A), Color(0xFF08080F)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
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
  static const Color modalBackground = Color(0xFF14142A);

  // Glass / Blur surfaces  (use with BackdropFilter)
  static const Color glassSurface = Color(0xED14142A);    // ~93% opaque cardSurface
  static const Color glassBorder  = Color(0x40FFFFFF);    // subtle at 25%

  // Aurora accent colors
  static const Color auroraBlue   = Color(0xFF00D9FF);    // cyan
  static const Color auroraGreen  = Color(0xFF10F090);    // green
  static const Color auroraPurple = Color(0xFFA855F7);    // violet light

  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFA855F7),  // violet light
      Color(0xFF7C3AED),  // violet
      Color(0xFF00D9FF),  // cyan
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Subtle glow shown beneath glassmorphic surfaces.
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
