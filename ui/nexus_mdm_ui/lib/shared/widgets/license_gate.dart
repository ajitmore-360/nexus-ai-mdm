import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/license/license_manager.dart';
import '../../core/license/licensed_module.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/user.dart';

/// Shown when a module requires a license the current tenant doesn't have.
class LicenseGate extends StatelessWidget {
  final LicensedModule module;
  const LicenseGate({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppColors.glowShadow(
                  color: AppColors.primary, intensity: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.auroraGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(module.icon, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 24),
                Text(module.displayName,
                    style: AppTextStyles.titleLarge.copyWith(fontSize: 22)),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText),
                    children: [
                      const TextSpan(
                          text: 'This module is included in the\n'),
                      TextSpan(
                        text: '${module.tier} plan',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(
                          text:
                              '.\nContact your Product Admin to activate it.'),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.workspace_premium_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${module.tier} · Upgrade required',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primary),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.go('/dashboard/admin/license'),
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('Manage License'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/dashboard'),
                  child: Text('Back to Dashboard',
                      style: AppTextStyles.buttonSmall
                          .copyWith(color: AppColors.secondaryText)),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: AppAnimations.slow)
              .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1, 1),
                  curve: AppAnimations.spring),
        ),
      ),
    );
  }
}

/// Wraps a page: shows [child] when the module is licensed (or the current
/// user is a Product Admin), otherwise shows [LicenseGate].
/// Role and license are resolved internally — no props needed beyond [module].
class LicenseGuard extends StatefulWidget {
  final LicensedModule module;
  final Widget child;

  const LicenseGuard({
    super.key,
    required this.module,
    required this.child,
  });

  @override
  State<LicenseGuard> createState() => _LicenseGuardState();
}

class _LicenseGuardState extends State<LicenseGuard> {
  bool? _licensed; // null = loading

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Product Admins bypass all license checks.
    final role = await AuthManager.getUserRole();
    if (role == UserRole.productAdmin.name) {
      if (mounted) setState(() => _licensed = true);
      return;
    }
    final ok = LicenseManager.hasModule(widget.module);
    if (mounted) setState(() => _licensed = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_licensed == null) {
      return const Scaffold(
        backgroundColor: AppColors.navyBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _licensed! ? widget.child : LicenseGate(module: widget.module);
  }
}
