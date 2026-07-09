import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/widgets/azile_logo.dart';

class ResetPasswordPage extends StatefulWidget {
  final String token;
  const ResetPasswordPage({super.key, required this.token});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey     = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool    _obscurePassword = true;
  bool    _obscureConfirm  = true;
  bool    _loading         = false;
  bool    _done            = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.token.isEmpty) {
      _error = 'Invalid reset link â€” token is missing.';
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.token.isEmpty) {
      setState(() => _error = 'Invalid reset link â€” token is missing.');
      return;
    }

    setState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final apiClient = GetIt.instance<ApiClient>();
      await apiClient.post<Map<String, dynamic>>(
        '/auth/reset-password',
        data: {
          'token':        widget.token,
          'new_password': _passwordCtrl.text,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _done    = true;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg  = body is Map
          ? (body['error'] ?? body['message'])?.toString()
          : null;
      setState(() {
        _loading = false;
        _error   = msg ?? 'Reset failed (${e.response?.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: isMobile
          ? SingleChildScrollView(
              child: Column(children: [
                _buildMobileHeader(),
                _buildFormPanel(),
              ]),
            )
          : Row(children: [
              Expanded(flex: 5, child: _buildBrandPanel()),
              Expanded(flex: 4, child: _buildFormPanel()),
            ]),
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
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x15599B81), Colors.transparent, Color(0x15070E0B)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AzileLogo(size: 48)
                    .animate()
                    .fadeIn(duration: 600.ms),
                const Spacer(),
                Text(
                  'Choose a new\npassword.',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.primaryText, height: 1.15,
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.2, end: 0, duration: 600.ms),
                const SizedBox(height: 16),
                Text(
                  'Pick something strong. This link is single-use and expires in 1 hour.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ).animate(delay: 300.ms).fadeIn(duration: 600.ms),
                const SizedBox(height: 40),
                _buildFeature(Icons.key_outlined,      'At least 8 characters'),
                _buildFeature(Icons.timer_outlined,     'Link expires in 1 hour'),
                _buildFeature(Icons.shield_outlined,    'Single-use token'),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Text(text,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          const AzileLogo(size: 36),
          const SizedBox(height: 16),
          Text('Choose a new password',
              style:     AppTextStyles.titleMedium,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _done ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set a new password', style: AppTextStyles.titleLarge)
            .animate()
            .fadeIn(duration: 400.ms),
        const SizedBox(height: 8),
        Text(
          'Your new password must be at least 8 characters.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.secondaryText),
        ).animate(delay: 80.ms).fadeIn(duration: 400.ms),

        const SizedBox(height: 32),

        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('NEW PASSWORD'),
              const SizedBox(height: 6),
              _passwordField(
                controller: _passwordCtrl,
                hint:       'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
                obscure:    _obscurePassword,
                toggle:     () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator:  (v) {
                  if (v == null || v.length < 8) {
                    return 'At least 8 characters required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _label('CONFIRM PASSWORD'),
              const SizedBox(height: 6),
              _passwordField(
                controller: _confirmCtrl,
                hint:       'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
                obscure:    _obscureConfirm,
                toggle:     () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator:  (v) {
                  if (v != _passwordCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width:  20,
                          height: 20,
                          child:  CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text('Set new password',
                          style: AppTextStyles.buttonMedium
                              .copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text('Back to sign in',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.primary)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width:  72,
          height: 72,
          decoration: BoxDecoration(
            color:  AppColors.success.withValues(alpha: 0.12),
            shape:  BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 40),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text('Password updated!',
            style:     AppTextStyles.titleLarge,
            textAlign: TextAlign.center)
            .animate(delay: 200.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 12),
        Text(
          'Your password has been changed. Sign in with your new password.',
          style:     AppTextStyles.bodyMedium
              .copyWith(color: AppColors.secondaryText),
          textAlign: TextAlign.center,
        ).animate(delay: 300.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Sign In',
                style: AppTextStyles.buttonMedium
                    .copyWith(color: Colors.white)),
          ),
        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        fontSize:      11,
        color:         AppColors.mutedText,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String                hint,
    required bool                  obscure,
    required VoidCallback           toggle,
    String? Function(String?)?     validator,
  }) {
    return TextFormField(
      controller:  controller,
      obscureText: obscure,
      validator:   validator,
      style:       AppTextStyles.inputText,
      decoration: InputDecoration(
        hintText:       hint,
        hintStyle:      AppTextStyles.inputHint,
        filled:         true,
        fillColor:      AppColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(
              color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(
              color: AppColors.error, width: 1.5),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size:  18,
            color: AppColors.mutedText,
          ),
          onPressed: toggle,
        ),
      ),
    );
  }
}
