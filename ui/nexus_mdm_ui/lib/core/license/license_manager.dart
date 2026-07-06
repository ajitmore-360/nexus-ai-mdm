import '../network/api_client.dart';
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
// Key activation is server-side only (POST /v1/license/activate). The client
// never holds a local key → tier mapping; all tier decisions are authorised
// by the backend.
// ─────────────────────────────────────────────────────────────────────────────

class LicenseManager {
  LicenseManager._();

  static LicenseTierInfo? _cachedTier;
  static UsageInfo?        _cachedUsage;
  static LicenseRepository? _repository;

  // ---------------------------------------------------------------------------
  // Offline essentials — used when the server is temporarily unreachable.
  // Grants only the core always-on features so the app stays usable without
  // silently granting higher-tier access.
  // ---------------------------------------------------------------------------
  static const _offlineEssentials = LicenseTierInfo(
    tier:        'essentials',
    status:      'offline',
    maxDomains:  1,
    maxRecords:  500000,
    maxStewards: 5,
    features:    {},
  );

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  static void init(ApiClient client) {
    _repository = LicenseRepository(client: client);
  }

  // ---------------------------------------------------------------------------
  // Server load (call after login)
  // ---------------------------------------------------------------------------

  /// Fetches the tenant license from the server and caches it in memory.
  /// On network failure, falls back to [_offlineEssentials] so the app
  /// remains usable with core features only — no local key backdoor.
  static Future<void> loadFromServer() async {
    if (_repository == null) return;
    try {
      final (tier, usage) = await _repository!.getMyLicense();
      _cachedTier  = tier;
      _cachedUsage = usage;
    } catch (_) {
      _cachedTier  = _offlineEssentials;
      _cachedUsage = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Access checks
  // ---------------------------------------------------------------------------

  static bool hasModule(LicensedModule module) {
    if (_cachedTier == null) return false;
    if (module.featureKey == null) return true;
    return _cachedTier!.hasFeature(module.featureKey!);
  }

  static bool hasFeature(String featureKey) =>
      _cachedTier?.hasFeature(featureKey) ?? false;

  static Future<Set<LicensedModule>> getActiveModules() async {
    if (!isLoaded) await loadFromServer();
    return LicensedModule.values.where((m) => hasModule(m)).toSet();
  }

  // ---------------------------------------------------------------------------
  // State accessors
  // ---------------------------------------------------------------------------

  static LicenseTierInfo? get currentTier    => _cachedTier;
  static UsageInfo?        get currentUsage   => _cachedUsage;
  static bool              get isLoaded       => _cachedTier != null;
  static bool              get isOffline      => _cachedTier?.status == 'offline';
  static bool              get isProfessional => _cachedTier?.isProfessional ?? false;
  static bool              get isEnterprise   => _cachedTier?.isEnterprise ?? false;

  // ---------------------------------------------------------------------------
  // License key activation (server-validated)
  // ---------------------------------------------------------------------------

  /// Submits [key] to the backend for validation and tier assignment.
  /// On success: updates the in-memory cache with the activated tier and
  /// returns that [LicenseTierInfo].
  /// On failure: throws a [LicenseActivationException] with a user-facing message.
  static Future<LicenseTierInfo> activate(String key) async {
    if (_repository == null) {
      throw const LicenseActivationException(
        'License service not initialised. Call LicenseManager.init() first.',
      );
    }
    final tier = await _repository!.activateLicenseKey(key);
    _cachedTier = tier;
    return tier;
  }

  /// Clears the in-memory cache (logout / tenant switch).
  static void revoke() {
    _cachedTier  = null;
    _cachedUsage = null;
  }
}
