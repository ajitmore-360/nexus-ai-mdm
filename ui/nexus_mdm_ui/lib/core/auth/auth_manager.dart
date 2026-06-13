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

  // ---------------------------------------------------------------------------
  // Auth state
  // ---------------------------------------------------------------------------

  static Future<bool> isLoggedIn() async {
    return SecureStorage.isLoggedIn();
  }

  static Future<String?> getToken() async =>
      SecureStorage.read(AppConstants.storageAccessToken);

  static Future<String?> getTenantId() async =>
      (await SecureStorage.read(AppConstants.storageTenantId)) ?? _demoTenantId;

  static Future<String?> getUserEmail() async =>
      SecureStorage.read(AppConstants.storageUserEmail);

  static Future<String?> getUserName() async =>
      SecureStorage.read(AppConstants.storageUserName);

  static Future<String?> getUserRole() async =>
      SecureStorage.read(AppConstants.storageUserRole);

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
  }) async {
    await Future.wait([
      SecureStorage.write(AppConstants.storageAccessToken,  accessToken),
      SecureStorage.write(AppConstants.storageRefreshToken, refreshToken),
      SecureStorage.write(AppConstants.storageTenantId,     tenantId),
      SecureStorage.write(AppConstants.storageUserId,       userId),
      SecureStorage.write(AppConstants.storageUserEmail,    email),
      SecureStorage.write(AppConstants.storageUserName,     displayName),
      SecureStorage.write(AppConstants.storageUserRole,     role),
    ]);
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
    await SecureStorage.clearAuth();
  }
}
