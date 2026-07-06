import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Encrypted storage for authentication tokens and credentials.
///
/// On native platforms (iOS, Android, Windows, Linux, macOS) this uses
/// platform-secure enclaves (Keychain, Keystore, DPAPI, libsecret).
///
/// On web, flutter_secure_storage's IndexedDB/WebCrypto backend can throw
/// OperationError in some browser configurations, so we fall back to
/// SharedPreferences (localStorage). Web tokens are short-lived (15 min
/// access / 7 day refresh) and the app is served over localhost/HTTPS.
class SecureStorage {
  SecureStorage._();

  static const _nativeStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
    wOptions: WindowsOptions(),
  );

  /// Write a value to platform-appropriate storage.
  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _nativeStorage.write(key: key, value: value);
    }
  }

  /// Read a value from platform-appropriate storage.
  static Future<String?> read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _nativeStorage.read(key: key);
  }

  /// Delete a key from storage.
  static Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _nativeStorage.delete(key: key);
    }
  }

  /// Delete all auth-related keys (logout).
  static Future<void> clearAuth() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(AppConstants.storageAccessToken),
        prefs.remove(AppConstants.storageRefreshToken),
        prefs.remove(AppConstants.storageTenantId),
        prefs.remove(AppConstants.storageUserId),
        prefs.remove(AppConstants.storageUserEmail),
        prefs.remove(AppConstants.storageUserName),
        prefs.remove(AppConstants.storageUserRole),
        prefs.remove(AppConstants.storageAssignedEntityTypes),
      ]);
    } else {
      await Future.wait([
        _nativeStorage.delete(key: AppConstants.storageAccessToken),
        _nativeStorage.delete(key: AppConstants.storageRefreshToken),
        _nativeStorage.delete(key: AppConstants.storageTenantId),
        _nativeStorage.delete(key: AppConstants.storageUserId),
        _nativeStorage.delete(key: AppConstants.storageUserEmail),
        _nativeStorage.delete(key: AppConstants.storageUserName),
        _nativeStorage.delete(key: AppConstants.storageUserRole),
        _nativeStorage.delete(key: AppConstants.storageAssignedEntityTypes),
      ]);
    }
  }

  /// Check if the user is logged in (access token exists and non-empty).
  static Future<bool> isLoggedIn() async {
    final token = await read(AppConstants.storageAccessToken);
    return token != null && token.isNotEmpty;
  }
}
