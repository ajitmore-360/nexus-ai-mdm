// ignore: avoid_web_libraries_in_flutter â€” this app is web-only.
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../network/api_client.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// SsoService â€” OAuth2 Authorization Code + PKCE (S256) for Flutter Web
//
// Flow:
//   1. Caller invokes start*Flow().  The browser is redirected to the
//      provider's authorization endpoint.  The PKCE verifier, provider name,
//      and provider token URL are stored in window.sessionStorage so the
//      callback page can retrieve them after the redirect.
//   2. The provider redirects back to <origin>/auth-callback?code=...
//      The AuthCallbackPage calls completeFlow(code, client).
//   3. completeFlow() exchanges the authorization code for an access_token
//      directly at the provider's token endpoint (public PKCE client, no secret).
//   4. The access_token is sent to POST /auth/sso-exchange on the AZILE backend,
//      which validates it via the provider's userinfo endpoint and returns a
//      AZILE JWT pair.
//
// Required --dart-define flags at build time:
//   GOOGLE_CLIENT_ID   â€” Google OAuth2 client ID (Web Application type)
//   AZURE_CLIENT_ID    â€” Azure AD application (client) ID
//   AZURE_TENANT_ID    â€” Azure AD tenant ID (default: "common")
//   OKTA_CLIENT_ID     â€” Okta OIDC application client ID
//   OKTA_ISSUER        â€” Okta org authorization server URL (e.g. https://xxx.okta.com)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class SsoService {
  SsoService._();

  // sessionStorage keys â€” cleared immediately after the callback reads them.
  static const _kVerifier  = 'azile_pkce_verifier';
  static const _kProvider  = 'AZILE_sso_provider';
  static const _kTokenUrl  = 'AZILE_sso_token_url';
  static const _kClientId  = 'AZILE_sso_client_id';

  // ---------------------------------------------------------------------------
  // Start flows â€” redirects the browser to the provider
  // ---------------------------------------------------------------------------

  static void startGoogleFlow() {
    _requireConfig(AppConstants.googleClientId, 'GOOGLE_CLIENT_ID');
    _startFlow(
      provider: 'google',
      clientId: AppConstants.googleClientId,
      authUrl:  AppConstants.googleAuthUrl,
      tokenUrl: AppConstants.googleTokenUrl,
      scopes:   'openid email profile',
    );
  }

  static void startAzureFlow() {
    _requireConfig(AppConstants.azureClientId, 'AZURE_CLIENT_ID');
    final tenant = AppConstants.azureTenantId.isEmpty ? 'common' : AppConstants.azureTenantId;
    _startFlow(
      provider: 'azure',
      clientId: AppConstants.azureClientId,
      authUrl:  'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize',
      tokenUrl: 'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token',
      scopes:   'openid email profile',
    );
  }

  static void startOktaFlow() {
    _requireConfig(AppConstants.oktaClientId,  'OKTA_CLIENT_ID');
    _requireConfig(AppConstants.oktaIssuer,    'OKTA_ISSUER');
    final issuer = AppConstants.oktaIssuer.replaceAll(RegExp(r'/+$'), '');
    _startFlow(
      provider: 'okta',
      clientId: AppConstants.oktaClientId,
      authUrl:  '$issuer/v1/authorize',
      tokenUrl: '$issuer/v1/token',
      scopes:   'openid email profile',
    );
  }

  // ---------------------------------------------------------------------------
  // Complete flow â€” called by AuthCallbackPage with the authorization code
  // ---------------------------------------------------------------------------

  /// Exchanges [code] for an access token at the provider, then sends the
  /// access token to the AZILE backend's /auth/sso-exchange endpoint.
  /// Returns the `data` map from the backend response (access_token, user, etc.)
  static Future<Map<String, dynamic>> completeFlow({
    required String code,
    required ApiClient client,
  }) async {
    final storage  = html.window.sessionStorage;
    final verifier = storage[_kVerifier];
    final provider = storage[_kProvider];
    final tokenUrl = storage[_kTokenUrl];
    final clientId = storage[_kClientId];

    // Clear session state immediately to prevent replay
    storage.remove(_kVerifier);
    storage.remove(_kProvider);
    storage.remove(_kTokenUrl);
    storage.remove(_kClientId);

    if (verifier == null || provider == null || tokenUrl == null || clientId == null) {
      throw const SsoException(
        'SSO session state is missing. The page may have been refreshed during login. '
        'Please try again.',
      );
    }

    // Exchange authorization code for provider access token.
    // The token endpoint is called directly (public PKCE client â€” no client_secret).
    final tokenDio = Dio();
    final formBody = [
      'grant_type=authorization_code',
      'code=${Uri.encodeComponent(code)}',
      'redirect_uri=${Uri.encodeComponent(_redirectUri)}',
      'client_id=${Uri.encodeComponent(clientId)}',
      'code_verifier=${Uri.encodeComponent(verifier)}',
    ].join('&');

    final tokenResp = await tokenDio
        .post<Map<String, dynamic>>(
          tokenUrl,
          data: formBody,
          options: Options(
            headers: {'content-type': 'application/x-www-form-urlencoded'},
            validateStatus: (_) => true,  // handle errors manually
          ),
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw const SsoException('Token exchange timed out.'),
        );

    final tokenData = tokenResp.data ?? {};
    if (tokenResp.statusCode != 200) {
      final detail = tokenData['error_description'] ?? tokenData['error'] ?? 'unknown';
      throw SsoException('Token exchange failed: $detail');
    }

    final accessToken = tokenData['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const SsoException('Provider did not return an access token.');
    }

    // Send to AZILE backend â€” backend validates against provider's userinfo endpoint.
    final exchangeResp = await client.post<Map<String, dynamic>>(
      AppConstants.ssoExchangePath,
      data: {'provider': provider, 'access_token': accessToken},
    );

    final body = exchangeResp.data!;
    if (body['success'] != true) {
      throw SsoException(body['error'] as String? ?? 'SSO login failed.');
    }
    return body['data'] as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String get _redirectUri {
    final origin = html.window.location.origin;
    return '$origin${AppConstants.authCallbackPath}';
  }

  static void _startFlow({
    required String provider,
    required String clientId,
    required String authUrl,
    required String tokenUrl,
    required String scopes,
  }) {
    final verifier  = _generateVerifier();
    final challenge = _computeChallenge(verifier);

    // Persist PKCE state for the callback page (survives the redirect)
    final storage = html.window.sessionStorage;
    storage[_kVerifier] = verifier;
    storage[_kProvider] = provider;
    storage[_kTokenUrl] = tokenUrl;
    storage[_kClientId] = clientId;

    final params = {
      'client_id':             clientId,
      'redirect_uri':          _redirectUri,
      'response_type':         'code',
      'scope':                 scopes,
      'state':                 _generateVerifier().substring(0, 32),
      'code_challenge':        challenge,
      'code_challenge_method': 'S256',
    };

    html.window.location.href = '$authUrl?${_buildQuery(params)}';
  }

  static String _generateVerifier() {
    final random = Random.secure();
    final bytes  = List<int>.generate(64, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _computeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final hash  = sha256.convert(bytes);
    return base64Url.encode(hash.bytes).replaceAll('=', '');
  }

  static String _buildQuery(Map<String, String> params) => params.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  static void _requireConfig(String value, String envKey) {
    if (value.isEmpty) {
      throw SsoConfigException(
        'SSO is not configured: $envKey is not set.\n'
        'Build with --dart-define=$envKey=<value> to enable this provider.',
      );
    }
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Exceptions
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class SsoException implements Exception {
  final String message;
  const SsoException(this.message);
  @override
  String toString() => message;
}

class SsoConfigException extends SsoException {
  const SsoConfigException(super.message);
}
