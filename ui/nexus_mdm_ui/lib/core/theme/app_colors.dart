import 'package:flutter/material.dart' show BoxShadow, Color, Colors, LinearGradient, Alignment, Offset;

class AppColors {
  AppColors._();

  // Primary Green System
  static const Color primary = Color(0xFF00C896);
  static const Color darkGreen = Color(0xFF007A5E);
  static const Color lightGreen = Color(0xFF00E6AB);
  static const Color mintAccent = Color(0xFFB5F5E0);

  // Background System
  static const Color navyBackground = Color(0xFF0A1628);
  static const Color cardSurface = Color(0xFF0F2035);
  static const Color elevatedCard = Color(0xFF1A3050);
  static const Color divider = Color(0xFF1E3A5F);
  static const Color inputFill = Color(0xFF0D1F35);

  // Text System
  static const Color primaryText = Color(0xFFE8F5F0);
  static const Color secondaryText = Color(0xFF8BA8B8);
  static const Color mutedText = Color(0xFF4A6580);
  static const Color hintText = Color(0xFF3A5570);

  // Semantic Colors
  static const Color warning = Color(0xFFFF8C42);
  static const Color warningLight = Color(0xFFFFF0E6);
  static const Color error = Color(0xFFFF4D6D);
  static const Color errorLight = Color(0xFFFFE5EB);
  static const Color success = Color(0xFF00C896);
  static const Color successLight = Color(0xFFE0FFF5);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFEFF6FF);

  // AI Purple
  static const Color aiPurple = Color(0xFF8B5CF6);
  static const Color aiPurpleLight = Color(0xFFEDE9FE);
  static const Color aiPurpleDark = Color(0xFF6D28D9);

  // Status Colors
  static const Color statusActive = Color(0xFF00C896);
  static const Color statusGolden = Color(0xFFFFD700);
  static const Color statusReview = Color(0xFFFF8C42);
  static const Color statusMerged = Color(0xFF8B5CF6);
  static const Color statusInactive = Color(0xFF4A6580);

  // Chart Colors
  static const List<Color> chartPalette = [
    Color(0xFF00C896),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFFFF8C42),
    Color(0xFFFF4D6D),
    Color(0xFF06B6D4),
    Color(0xFFFFD700),
    Color(0xFF10B981),
  ];

  // Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00C896), Color(0xFF007A5E)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F2035), Color(0xFF0A1628)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );

  static const LinearGradient warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8C42), Color(0xFFE55A00)],
  );

  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF4D6D), Color(0xFFCC0030)],
  );

  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  );

  // Sidebar
  static const Color sidebarBackground = Color(0xFF071220);
  static const Color sidebarSelected = Color(0xFF0F2035);
  static const Color sidebarHover = Color(0xFF0D1A2E);

  // Overlay
  static const Color overlay = Color(0x80000000);
  static const Color modalBackground = Color(0xFF0F2035);

  // Glass / Blur surfaces  (use with BackdropFilter)
  static const Color glassSurface = Color(0xED0F2035); // ~93% opaque navy
  static const Color glassBorder  = Color(0x401E3A5F); // subtle divider at 25%

  // Aurora accent colors — used for the command palette and AI header glow
  static const Color auroraBlue   = Color(0xFF3B82F6);
  static const Color auroraGreen  = Color(0xFF00C896);
  static const Color auroraPurple = Color(0xFF8B5CF6);

  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF8B5CF6),
      Color(0xFF3B82F6),
      Color(0xFF00C896),
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
