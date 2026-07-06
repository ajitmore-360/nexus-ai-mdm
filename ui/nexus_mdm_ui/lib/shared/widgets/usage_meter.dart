import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Horizontal usage-meter row.
///
/// ```dart
/// UsageMeter(
///   label: 'Golden Records',
///   current: 4200,
///   limit: 5000,
/// )
/// ```
///
/// Set [limit] to `-1` to indicate unlimited — the bar renders full green and
/// the right-hand label shows "Unlimited".
class UsageMeter extends StatelessWidget {
  const UsageMeter({
    super.key,
    required this.label,
    required this.current,
    required this.limit,
    this.color,
  });

  final String label;
  final int current;

  /// `-1` means unlimited.
  final int limit;

  /// Override the computed semantic color.
  final Color? color;

  // ── Computed values ────────────────────────────────────────────────────────

  bool get _unlimited => limit == -1;

  double get _fraction {
    if (_unlimited || limit == 0) return 1.0;
    return (current / limit).clamp(0.0, 1.0);
  }

  Color get _barColor {
    if (color != null) return color!;
    if (_unlimited) return AppColors.success;
    final pct = _fraction;
    if (pct > 0.9) return AppColors.error;
    if (pct > 0.7) return AppColors.warning;
    return AppColors.success;
  }

  String get _rightLabel {
    if (_unlimited) return 'Unlimited';
    return '${_fmt(current)} / ${_fmt(limit)}';
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return '$n';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),

          // Progress bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: Stack(
                children: [
                  // Track
                  Container(
                    height: 6,
                    color: AppColors.divider.withValues(alpha: 0.25),
                  ),
                  // Fill
                  FractionallySizedBox(
                    widthFactor: _fraction,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _barColor,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Right label
          SizedBox(
            width: 88,
            child: Text(
              _rightLabel,
              style: AppTextStyles.labelSmall.copyWith(
                color: _unlimited ? AppColors.success : _barColor,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
