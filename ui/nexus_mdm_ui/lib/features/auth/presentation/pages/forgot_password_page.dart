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

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool    _loading = false;
  bool    _sent    = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final apiClient = GetIt.instance<ApiClient>();
      await apiClient.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        data: {'email': _emailCtrl.text.trim().toLowerCase()},
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent    = true;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg  = body is Map
          ? (body['error'] ?? body['message'])?.toString()
          : null;
      setState(() {
        _loading = false;
        _error   = msg ?? 'Something went wrong. Please try again.';
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
                colors: [Color(0x1500C896), Colors.transparent, Color(0x150A1628)],
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
                  'Forgot your\npassword?',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.primaryText, height: 1.15,
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.2, end: 0, duration: 600.ms),
                const SizedBox(height: 16),
                Text(
                  'Enter the email address linked to your account and we\'ll send you a reset link.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ).animate(delay: 300.ms).fadeIn(duration: 600.ms),
                const SizedBox(height: 40),
                _buildFeature(Icons.lock_reset_outlined,  'One-time reset link'),
                _buildFeature(Icons.timer_outlined,        'Expires in 1 hour'),
                _buildFeature(Icons.shield_outlined,       'Secure by default'),
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
          Text('Forgot password',
              style: AppTextStyles.titleMedium,
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
          child: _sent ? _buildSentState() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reset your password', style: AppTextStyles.titleLarge)
            .animate()
            .fadeIn(duration: 400.ms),
        const SizedBox(height: 8),
        Text(
          'We\'ll email you a secure link to choose a new password.',
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
              _label('EMAIL ADDRESS'),
              const SizedBox(height: 6),
              TextFormField(
                controller:   _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect:  false,
                style:        AppTextStyles.inputText,
                validator:    (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@'))               return 'Enter a valid email';
                  return null;
                },
                decoration: InputDecoration(
                  hintText:       'you@example.com',
                  hintStyle:      AppTextStyles.inputHint,
                  filled:         true,
                  fillColor:      AppColors.inputFill,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: AppColors.error, width: 1.5),
                  ),
                ),
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
                      : Text('Send reset link',
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

  Widget _buildSentState() {
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
          child: const Icon(Icons.mark_email_read_outlined,
              color: AppColors.success, size: 40),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text('Check your inbox',
            style:     AppTextStyles.titleLarge,
            textAlign: TextAlign.center)
            .animate(delay: 200.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 12),
        Text(
          'If an account exists for ${_emailCtrl.text.trim()}, '
          'a reset link is on its way. Check your spam folder if it '
          'doesn\'t arrive within a few minutes.',
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
            child: Text('Back to sign in',
                style: AppTextStyles.buttonMedium
                    .copyWith(color: Colors.white)),
          ),
        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() {
            _sent  = false;
            _error = null;
            _emailCtrl.clear();
          }),
          child: Text('Try a different email',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.mutedText)),
        ).animate(delay: 500.ms).fadeIn(duration: 400.ms),
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
}
