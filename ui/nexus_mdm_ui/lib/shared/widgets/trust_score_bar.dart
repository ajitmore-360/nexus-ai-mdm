import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class TrustScoreBar extends StatefulWidget {
  final double score;
  final double? width;
  final double height;
  final bool showLabel;
  final bool showPercentage;
  final bool animate;

  const TrustScoreBar({
    super.key,
    required this.score,
    this.width,
    this.height = 8,
    this.showLabel = false,
    this.showPercentage = true,
    this.animate = true,
  });

  @override
  State<TrustScoreBar> createState() => _TrustScoreBarState();
}

class _TrustScoreBarState extends State<TrustScoreBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: 0, end: widget.score).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(TrustScoreBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.score,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double trustScoreHigh = 0.85;
  static const double trustScoreMedium = 0.65;

  Color _getColor(double score) {
    if (score >= trustScoreHigh) return AppColors.primary;
    if (score >= trustScoreMedium) return AppColors.warning;
    return AppColors.error;
  }

  String _getLabel(double score) {
    if (score >= trustScoreHigh) return 'High';
    if (score >= trustScoreMedium) return 'Medium';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value;
        final color = _getColor(value);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showLabel)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Trust Score',
                      style: AppTextStyles.labelSmall,
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getLabel(value),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: Stack(
                      children: [
                        // Track
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius:
                                BorderRadius.circular(widget.height / 2),
                          ),
                        ),
                        // Fill
                        FractionallySizedBox(
                          widthFactor: value.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  color.withValues(alpha:0.7),
                                  color,
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(widget.height / 2),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha:0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.showPercentage) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${(value * 100).round()}%',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
