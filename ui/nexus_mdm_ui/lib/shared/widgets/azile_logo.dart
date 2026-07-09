import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

// ── AzileLogo ────────────────────────────────────────────────────────────────
//
// Renders the Azile geometric A mark (two legs from an apex node, crossbar
// with a data-pulse peak) optionally followed by the product wordmark.
//
// Parameters
//   size       — bounding box of the mark square (default 40)
//   showText   — whether to render the wordmark to the right of the mark
//   animateIn  — run the stroke draw-in animation on first mount
//   shouldPulse — after draw-in completes, gently pulse the apex node
//   primaryColor / textColor — override the default AppColors
//
// Used in: sidebar header, login page, splash page (mark-only variant).
// ─────────────────────────────────────────────────────────────────────────────

class AzileLogo extends StatefulWidget {
  final double size;
  final bool showText;
  final bool shouldPulse;
  final bool animateIn;
  final Color? primaryColor;
  final Color? textColor;

  const AzileLogo({
    super.key,
    this.size = 40,
    this.showText = true,
    this.shouldPulse = false,
    this.animateIn = false,
    this.primaryColor,
    this.textColor,
  });

  @override
  State<AzileLogo> createState() => _AzileLogoState();
}

class _AzileLogoState extends State<AzileLogo>
    with TickerProviderStateMixin {
  late AnimationController _drawController;
  late AnimationController _pulseController;
  late Animation<double> _drawAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _drawAnimation = CurvedAnimation(
      parent: _drawController,
      curve: Curves.easeOut,
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.animateIn) {
      _drawController.forward().then((_) {
        if (widget.shouldPulse && mounted) {
          _pulseController.repeat(reverse: true);
        }
      });
    } else {
      _drawController.value = 1.0;
      if (widget.shouldPulse) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _drawController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color     = widget.primaryColor ?? AppColors.primary;
    final textColor = widget.textColor    ?? AppColors.primaryText;
    final s         = widget.size;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_drawAnimation, _pulseAnimation]),
          builder: (context, child) => SizedBox(
            width: s,
            height: s,
            child: CustomPaint(
              painter: _AzileMarkPainter(
                color:        color,
                drawProgress: _drawAnimation.value,
                pulseProgress: _pulseAnimation.value,
              ),
            ),
          ),
        ),
        if (widget.showText) ...[
          SizedBox(width: s * 0.22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    // "A" in brand sage, slightly heavier than the rest
                    TextSpan(
                      text: 'A',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: color,
                        letterSpacing: s * 0.058,
                        fontSize: s * 0.40,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                    // "ZILE" in off-white, light weight
                    TextSpan(
                      text: 'ZILE',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: textColor,
                        letterSpacing: s * 0.058,
                        fontSize: s * 0.40,
                        fontWeight: FontWeight.w300,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'AI · MDM',
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  letterSpacing: s * 0.040,
                  fontSize: s * 0.22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Mark painter ─────────────────────────────────────────────────────────────
//
// Geometric A: two strokes from an apex node, plus a crossbar with a single
// data-pulse peak. Draws in using PathMetric.extractPath when drawProgress < 1.
//
// Geometry (normalized to size × size canvas):
//   Apex:       (0.50, 0.11)
//   Left foot:  (0.14, 0.91)
//   Right foot: (0.86, 0.91)
//   Crossbar at 56% of leg height — endpoints intersect the legs exactly.
//   Pulse peak: (0.50, 0.47) — one clean spike above the crossbar baseline.
// ─────────────────────────────────────────────────────────────────────────────

class _AzileMarkPainter extends CustomPainter {
  final Color color;
  final double drawProgress;   // 0.0 → 1.0
  final double pulseProgress;  // 0.0 → 1.0 (apex glow oscillation)

  const _AzileMarkPainter({
    required this.color,
    required this.drawProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (drawProgress <= 0) return;

    final cx         = size.width * 0.50;
    final apexY      = size.height * 0.11;
    final legFootY   = size.height * 0.91;
    final leftFootX  = size.width  * 0.14;
    final rightFootX = size.width  * 0.86;

    // Crossbar: sits at 56% of leg span from apex
    const legFrac    = 0.56;
    final crossY     = apexY + (legFootY - apexY) * legFrac;
    final crossLeftX = cx + (leftFootX  - cx) * legFrac;    // ≈ 0.30 w
    final crossRightX= cx + (rightFootX - cx) * legFrac;    // ≈ 0.70 w
    final crossSpan  = crossRightX - crossLeftX;
    final midLeft    = crossLeftX  + crossSpan * 0.31;
    final midRight   = crossRightX - crossSpan * 0.31;
    final peakY      = crossY - size.height * 0.09;          // ≈ 0.47 h

    // Draw schedule: legs draw first (0.0→0.60), crossbar overlaps (0.45→1.0)
    final legProg   = (drawProgress / 0.60).clamp(0.0, 1.0);
    final crossProg = ((drawProgress - 0.45) / 0.55).clamp(0.0, 1.0);

    // Leg gradient: bright at apex, fades dark at feet
    final legPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.92),
          color.withValues(alpha: 0.28),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = size.width * 0.055
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke;

    // Both legs draw simultaneously from apex downward
    _drawPartial(
      canvas,
      Path()..moveTo(cx, apexY)..lineTo(leftFootX, legFootY),
      legPaint,
      legProg,
    );
    _drawPartial(
      canvas,
      Path()..moveTo(cx, apexY)..lineTo(rightFootX, legFootY),
      legPaint,
      legProg,
    );

    // Crossbar with data-pulse peak — draws left → right
    _drawPartial(
      canvas,
      Path()
        ..moveTo(crossLeftX, crossY)
        ..lineTo(midLeft, crossY)
        ..lineTo(cx, peakY)
        ..lineTo(midRight, crossY)
        ..lineTo(crossRightX, crossY),
      Paint()
        ..color       = color.withValues(alpha: 0.65)
        ..strokeWidth = size.width * 0.028
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round
        ..style       = PaintingStyle.stroke,
      crossProg,
    );

    // Apex node — appears immediately as legs begin, then gently pulses
    if (drawProgress > 0.01) {
      final apexRadius = size.width * 0.075;
      final nodeScale  = (drawProgress / 0.08).clamp(0.0, 1.0);
      final haloAlpha  = 0.18 + pulseProgress * 0.09;
      final haloRadius = apexRadius * (2.0 + pulseProgress * 0.5) * nodeScale;

      canvas.drawCircle(
        Offset(cx, apexY),
        haloRadius,
        Paint()
          ..color = color.withValues(alpha: haloAlpha)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(cx, apexY),
        apexRadius * nodeScale,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawPartial(Canvas canvas, Path path, Paint paint, double fraction) {
    if (fraction <= 0) return;
    if (fraction >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * fraction),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AzileMarkPainter old) =>
      old.color != color ||
      old.drawProgress != drawProgress ||
      old.pulseProgress != pulseProgress;
}

// ── AnimatedGraphBackground ──────────────────────────────────────────────────
//
// Floating node network used as a background texture on auth/splash screens.
// Nodes orbit slowly; edges appear between nearby pairs.
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedGraphBackground extends StatefulWidget {
  final int nodeCount;
  final Color color;
  final double opacity;

  const AnimatedGraphBackground({
    super.key,
    this.nodeCount = 20,
    this.color = AppColors.primary,
    this.opacity = 0.12,
  });

  @override
  State<AnimatedGraphBackground> createState() =>
      _AnimatedGraphBackgroundState();
}

class _AnimatedGraphBackgroundState extends State<AnimatedGraphBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<_GraphNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _nodes = List.generate(
      widget.nodeCount,
      (i) => _GraphNode(
        angle:  (2 * math.pi / widget.nodeCount) * i,
        radius: 0.3 + (i % 3) * 0.15,
        speed:  0.0003 + (i % 5) * 0.0001,
        size:   3.0 + (i % 4) * 2.5,
        phase:  i * 0.7,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _GraphBackgroundPainter(
          nodes:    _nodes,
          progress: _controller.value,
          color:    widget.color,
          opacity:  widget.opacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GraphNode {
  final double angle;
  final double radius;
  final double speed;
  final double size;
  final double phase;

  const _GraphNode({
    required this.angle,
    required this.radius,
    required this.speed,
    required this.size,
    required this.phase,
  });

  Offset position(Size size, double progress) {
    final t  = progress * 2 * math.pi + phase;
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = math.min(size.width, size.height) * radius;
    return Offset(
      cx + r * math.cos(angle + t * speed * 10),
      cy + r * math.sin(angle + t * speed * 10),
    );
  }
}

class _GraphBackgroundPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final double progress;
  final Color color;
  final double opacity;

  const _GraphBackgroundPainter({
    required this.nodes,
    required this.progress,
    required this.color,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final positions = nodes.map((n) => n.position(size, progress)).toList();

    final edgePaint = Paint()
      ..strokeWidth = 1
      ..style       = PaintingStyle.stroke;

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final dist = (positions[i] - positions[j]).distance;
        if (dist < size.width * 0.25) {
          final alpha = (1 - dist / (size.width * 0.25)) * opacity * 0.8;
          canvas.drawLine(
            positions[i],
            positions[j],
            edgePaint..color = color.withValues(alpha: alpha),
          );
        }
      }
    }

    final nodePaint = Paint()
      ..style = PaintingStyle.fill;
    for (int i = 0; i < positions.length; i++) {
      canvas.drawCircle(
        positions[i],
        nodes[i].size,
        nodePaint..color = color.withValues(alpha: opacity * 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_GraphBackgroundPainter old) =>
      old.progress != progress;
}
