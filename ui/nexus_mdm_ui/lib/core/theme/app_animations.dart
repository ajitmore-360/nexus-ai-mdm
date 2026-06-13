import 'package:flutter/material.dart';

/// Centralised animation constants — every transition in the app draws from here
/// so motion feels coherent across pages and components.
class AppAnimations {
  AppAnimations._();

  // ── Durations ─────────────────────────────────────────────────────────────
  static const Duration micro  = Duration(milliseconds:  80);
  static const Duration fast   = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow   = Duration(milliseconds: 400);
  static const Duration reveal = Duration(milliseconds: 550);

  // ── Curves ────────────────────────────────────────────────────────────────

  /// Used for most enter transitions — overshoots slightly then settles.
  static const Curve spring = Cubic(0.175, 0.885, 0.32, 1.275);

  /// Smooth deceleration — good for card slides and drawer open.
  static const Curve easeOutQuint = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Sharp enter — command palette, modals.
  static const Curve snappyEnter = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Quick dismiss — feels responsive to close.
  static const Curve quickExit = Cubic(0.4, 0.0, 1.0, 1.0);

  // ── Scale presets ─────────────────────────────────────────────────────────

  /// Hover scale — gives stat cards and buttons a subtle lift.
  static const double hoverScale = 1.025;

  /// Press scale — tactile "clicked" confirmation.
  static const double pressScale = 0.97;

  // ── Stagger helpers ───────────────────────────────────────────────────────

  /// Returns a delay suitable for a staggered list item at [index].
  /// Caps at 600 ms so long lists still animate quickly.
  static Duration stagger(int index, {int baseMs = 40}) =>
      Duration(milliseconds: (index * baseMs).clamp(0, 600));
}
