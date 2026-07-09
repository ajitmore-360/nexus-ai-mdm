import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_manager.dart';
import '../../../../core/auth/sso_service.dart';
import '../../../../core/branding/branding_manager.dart';
import '../../../../core/license/license_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// AuthCallbackPage
//
// Handles the OAuth2 redirect callback at /auth-callback.
//
// GoRouter passes the query parameters as constructor arguments:
//   code  â€” authorization code from the provider (success path)
//   error â€” provider error code (cancelled / denied)
//
// On mount this page:
//   1. Reads the PKCE verifier, provider, and token URL from sessionStorage.
//   2. Exchanges the authorization code for an access token at the provider.
//   3. Sends the access token to POST /auth/sso-exchange to get AZILE JWTs.
//   4. Persists tokens via AuthManager and navigates to /dashboard.
//
// On any error it shows the message and a "Try again" link back to /login.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class AuthCallbackPage extends StatefulWidget {
  final String? code;
  final String? error;
  final String? errorDescription;

  const AuthCallbackPage({
    super.key,
    this.code,
    this.error,
    this.errorDescription,
  });

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    // Provider returned an error (e.g. user cancelled or denied access).
    if (widget.error != null) {
      final detail = widget.errorDescription ?? widget.error;
      setState(() => _errorMessage = 'SSO was cancelled or denied: $detail');
      return;
    }

    final code = widget.code;
    if (code == null || code.isEmpty) {
      setState(() => _errorMessage = 'No authorization code received from provider.');
      return;
    }

    try {
      final apiClient = GetIt.instance<ApiClient>();
      final data = await SsoService.completeFlow(code: code, client: apiClient);

      final token       = data['access_token']   as String;
      final refresh     = data['refresh_token']  as String? ?? '';
      final userMap     = data['user']            as Map<String, dynamic>? ?? {};
      final tenantId    = userMap['tenant_id']    as String? ?? '';
      final userId      = userMap['user_id']      as String? ?? '';
      final email       = userMap['email']        as String? ?? '';
      final displayName = userMap['display_name'] as String? ?? email.split('@').first;
      final role        = userMap['role']         as String? ?? 'steward';
      final tenantName  = userMap['tenant_name']  as String? ?? '';

      await AuthManager.persistLogin(
        accessToken:  token,
        refreshToken: refresh,
        tenantId:     tenantId,
        userId:       userId,
        email:        email,
        displayName:  displayName,
        role:         role,
        tenantName:   tenantName,
      );
      apiClient.setAuthToken(token);
      apiClient.setTenantId(tenantId);

      await Future.wait([
        LicenseManager.loadFromServer(),
        BrandingManager.loadFromServer(),
      ]);

      if (mounted) context.go('/dashboard');
    } on SsoException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Center(
        child: _errorMessage != null
            ? _buildError(_errorMessage!)
            : _buildLoading(),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text('Completing sign-inâ€¦', style: AppTextStyles.bodyMedium),
      ],
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Sign-in failed',
            style: AppTextStyles.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }
}
