import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

// ──────────────────────────────────────────────────────────────────────────────
// StatCard — KPI card with hover-lift spring animation
// ──────────────────────────────────────────────────────────────────────────────

class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Gradient gradient;
  final double? trendValue;
  final bool? trendPositive;
  final VoidCallback? onTap;
  final bool isLoading;
  final int animationDelay;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.gradient,
    this.trendValue,
    this.trendPositive,
    this.onTap,
    this.isLoading = false,
    this.animationDelay = 0,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _elevAnim;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
      reverseDuration: AppAnimations.normal,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: AppAnimations.hoverScale)
        .animate(CurvedAnimation(
      parent: _hoverCtrl,
      curve: AppAnimations.spring,
      reverseCurve: AppAnimations.easeOutQuint,
    ));
    _elevAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hoverCtrl.forward(),
      onExit: (_) => _hoverCtrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _hoverCtrl,
          builder: (_, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Color.lerp(
                    AppColors.divider,
                    AppColors.primary.withValues(alpha: 0.35),
                    _elevAnim.value,
                  )!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: 0.18 + 0.14 * _elevAnim.value),
                    blurRadius: 8 + 16 * _elevAnim.value,
                    offset: Offset(0, 2 + 6 * _elevAnim.value),
                  ),
                  if (_elevAnim.value > 0.1)
                    BoxShadow(
                      color: AppColors.primary
                          .withValues(alpha: 0.06 * _elevAnim.value),
                      blurRadius: 40,
                      spreadRadius: -8,
                    ),
                ],
              ),
              child: child,
            ),
          ),
          child: Stack(
            children: [
              // Left gradient accent bar
              Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: widget.gradient,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: widget.isLoading
                    ? _buildShimmer()
                    : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: widget.animationDelay))
        .fadeIn(duration: AppAnimations.slow)
        .slideY(
            begin: 0.08,
            end: 0,
            duration: AppAnimations.slow,
            curve: AppAnimations.easeOutQuint);
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon,
                  color: AppColors.navyBackground, size: 20),
            ),
            const Spacer(),
            if (widget.trendValue != null) _buildTrend(),
          ],
        ),
        const SizedBox(height: 16),
        Text(widget.value, style: AppTextStyles.statValue),
        const SizedBox(height: 4),
        Text(widget.title, style: AppTextStyles.statLabel),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.mutedText),
          ),
        ],
      ],
    );
  }

  Widget _buildTrend() {
    final isPositive =
        widget.trendPositive ?? (widget.trendValue! >= 0);
    final color = isPositive ? AppColors.primary : AppColors.error;
    final arrowIcon =
        isPositive ? Icons.trending_up : Icons.trending_down;
    final sign = widget.trendValue! >= 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(arrowIcon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            '$sign${widget.trendValue!.toStringAsFixed(1)}%',
            style: AppTextStyles.badgeLabel.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _ShimmerBox(width: 40, height: 40, radius: 10),
            Spacer(),
            _ShimmerBox(width: 70, height: 24, radius: 12),
          ],
        ),
        SizedBox(height: 16),
        _ShimmerBox(width: 100, height: 36, radius: 4),
        SizedBox(height: 6),
        _ShimmerBox(width: 120, height: 16, radius: 4),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shimmer placeholder
// ──────────────────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: const [
              AppColors.elevatedCard,
              AppColors.divider,
              AppColors.elevatedCard,
            ],
          ),
        ),
      ),
    );
  }
}
