import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/entity.dart';

class EntityAvatar extends StatelessWidget {
  final EntityType type;
  final double size;
  final bool showGoldenRing;
  final Color? backgroundColor;

  const EntityAvatar({
    super.key,
    required this.type,
    this.size = 40,
    this.showGoldenRing = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();
    final bgColor = backgroundColor ?? config.backgroundColor;

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: showGoldenRing
            ? Border.all(
                color: AppColors.statusGolden,
                width: 2,
              )
            : Border.all(
                color: config.borderColor.withValues(alpha:0.4),
                width: 1,
              ),
        boxShadow: showGoldenRing
            ? [
                BoxShadow(
                  color: AppColors.statusGolden.withValues(alpha:0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        config.icon,
        color: config.iconColor,
        size: size * 0.5,
      ),
    );

    if (showGoldenRing) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: size * 0.35,
              height: size * 0.35,
              decoration: const BoxDecoration(
                color: AppColors.statusGolden,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.star,
                color: AppColors.navyBackground,
                size: size * 0.2,
              ),
            ),
          ),
        ],
      );
    }

    return avatar;
  }

  _AvatarConfig _getConfig() {
    switch (type) {
      case EntityType.person:
        return _AvatarConfig(
          icon: Icons.person_outline,
          iconColor: AppColors.primary,
          backgroundColor: AppColors.primary.withValues(alpha:0.12),
          borderColor: AppColors.primary,
        );
      case EntityType.organization:
        return _AvatarConfig(
          icon: Icons.business_outlined,
          iconColor: AppColors.info,
          backgroundColor: AppColors.info.withValues(alpha:0.12),
          borderColor: AppColors.info,
        );
      case EntityType.product:
        return _AvatarConfig(
          icon: Icons.inventory_2_outlined,
          iconColor: AppColors.aiPurple,
          backgroundColor: AppColors.aiPurple.withValues(alpha:0.12),
          borderColor: AppColors.aiPurple,
        );
      case EntityType.location:
        return _AvatarConfig(
          icon: Icons.location_on_outlined,
          iconColor: AppColors.warning,
          backgroundColor: AppColors.warning.withValues(alpha:0.12),
          borderColor: AppColors.warning,
        );
      case EntityType.asset:
        return _AvatarConfig(
          icon: Icons.account_tree_outlined,
          iconColor: AppColors.mintAccent,
          backgroundColor: AppColors.mintAccent.withValues(alpha:0.1),
          borderColor: AppColors.mintAccent,
        );
    }
  }
}

class _AvatarConfig {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;

  const _AvatarConfig({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
  });
}

// Activity type avatar
class ActivityAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const ActivityAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
