import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class NexusLogo extends StatefulWidget {
  final double size;
  final bool showText;
  final bool shouldPulse;
  final Color? primaryColor;
  final Color? textColor;

  const NexusLogo({
    super.key,
    this.size = 40,
    this.showText = true,
    this.shouldPulse = false,
    this.primaryColor,
    this.textColor,
  });

  @override
  State<NexusLogo> createState() => _NexusLogoState();
}

class _NexusLogoState extends State<NexusLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.shouldPulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor ?? AppColors.primary;
    final textColor = widget.textColor ?? AppColors.primaryText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: widget.shouldPulse ? _pulseAnimation.value : 1.0,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _NexusLogoPainter(color: color),
                ),
              ),
            );
          },
        ),
        if (widget.showText) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NEXUS',
                style: AppTextStyles.titleMedium.copyWith(
                  color: textColor,
                  letterSpacing: 2,
                  fontSize: widget.size * 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'AI MDM',
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  letterSpacing: 1.5,
                  fontSize: widget.size * 0.22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NexusLogoPainter extends CustomPainter {
  final Color color;

  const _NexusLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;

    // Node positions — hexagonal graph
    final nodes = <Offset>[
      Offset(cx, cy - r * 0.9), // top
      Offset(cx + r * 0.78, cy - r * 0.45), // top-right
      Offset(cx + r * 0.78, cy + r * 0.45), // bottom-right
      Offset(cx, cy + r * 0.9), // bottom
      Offset(cx - r * 0.78, cy + r * 0.45), // bottom-left
      Offset(cx - r * 0.78, cy - r * 0.45), // top-left
      Offset(cx, cy), // center
    ];

    final edgePaint = Paint()
      ..color = color.withValues(alpha:0.5)
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw edges
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0],
      [6, 0], [6, 2], [6, 4],
    ];

    for (final edge in edges) {
      canvas.drawLine(nodes[edge[0]], nodes[edge[1]], edgePaint);
    }

    // Draw nodes
    for (int i = 0; i < nodes.length; i++) {
      final isCenter = i == 6;
      final nodeRadius =
          isCenter ? size.width * 0.115 : size.width * 0.08;

      // Glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha:0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, nodeRadius * 1.5);
      canvas.drawCircle(nodes[i], nodeRadius * 2, glowPaint);

      // Outer circle
      final outerPaint = Paint()
        ..color = color.withValues(alpha:isCenter ? 0.4 : 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nodes[i], nodeRadius * 1.4, outerPaint);

      // Inner circle
      final innerPaint = Paint()
        ..color = isCenter ? color : color.withValues(alpha:0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nodes[i], nodeRadius, innerPaint);
    }
  }

  @override
  bool shouldRepaint(_NexusLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

// Animated graph nodes for splash/login backgrounds
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
        angle: (2 * math.pi / widget.nodeCount) * i,
        radius: 0.3 + (i % 3) * 0.15,
        speed: 0.0003 + (i % 5) * 0.0001,
        size: 3.0 + (i % 4) * 2.5,
        phase: i * 0.7,
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
      builder: (context, child) {
        return CustomPaint(
          painter: _GraphBackgroundPainter(
            nodes: _nodes,
            progress: _controller.value,
            color: widget.color,
            opacity: widget.opacity,
          ),
          size: Size.infinite,
        );
      },
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
    final t = progress * 2 * math.pi + phase;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(size.width, size.height) * radius;
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

    // Draw edges between nearby nodes
    final edgePaint = Paint()
      ..color = color.withValues(alpha:opacity * 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final dist = (positions[i] - positions[j]).distance;
        if (dist < size.width * 0.25) {
          final alpha = (1 - dist / (size.width * 0.25)) * opacity * 0.8;
          canvas.drawLine(
            positions[i],
            positions[j],
            edgePaint..color = color.withValues(alpha:alpha),
          );
        }
      }
    }

    // Draw nodes
    for (int i = 0; i < positions.length; i++) {
      final nodePaint = Paint()
        ..color = color.withValues(alpha:opacity * 1.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(positions[i], nodes[i].size, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_GraphBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
