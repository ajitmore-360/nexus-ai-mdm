import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/user.dart';

User _profileUserFromAuth({
  required String name,
  required String email,
  required String role,
}) {
  final userRole = role == 'super_admin'
      ? UserRole.productAdmin
      : UserRole.values.firstWhere(
          (r) => r.name == role,
          orElse: () => UserRole.viewer,
        );
  return User(
    id: '',
    email: email,
    name: name.isNotEmpty ? name : email.split('@').first,
    role: userRole,
    tenantId: '',
    tenantName: '',
    createdAt: DateTime(2024),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _user;

  // Password form
  final _pwFormKey    = GlobalKey<FormState>();
  final _curPwCtrl    = TextEditingController();
  final _newPwCtrl    = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscureCur  = true;
  bool _obscureNew  = true;
  bool _obscureConf = true;
  bool _pwSaving    = false;
  bool _pwSuccess   = false;
  String? _pwError;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _curPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final results = await Future.wait([
      AuthManager.getUserName(),
      AuthManager.getUserEmail(),
      AuthManager.getUserRole(),
    ]);
    if (!mounted) return;
    setState(() {
      _user = _profileUserFromAuth(
        name:  results[0] ?? '',
        email: results[1] ?? '',
        role:  results[2] ?? 'viewer',
      );
    });
  }

  Future<void> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() { _pwSaving = true; _pwError = null; _pwSuccess = false; });
    try {
      final api = GetIt.instance<ApiClient>();
      await api.post<Map<String, dynamic>>(
        '/auth/change-password',
        data: {
          'current_password': _curPwCtrl.text,
          'new_password':     _newPwCtrl.text,
        },
      );
      if (!mounted) return;
      _curPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmCtrl.clear();
      setState(() { _pwSaving = false; _pwSuccess = true; });
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg  = body is Map
          ? (body['error'] ?? body['message'])?.toString()
          : null;
      setState(() {
        _pwSaving = false;
        _pwError  = msg ?? 'Failed to update password. Check your current password.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pwSaving = false;
        _pwError  = 'An unexpected error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarCard(),
            const SizedBox(height: 24),
            _buildPasswordCard(),
          ],
        ),
      ),
    );
  }

  // ── Avatar / display name card ─────────────────────────────────────────────

  Widget _buildAvatarCard() {
    final initials = _user == null
        ? '?'
        : (_user!.name.isNotEmpty
            ? _user!.name
                .split(' ')
                .where((p) => p.isNotEmpty)
                .take(2)
                .map((p) => p[0].toUpperCase())
                .join()
            : _user!.email[0].toUpperCase());

    final roleLabel = _user == null ? '' : _roleDisplayName(_user!.role);

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar circle
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: (_user?.avatarUrl != null && _user!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(_user!.avatarUrl!)
                    : null,
                child: (_user?.avatarUrl == null || _user!.avatarUrl!.isEmpty)
                    ? Text(
                        initials,
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              Tooltip(
                message: 'Profile picture upload coming soon',
                child: InkWell(
                  onTap: () => _showComingSoon(context, 'Profile picture upload'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.cardSurface, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.camera_alt_outlined,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 20),

          // Name + role + email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user?.name ?? '',
                  style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        roleLabel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _user?.email ?? '',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Password card ──────────────────────────────────────────────────────────

  Widget _buildPasswordCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Change Password', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('Update your login password',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 20),

          if (_pwSuccess)
            _banner(
              icon: Icons.check_circle_outline,
              message: 'Password updated successfully.',
              color: AppColors.success,
            ),
          if (_pwError != null)
            _banner(
              icon: Icons.error_outline,
              message: _pwError!,
              color: AppColors.error,
            ),

          Form(
            key: _pwFormKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 600;
                final fields = [
                  _pwField(
                    label: 'CURRENT PASSWORD',
                    controller: _curPwCtrl,
                    obscure: _obscureCur,
                    onToggle: () => setState(() => _obscureCur = !_obscureCur),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  _pwField(
                    label: 'NEW PASSWORD',
                    controller: _newPwCtrl,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    validator: (v) =>
                        (v == null || v.length < 8) ? 'At least 8 characters' : null,
                  ),
                  _pwField(
                    label: 'CONFIRM NEW PASSWORD',
                    controller: _confirmCtrl,
                    obscure: _obscureConf,
                    onToggle: () => setState(() => _obscureConf = !_obscureConf),
                    validator: (v) =>
                        v != _newPwCtrl.text ? 'Passwords do not match' : null,
                  ),
                ];

                return narrow
                    ? Column(
                        children: fields
                            .map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: f))
                            .toList(),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: fields
                            .expand((f) => [Expanded(child: f), const SizedBox(width: 16)])
                            .toList()
                          ..removeLast(),
                      );
              },
            ),
          ),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pwSaving ? null : _changePassword,
            icon: _pwSaving
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_rounded, size: 16),
            label: Text(
              _pwSaving ? 'Saving...' : 'Update Password',
              style: AppTextStyles.buttonSmall.copyWith(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }

  Widget _banner({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: AppTextStyles.bodySmall.copyWith(color: color)),
          ),
        ],
      ),
    );
  }

  Widget _pwField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11, color: AppColors.mutedText, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: AppTextStyles.inputText,
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: AppTextStyles.inputHint,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.error, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 16,
                color: AppColors.mutedText,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _roleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.productAdmin:  return 'Platform Admin';
      case UserRole.admin:         return 'Admin';
      case UserRole.businessAdmin: return 'Business Admin';
      case UserRole.steward:       return 'Data Steward';
      case UserRole.analyst:       return 'Analyst';
      case UserRole.viewer:        return 'Viewer';
    }
  }
}
