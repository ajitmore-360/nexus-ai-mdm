import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Reusable gate widget shown when the user attempts to access a feature that
/// requires a higher license tier.
///
/// Usage — wrap a feature widget:
/// ```dart
/// UpgradePrompt.wrap(
///   child: AdvancedAnalyticsWidget(),
///   hasAccess: licenseManager.hasModule(LicensedModule.analytics),
///   featureName: 'Advanced Analytics',
///   requiredTier: 'Enterprise',
/// )
/// ```
class UpgradePrompt extends StatelessWidget {
  const UpgradePrompt({
    super.key,
    required this.featureName,
    required this.requiredTier,
    this.description,
    this.onUpgrade,
    this.onLearnMore,
  });

  final String featureName;

  /// 'Professional' or 'Enterprise'
  final String requiredTier;

  final String? description;

  /// Called when the user taps "Upgrade to {tier}". If null the button is still
  /// shown but performs a no-op (so callers can wire it up later).
  final VoidCallback? onUpgrade;

  /// Called when the user taps "Learn More". Optional.
  final VoidCallback? onLearnMore;

  // ── Static helper ──────────────────────────────────────────────────────────

  /// Returns [child] unchanged when [hasAccess] is true, otherwise returns an
  /// [UpgradePrompt] that blocks access.
  static Widget wrap({
    required Widget child,
    required bool hasAccess,
    required String featureName,
    required String requiredTier,
    String? description,
    VoidCallback? onUpgrade,
    VoidCallback? onLearnMore,
  }) {
    if (hasAccess) return child;
    return UpgradePrompt(
      featureName: featureName,
      requiredTier: requiredTier,
      description: description,
      onUpgrade: onUpgrade,
      onLearnMore: onLearnMore,
    );
  }

  // ── Tier helpers ───────────────────────────────────────────────────────────

  Color get _tierColor {
    switch (requiredTier) {
      case 'Enterprise':
        return AppColors.warning;
      case 'Professional':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  Color get _tierBgColor => _tierColor.withValues(alpha: 0.12);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: _GradientBorderCard(
        borderColor: _tierColor.withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _tierColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded,
                    color: _tierColor, size: 22),
              ),
              const SizedBox(height: 12),

              // Headline
              Text(
                'Feature not available',
                style: AppTextStyles.titleSmall
                    .copyWith(color: AppColors.primaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // Sub-line
              Text(
                '$featureName requires $requiredTier or higher.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),

              // Optional description
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.mutedText, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 14),

              // Tier badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _tierBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _tierColor.withValues(alpha: 0.35), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_outlined,
                        size: 12, color: _tierColor),
                    const SizedBox(width: 5),
                    Text(
                      requiredTier,
                      style: AppTextStyles.badgeLabel
                          .copyWith(color: _tierColor, fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Learn More — outline
                  OutlinedButton(
                    onPressed: onLearnMore,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: const BorderSide(
                          color: AppColors.divider, width: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Learn More',
                        style: AppTextStyles.buttonSmall
                            .copyWith(color: AppColors.secondaryText)),
                  ),
                  const SizedBox(width: 10),

                  // Upgrade — filled
                  ElevatedButton.icon(
                    onPressed: onUpgrade,
                    icon: const Icon(Icons.arrow_upward_rounded,
                        size: 14, color: Colors.black87),
                    label: Text(
                      'Upgrade to $requiredTier',
                      style: AppTextStyles.buttonSmall
                          .copyWith(color: Colors.black87),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tierColor,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Internal gradient-border card ─────────────────────────────────────────────

class _GradientBorderCard extends StatelessWidget {
  const _GradientBorderCard({
    required this.child,
    required this.borderColor,
  });

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      child: child,
    );
  }
}
