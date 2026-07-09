import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/auth/sso_service.dart';
import '../../../../core/branding/branding_manager.dart';
import '../../../../core/license/license_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/widgets/azile_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({String? forcedTenantId}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!mounted) return;

    try {
      // Use the singleton ApiClient so auth headers set below take effect
      // immediately for all subsequent requests in this session.
      final apiClient = GetIt.instance<ApiClient>();
      final payload = <String, dynamic>{
        'email':    _emailController.text.trim(),
        'password': _passwordController.text,
      };
      if (forcedTenantId != null) payload['tenant_id'] = forcedTenantId;

      final response = await apiClient.post<Map<String, dynamic>>(
        AppConstants.loginPath,
        data: payload,
      );

      final body = response.data;

      // Server found multiple tenant memberships â€” show picker then retry.
      if (body?['requires_tenant_selection'] == true) {
        setState(() => _isLoading = false);
        final tenants = (body!['tenants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final chosen = await _showTenantPicker(tenants);
        if (chosen != null && mounted) await _handleLogin(forcedTenantId: chosen);
        return;
      }

      final success = body?['success'] == true;
      if (!success) {
        throw Exception(body?['error'] ?? 'Login failed');
      }

      // Persist tokens securely (Keychain / Keystore â€” never plaintext)
      final data        = body!['data'] as Map<String, dynamic>;
      final token       = data['access_token']   as String;
      final refresh     = data['refresh_token']  as String? ?? '';
      final userMap     = data['user']            as Map<String, dynamic>? ?? {};
      final tenantId    = userMap['tenant_id']    as String? ?? '';
      final userId      = userMap['user_id']      as String? ?? '';
      final email       = userMap['email']        as String?
                        ?? _emailController.text.trim();
      final displayName = userMap['display_name'] as String?
                        ?? email.split('@').first;
      final role        = userMap['role']         as String? ?? 'steward';
      final tenantName  = userMap['tenant_name']  as String? ?? '';
      final assignedEntityTypes = (userMap['assigned_entity_types'] as List<dynamic>?)
          ?.cast<String>() ?? [];

      await AuthManager.persistLogin(
        accessToken:          token,
        refreshToken:         refresh,
        tenantId:             tenantId,
        userId:               userId,
        email:                email,
        displayName:          displayName,
        role:                 role,
        tenantName:           tenantName,
        assignedEntityTypes:  assignedEntityTypes,
      );

      // Update the live singleton so every subsequent request has the correct
      // headers without waiting for the async interceptor to re-read storage.
      apiClient.setAuthToken(token);
      apiClient.setTenantId(tenantId);

      // Load license + branding in parallel â€” both are fire-and-forget safe;
      // failures fall back to defaults without blocking navigation.
      await Future.wait([
        LicenseManager.loadFromServer(),
        BrandingManager.loadFromServer(),
      ]);

      if (mounted) context.go('/dashboard');

    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading    = false;
        _errorMessage = e.message;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final String msg;
      switch (e.type) {
        case DioExceptionType.connectionError:
          msg = 'Cannot reach the server. Make sure the backend is running on ${AppConstants.baseUrl}.';
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          msg = 'Request timed out. Check your network and try again.';
        case DioExceptionType.badResponse:
          final status = e.response?.statusCode;
          final body   = e.response?.data;
          final detail = body is Map ? (body['error'] ?? body['message']) : null;
          msg = detail?.toString() ?? 'Server returned $status.';
        default:
          msg = e.message ?? 'An unexpected error occurred.';
      }
      setState(() {
        _isLoading    = false;
        _errorMessage = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading    = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<String?> _showTenantPicker(List<Map<String, dynamic>> tenants) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Select workspace', style: AppTextStyles.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: tenants.map((t) {
            final id   = t['tenant_id']   as String? ?? '';
            final name = t['tenant_name'] as String? ?? id;
            return ListTile(
              leading: const Icon(Icons.business_outlined, color: AppColors.primary),
              title: Text(name, style: AppTextStyles.bodyMedium),
              onTap: () => Navigator.of(ctx).pop(id),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Initiates the PKCE redirect flow for the chosen provider.
  // SsoService stores the PKCE verifier in sessionStorage and redirects
  // the browser to the provider's authorization endpoint.  Completion
  // is handled by AuthCallbackPage at /auth-callback.
  void _handleSsoLogin(String provider) {
    if (_isLoading) return;
    setState(() => _errorMessage = null);
    try {
      switch (provider) {
        case 'google':
          SsoService.startGoogleFlow();
        case 'azure':
          SsoService.startAzureFlow();
        case 'okta':
          SsoService.startOktaFlow();
      }
      // Browser will redirect â€” no further action in this widget.
    } on SsoConfigException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < AppConstants.mobileBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left panel â€” branding
        Expanded(
          flex: 5,
          child: _buildBrandPanel(),
        ),
        // Right panel â€” login form
        Expanded(
          flex: 4,
          child: _buildFormPanel(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildMobileBrandHeader(),
          _buildFormPanel(),
        ],
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Animated background
          const AnimatedGraphBackground(
            nodeCount: 30,
            opacity: 0.1,
            color: AppColors.primary,
          ),

          // Gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x15599B81),
                  Colors.transparent,
                  Color(0x15070E0B),
                ],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AzileLogo(size: 48)
                    .animate()
                    .fadeIn(duration: const Duration(milliseconds: 600)),

                const Spacer(),

                // Main headline
                Text(
                  'Unify your data.\nAmplify your intelligence.',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.primaryText,
                    height: 1.15,
                  ),
                )
                    .animate(delay: const Duration(milliseconds: 200))
                    .fadeIn(duration: const Duration(milliseconds: 600))
                    .slideY(
                        begin: 0.2,
                        end: 0,
                        duration: const Duration(milliseconds: 600)),

                const SizedBox(height: 16),
                Text(
                  'The AI-powered master data management platform that turns fragmented data into trusted golden records.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                )
                    .animate(delay: const Duration(milliseconds: 300))
                    .fadeIn(duration: const Duration(milliseconds: 600)),

                const SizedBox(height: 48),

                // Feature list
                ..._buildFeatureList(),

                const Spacer(),

                // Social proof
                _buildSocialProof(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFeatureList() {
    final features = [
      (Icons.auto_awesome, 'AI-powered entity matching with 97% accuracy'),
      (Icons.merge_type, 'Automated golden record creation and merging'),
      (Icons.verified, 'Real-time data quality scoring and alerts'),
      (Icons.hub, 'Universal connector for any data source'),
      (Icons.insights, 'Deep lineage tracking and governance'),
    ];

    return features.asMap().entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha:0.3)),
              ),
              child: Icon(entry.value.$1,
                  color: AppColors.primary, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.value.$2,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ],
        )
            .animate(
                delay: Duration(
                    milliseconds: 400 + entry.key * 80))
            .fadeIn(duration: const Duration(milliseconds: 400))
            .slideX(
                begin: -0.1,
                end: 0,
                duration: const Duration(milliseconds: 400)),
      );
    }).toList();
  }

  Widget _buildSocialProof() {
    return Row(
      children: [
        _buildStatChip('247K+', 'Entities'),
        const SizedBox(width: 16),
        _buildStatChip('98.4%', 'Uptime'),
        const SizedBox(width: 16),
        _buildStatChip('50ms', 'Avg. Match Time'),
      ],
    )
        .animate(delay: const Duration(milliseconds: 800))
        .fadeIn(duration: const Duration(milliseconds: 400));
  }

  Widget _buildStatChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.primary,
            ),
          ),
          Text(label, style: AppTextStyles.labelSmall),
        ],
      ),
    );
  }

  Widget _buildMobileBrandHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AzileLogo(size: 40),
          const SizedBox(height: 24),
          Text(
            'Unify your data.',
            style: AppTextStyles.headlineMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      color: AppColors.navyBackground,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back',
                  style: AppTextStyles.headlineMedium,
                )
                    .animate()
                    .fadeIn(duration: const Duration(milliseconds: 500)),

                const SizedBox(height: 6),
                Text(
                  'Sign in to your Azile AI MDM account',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                )
                    .animate(delay: const Duration(milliseconds: 100))
                    .fadeIn(duration: const Duration(milliseconds: 500)),

                const SizedBox(height: 36),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          hintText: 'you@company.com',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email address';
                          }
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      )
                          .animate(
                              delay: const Duration(milliseconds: 200))
                          .fadeIn(duration: const Duration(milliseconds: 400))
                          .slideY(
                              begin: 0.1,
                              end: 0,
                              duration: const Duration(milliseconds: 400)),

                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      )
                          .animate(
                              delay: const Duration(milliseconds: 280))
                          .fadeIn(duration: const Duration(milliseconds: 400))
                          .slideY(
                              begin: 0.1,
                              end: 0,
                              duration: const Duration(milliseconds: 400)),

                      const SizedBox(height: 12),

                      // Remember me + Forgot password
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Remember me',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.secondaryText,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                            ),
                            child: Text(
                              'Forgot password?',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      )
                          .animate(
                              delay: const Duration(milliseconds: 320))
                          .fadeIn(duration: const Duration(milliseconds: 400)),

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha:0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha:0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.error, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn().shakeX(hz: 3, amount: 4),
                      ],

                      const SizedBox(height: 24),

                      // Sign in button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: AppTextStyles.buttonLarge,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.navyBackground,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                      )
                          .animate(
                              delay: const Duration(milliseconds: 380))
                          .fadeIn(duration: const Duration(milliseconds: 400))
                          .slideY(
                              begin: 0.1,
                              end: 0,
                              duration: const Duration(milliseconds: 400)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or continue with',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.divider)),
                  ],
                )
                    .animate(delay: const Duration(milliseconds: 440))
                    .fadeIn(duration: const Duration(milliseconds: 400)),

                const SizedBox(height: 20),

                // SSO buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildSSOButton(
                        label:    'Google',
                        icon:     Icons.g_mobiledata_rounded,
                        provider: 'google',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSSOButton(
                        label:    'Microsoft',
                        icon:     Icons.window_rounded,
                        provider: 'azure',
                      ),
                    ),
                  ],
                )
                    .animate(delay: const Duration(milliseconds: 480))
                    .fadeIn(duration: const Duration(milliseconds: 400)),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSSOButton({
    required String label,
    required IconData icon,
    required String provider,
  }) {
    return OutlinedButton(
      onPressed: _isLoading ? null : () => _handleSsoLogin(provider),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.buttonSmall),
        ],
      ),
    );
  }
}
