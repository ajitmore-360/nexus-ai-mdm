import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import '../security/secure_storage.dart';

/// Manages authentication state.
///
/// SECURITY: all tokens (access and refresh) are stored using
/// [SecureStorage] which uses platform-native encrypted storage:
/// - iOS/macOS: Keychain Services
/// - Android: Keystore-backed EncryptedSharedPreferences
/// - Linux: libsecret
/// - Windows: DPAPI
///
/// Non-sensitive user metadata (display name, email) uses the same secure
/// store for consistency, since it is derived from the JWT anyway.
class AuthManager {
  static const String _demoTenantId = '00000000-0000-0000-0000-000000000001';

  /// Called by the API layer when a token refresh fails and the session
  /// cannot be recovered. Wire this up in main.dart to redirect to /login.
  static void Function()? onUnauthorized;

  // ---------------------------------------------------------------------------
  // Auth state
  // ---------------------------------------------------------------------------

  static Future<bool> isLoggedIn() async {
    return SecureStorage.isLoggedIn();
  }

  static Future<String?> getToken() async =>
      SecureStorage.read(AppConstants.storageAccessToken);

  /// Returns the stored tenant ID, or null when no session exists.
  /// The API interceptor sends no x-tenant-id header when this returns null,
  /// which correctly causes the backend to respond 401 rather than routing
  /// the request to the demo tenant.
  static Future<String?> getTenantId() async =>
      SecureStorage.read(AppConstants.storageTenantId);

  static Future<String?> getUserId() async =>
      SecureStorage.read(AppConstants.storageUserId);

  static Future<String?> getUserEmail() async =>
      SecureStorage.read(AppConstants.storageUserEmail);

  static Future<String?> getUserName() async =>
      SecureStorage.read(AppConstants.storageUserName);

  static Future<String?> getUserRole() async =>
      SecureStorage.read(AppConstants.storageUserRole);

  static Future<String?> getTenantName() async =>
      SecureStorage.read(AppConstants.storageTenantName);

  // ---------------------------------------------------------------------------
  // Login — persist tokens from API response
  // ---------------------------------------------------------------------------

  static Future<void> persistLogin({
    required String accessToken,
    required String refreshToken,
    required String tenantId,
    required String userId,
    required String email,
    required String displayName,
    String role = 'steward',
    String tenantName = '',
    List<String> assignedEntityTypes = const [],
  }) async {
    await Future.wait([
      SecureStorage.write(AppConstants.storageAccessToken,  accessToken),
      SecureStorage.write(AppConstants.storageRefreshToken, refreshToken),
      SecureStorage.write(AppConstants.storageTenantId,     tenantId),
      SecureStorage.write(AppConstants.storageUserId,       userId),
      SecureStorage.write(AppConstants.storageUserEmail,    email),
      SecureStorage.write(AppConstants.storageUserName,     displayName),
      SecureStorage.write(AppConstants.storageUserRole,     role),
      SecureStorage.write(AppConstants.storageTenantName,   tenantName),
      // Comma-separated list; empty string means no restriction (non-steward roles).
      SecureStorage.write(AppConstants.storageAssignedEntityTypes, assignedEntityTypes.join(',')),
    ]);
  }

  /// Returns entity types the steward is assigned to, or an empty list for other roles.
  static Future<List<String>> getAssignedEntityTypes() async {
    final raw = await SecureStorage.read(AppConstants.storageAssignedEntityTypes);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  // ---------------------------------------------------------------------------
  // Demo mode — used when backend is unreachable in development
  // ---------------------------------------------------------------------------

  static Future<void> persistDemoLogin(String email) async {
    final name = email.split('@').first;
    await persistLogin(
      accessToken:  'demo-token-${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: '',
      tenantId:     _demoTenantId,
      userId:       '00000000-0000-0000-0000-000000000002',
      email:        email,
      displayName:  name,
      role:         'admin',
    );
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  static Future<void> logout() async {
    // Best-effort server-side revocation — errors are non-fatal; the client
    // clears its tokens regardless so the local session always ends cleanly.
    try {
      final token    = await SecureStorage.read(AppConstants.storageAccessToken);
      final tenantId = await SecureStorage.read(AppConstants.storageTenantId);
      if (token != null && token.isNotEmpty) {
        final dio = Dio(BaseOptions(baseUrl: AppConstants.baseUrl));
        dio.options.headers['Authorization'] = 'Bearer $token';
        if (tenantId != null && tenantId.isNotEmpty) {
          dio.options.headers['x-tenant-id'] = tenantId;
        }
        await dio.post('/auth/logout');
      }
    } catch (_) {}
    await SecureStorage.clearAuth();
  }
}
