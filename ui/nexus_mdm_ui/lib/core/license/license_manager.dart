import '../constants/app_constants.dart';
import '../network/api_client.dart';
import '../security/secure_storage.dart';
import 'license_repository.dart';
import 'licensed_module.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LicenseManager
//
// Singleton that owns the in-memory license state for the running session.
//
// Startup sequence:
//   1. LicenseManager.init(apiClient)       — call once at app boot
//   2. LicenseManager.loadFromServer()      — call after login succeeds
//
// If the server is unreachable the manager falls back to the stored demo key
// so the app stays usable for development / onboarding.
// ─────────────────────────────────────────────────────────────────────────────

class LicenseManager {
  LicenseManager._();

  static LicenseTierInfo? _cachedTier;
  static UsageInfo? _cachedUsage;
  static LicenseRepository? _repository;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Call once at app boot before any license checks are performed.
  static void init(ApiClient client) {
    _repository = LicenseRepository(client: client);
  }

  // ---------------------------------------------------------------------------
  // Server load (call after login)
  // ---------------------------------------------------------------------------

  /// Fetches the tenant license from the server and caches it in memory.
  /// Falls back to the locally-stored demo key when the server is unreachable.
  static Future<void> loadFromServer() async {
    if (_repository == null) return;
    try {
      final (tier, usage) = await _repository!.getMyLicense();
      _cachedTier = tier;
      _cachedUsage = usage;
    } catch (_) {
      // Server unreachable — fall back to demo key stored in secure storage.
      final key = await SecureStorage.read(AppConstants.storageLicenseKey);
      _cachedTier = _tierFromDemoKey(key);
      _cachedUsage = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Access checks
  // ---------------------------------------------------------------------------

  /// Returns true when the current tenant has access to [module].
  /// Always returns true for always-on modules (featureKey == null).
  static bool hasModule(LicensedModule module) {
    if (_cachedTier == null) return false; // not loaded yet
    if (module.featureKey == null) return true; // always-on (e.g. lineage)
    return _cachedTier!.hasFeature(module.featureKey!);
  }

  /// Returns true when the current tenant has the named feature flag enabled.
  static bool hasFeature(String featureKey) =>
      _cachedTier?.hasFeature(featureKey) ?? false;

  /// Returns the set of [LicensedModule]s the current tenant has access to.
  /// Triggers [loadFromServer] if the license hasn't been loaded yet.
  static Future<Set<LicensedModule>> getActiveModules() async {
    if (!isLoaded) await loadFromServer();
    return LicensedModule.values.where((m) => hasModule(m)).toSet();
  }

  // ---------------------------------------------------------------------------
  // State accessors
  // ---------------------------------------------------------------------------

  static LicenseTierInfo? get currentTier  => _cachedTier;
  static UsageInfo?        get currentUsage => _cachedUsage;
  static bool              get isLoaded      => _cachedTier != null;
  static bool              get isProfessional => _cachedTier?.isProfessional ?? false;
  static bool              get isEnterprise   => _cachedTier?.isEnterprise ?? false;

  // ---------------------------------------------------------------------------
  // Demo key fallback (dev / onboarding)
  // ---------------------------------------------------------------------------

  /// Builds a [LicenseTierInfo] from a known demo key.
  /// Used both as the server-unreachable fallback and by [activate].
  static LicenseTierInfo _tierFromDemoKey(String? key) {
    switch (key?.trim().toUpperCase()) {
      case 'NXS-PRO-2026':
      case 'NXS-PRO-2027':
        return const LicenseTierInfo(
          tier: 'professional',
          status: 'active',
          maxDomains: 5,
          maxRecords: 5000000,
          maxStewards: 20,
          features: {
            'ai_copilot': true,
            'matching_semantic': true,
            'relationships': true,
            'domain_policies': true,
            'data_quality': true,
            'analytics': true,
            'governance': true,
            'distribution': true,
          },
        );
      case 'NXS-ENT-2026':
      case 'NXS-ENT-2027':
      case 'NXS-FULL-2026':
        return const LicenseTierInfo(
          tier: 'enterprise',
          status: 'active',
          maxDomains: -1,
          maxRecords: -1,
          maxStewards: -1,
          features: {
            'ai_copilot': true,
            'matching_semantic': true,
            'relationships': true,
            'domain_policies': true,
            'data_quality': true,
            'analytics': true,
            'governance': true,
            'distribution': true,
            'white_label': true,
          },
        );
      default:
        return const LicenseTierInfo(
          tier: 'essentials',
          status: 'active',
          maxDomains: 1,
          maxRecords: 500000,
          maxStewards: 5,
          features: {},
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Legacy: manual key activation (used on the license entry screen)
  // ---------------------------------------------------------------------------

  /// Validates [key] against known demo keys, caches the resulting tier, and
  /// persists the key to secure storage. Always returns true (every key maps
  /// to at least the Essentials tier).
  static Future<bool> activate(String key) async {
    final normalised = key.trim().toUpperCase();
    _cachedTier = _tierFromDemoKey(normalised);
    await SecureStorage.write(AppConstants.storageLicenseKey, normalised);
    return true;
  }

  /// Clears the in-memory cache and wipes the stored key.
  static Future<void> revoke() async {
    _cachedTier = null;
    _cachedUsage = null;
    await SecureStorage.write(AppConstants.storageLicenseKey, '');
  }

  // ---------------------------------------------------------------------------
  // Demo keys (shown on the license / onboarding screen)
  // ---------------------------------------------------------------------------

  static const List<({String key, String label, String tier})> demoKeys = [
    (key: 'NXS-PRO-2026',  label: 'Professional', tier: 'Core + all Professional modules'),
    (key: 'NXS-ENT-2026',  label: 'Enterprise',   tier: 'All modules + white-label'),
  ];
}
