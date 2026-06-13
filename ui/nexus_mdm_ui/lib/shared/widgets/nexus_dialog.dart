import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_animations.dart';

// ──────────────────────────────────────────────────────────────────────────────
// showNexusDialog — drop-in replacement for showDialog / AlertDialog
// ──────────────────────────────────────────────────────────────────────────────

Future<T?> showNexusDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'NexusDialog',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: AppAnimations.normal,
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppAnimations.snappyEnter,
        reverseCurve: AppAnimations.quickExit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// NexusDialog — the glass card itself
// ──────────────────────────────────────────────────────────────────────────────

class NexusDialog extends StatelessWidget {
  final String title;
  final Widget? titleIcon;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;

  const NexusDialog({
    super.key,
    required this.title,
    this.titleIcon,
    required this.content,
    this.actions,
    this.maxWidth = 440,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.glassSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: AppColors.glowShadow(),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
                      child: Row(
                        children: [
                          if (titleIcon != null) ...[
                            titleIcon!,
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(title, style: AppTextStyles.titleMedium),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: AppColors.secondaryText),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.divider, height: 1),
                    // ── Content ───────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: content,
                    ),
                    // ── Actions ───────────────────────────────────────────
                    if (actions != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.divider)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions!
                              .map((a) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: a,
                                  ))
                              .toList(),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
