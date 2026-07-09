import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'tenant_branding.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// BrandingManager
//
// Singleton that owns the in-memory tenant branding for the running session.
// Mirrors the pattern used by LicenseManager.
//
// Startup sequence:
//   1. BrandingManager.init(apiClient)       â€” once at app boot
//   2. BrandingManager.loadFromServer()      â€” after login succeeds
//
// The themeNotifier ValueNotifier triggers a full theme rebuild in AzileMdmApp
// whenever branding changes, so Enterprise tenants see their colour scheme
// without an app restart.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class BrandingManager {
  BrandingManager._();

  static TenantBranding? _branding;
  static BrandingRepository? _repository;

  /// Notifier for the current ThemeData â€” rebuilt whenever branding is loaded.
  static final ValueNotifier<ThemeData> themeNotifier =
      ValueNotifier(AppTheme.darkTheme);

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  static void init(ApiClient client) {
    _repository = BrandingRepository(client: client);
  }

  // ---------------------------------------------------------------------------
  // Server load
  // ---------------------------------------------------------------------------

  /// Fetches branding from the server and rebuilds the theme.
  /// Silently does nothing when no branding is configured or the server is
  /// unreachable â€” the default AZILE theme is always the safe fallback.
  static Future<void> loadFromServer() async {
    if (_repository == null) return;
    try {
      _branding = await _repository!.getBranding();
      themeNotifier.value = _buildTheme(_branding);
    } catch (_) {
      // Keep the current theme on error.
    }
  }

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  static TenantBranding? get branding     => _branding;
  static String          get productName  => _branding?.productName ?? 'Azile AI MDM';
  static String?         get logoUrl      => _branding?.logoUrl;
  static String?         get supportEmail => _branding?.supportEmail;
  static String?         get supportUrl   => _branding?.supportUrl;
  static bool            get hasCustomBranding => _branding != null;

  // ---------------------------------------------------------------------------
  // Save branding (Enterprise admin action)
  // ---------------------------------------------------------------------------

  static Future<void> save(TenantBranding updated) async {
    if (_repository == null) return;
    _branding = await _repository!.upsertBranding(updated);
    themeNotifier.value = _buildTheme(_branding);
  }

  // ---------------------------------------------------------------------------
  // Clear on logout
  // ---------------------------------------------------------------------------

  static void clear() {
    _branding = null;
    themeNotifier.value = AppTheme.darkTheme;
  }

  // ---------------------------------------------------------------------------
  // Theme builder
  // ---------------------------------------------------------------------------

  static ThemeData _buildTheme(TenantBranding? b) {
    if (b == null) return AppTheme.darkTheme;

    final primary = b.primaryColor ?? AppColors.primary;
    final accent  = b.accentColor  ?? AppColors.aiPurple;

    // Patch only the color scheme; keep all typography and shape tokens intact.
    final base = AppTheme.darkTheme;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary:          primary,
        onPrimary:        _contrastFor(primary),
        primaryContainer: _darken(primary, 0.3),
        secondary:        accent,
        onSecondary:      _contrastFor(accent),
      ),
    );
  }

  // â”€â”€ Colour helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Color _contrastFor(Color c) {
    final luminance = c.computeLuminance();
    return luminance > 0.4 ? const Color(0xFF0A1628) : Colors.white;
  }

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
