import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/entity.dart';

class StatusBadge extends StatelessWidget {
  final EntityStatus status;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  factory StatusBadge.fromString(String statusStr, {bool compact = false}) {
    final status = EntityStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == statusStr.toLowerCase() ||
          s.name == statusStr,
      orElse: () => EntityStatus.active,
    );
    return StatusBadge(status: status, compact: compact);
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    if (compact) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: config.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: config.color.withValues(alpha:0.4),
              blurRadius: 4,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.color.withValues(alpha:0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: config.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            config.label,
            style: AppTextStyles.badgeLabel.copyWith(
              color: config.color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  _BadgeConfig _getConfig() {
    switch (status) {
      case EntityStatus.active:
        return _BadgeConfig(
          label: 'ACTIVE',
          color: AppColors.statusActive,
          backgroundColor: AppColors.statusActive.withValues(alpha:0.1),
        );
      case EntityStatus.golden:
        return _BadgeConfig(
          label: 'GOLDEN',
          color: AppColors.statusGolden,
          backgroundColor: AppColors.statusGolden.withValues(alpha:0.1),
        );
      case EntityStatus.review:
        return _BadgeConfig(
          label: 'REVIEW',
          color: AppColors.statusReview,
          backgroundColor: AppColors.statusReview.withValues(alpha:0.1),
        );
      case EntityStatus.merged:
        return _BadgeConfig(
          label: 'MERGED',
          color: AppColors.statusMerged,
          backgroundColor: AppColors.statusMerged.withValues(alpha:0.1),
        );
      case EntityStatus.inactive:
        return _BadgeConfig(
          label: 'INACTIVE',
          color: AppColors.statusInactive,
          backgroundColor: AppColors.statusInactive.withValues(alpha:0.1),
        );
      case EntityStatus.pending:
        return _BadgeConfig(
          label: 'PENDING',
          color: AppColors.warning,
          backgroundColor: AppColors.warning.withValues(alpha:0.1),
        );
    }
  }
}

class _BadgeConfig {
  final String label;
  final Color color;
  final Color backgroundColor;

  const _BadgeConfig({
    required this.label,
    required this.color,
    required this.backgroundColor,
  });
}

// Priority Badge variant
class PriorityBadge extends StatelessWidget {
  final String priority;

  const PriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority.toLowerCase()) {
      case 'critical':
        color = AppColors.error;
        break;
      case 'high':
        color = AppColors.warning;
        break;
      case 'normal':
        color = AppColors.primary;
        break;
      default:
        color = AppColors.secondaryText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha:0.4)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: AppTextStyles.badgeLabel.copyWith(color: color),
      ),
    );
  }
}
