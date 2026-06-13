import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_animations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LineagePage — Visual data-flow overview of the MDM lineage graph
// ─────────────────────────────────────────────────────────────────────────────

class LineagePage extends StatefulWidget {
  const LineagePage({super.key});

  @override
  State<LineagePage> createState() => _LineagePageState();
}

class _LineagePageState extends State<LineagePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  int _selectedNode = -1;

  static const _sourceNodes = [
    _LineageNode('Salesforce CRM', Icons.cloud_outlined, AppColors.primary,
        '12,847 entities', 'Last sync: 4 min ago'),
    _LineageNode('SAP ERP', Icons.precision_manufacturing_outlined,
        Color(0xFF00C896), '9,231 entities', 'Last sync: 1 hr ago'),
    _LineageNode('Oracle CRM', Icons.storage_outlined, Color(0xFFFF6B35),
        '3,419 entities', 'Last sync: 3 days ago'),
    _LineageNode('Manual Entry', Icons.edit_outlined, Color(0xFF8B5CF6),
        '847 entities', 'Last sync: Real-time'),
  ];

  static const _targetNodes = [
    _LineageNode('Salesforce Output', Icons.upload_outlined, AppColors.primary,
        '11,200 pushed', 'Mode: Push'),
    _LineageNode('Data Warehouse', Icons.warehouse_outlined, Color(0xFF00C896),
        '22,344 synced', 'Mode: CDC'),
    _LineageNode('Analytics BI', Icons.bar_chart_outlined, Color(0xFF3B82F6),
        '18,000 records', 'Mode: Pull'),
    _LineageNode('Kafka Stream', Icons.stream_outlined, Color(0xFFFF6B35),
        '1.2M events', 'Mode: Webhook'),
  ];

  static const _stats = [
    _LineStat('Total Lineage Events', '2.4M', Icons.timeline_rounded, AppColors.primary),
    _LineStat('Active Pipelines', '14', Icons.hub_rounded, Color(0xFF00C896)),
    _LineStat('Avg. Propagation', '340ms', Icons.speed_rounded, Color(0xFF8B5CF6)),
    _LineStat('Data Freshness', '98.7%', Icons.verified_rounded, Color(0xFF3B82F6)),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStats(),
            const SizedBox(height: 24),
            _buildLineageGraph(),
            const SizedBox(height: 24),
            _buildRecentEvents(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.account_tree_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data Lineage', style: AppTextStyles.titleLarge),
            Text('End-to-end data flow and provenance tracking',
                style: AppTextStyles.bodySmall),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.secondaryText,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download_outlined, size: 16),
          label: const Text('Export'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: AppAnimations.normal)
        .slideY(begin: -0.05, end: 0, curve: AppAnimations.easeOutQuint);
  }

  Widget _buildStats() {
    return Row(
      children: _stats.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < _stats.length - 1 ? 12 : 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(s.icon, color: s.color, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.value,
                        style: AppTextStyles.statValue
                            .copyWith(fontSize: 18, color: s.color)),
                    Text(s.label, style: AppTextStyles.labelSmall),
                  ],
                ),
              ],
            ),
          ).animate(delay: AppAnimations.stagger(i)).fadeIn().slideY(begin: 0.05, end: 0),
        );
      }).toList(),
    );
  }

  Widget _buildLineageGraph() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schema_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Live Lineage Graph', style: AppTextStyles.titleSmall),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Source nodes
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _sourceNodes.asMap().entries.map((e) {
                      return _buildFlowNode(e.value, e.key, isSource: true);
                    }).toList(),
                  ),
                ),
                // Arrow lane with pulse
                Expanded(
                  flex: 2,
                  child: _buildCenterLane(),
                ),
                // Target nodes
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _targetNodes.asMap().entries.map((e) {
                      return _buildFlowNode(e.value, e.key + 10, isSource: false);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: 200.ms)
        .fadeIn(duration: AppAnimations.slow)
        .slideY(begin: 0.04, end: 0, curve: AppAnimations.easeOutQuint);
  }

  Widget _buildFlowNode(_LineageNode node, int index, {required bool isSource}) {
    final isSelected = _selectedNode == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNode = isSelected ? -1 : index),
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? node.color.withValues(alpha: 0.12)
              : AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? node.color : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (!isSource) const Spacer(),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: node.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(node.icon, size: 14, color: node.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: isSource
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(node.name,
                      style: AppTextStyles.labelSmall
                          .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(node.subtitle,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.mutedText, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isSource) const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterLane() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        return CustomPaint(
          painter: _FlowLanePainter(_pulseCtrl.value),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.auroraGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hub_rounded, color: Colors.white, size: 18),
                  const SizedBox(height: 4),
                  Text('Nexus MDM',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      )),
                  Text('Golden Record',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white70,
                        fontSize: 9,
                      )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentEvents() {
    const events = [
      _LineageEvent('EntityCreated', 'Customer #CUST-001234 created via Salesforce',
          AppColors.primary, '2s ago'),
      _LineageEvent('EntityUpdated', 'Vendor #VEND-005678 phone updated from SAP',
          Color(0xFF00C896), '14s ago'),
      _LineageEvent('EntityMerged', 'Duplicate Customer records merged → Golden Record',
          Color(0xFF8B5CF6), '1 min ago'),
      _LineageEvent('EntityDistributed', 'Material #MAT-00890 pushed to 3 targets',
          Color(0xFF3B82F6), '3 min ago'),
      _LineageEvent('QualityViolation', 'Customer email format invalid — quarantined',
          AppColors.warning, '7 min ago'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Recent Lineage Events', style: AppTextStyles.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text('View all',
                    style: AppTextStyles.buttonSmall
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          ...events.asMap().entries.map((e) => _buildEventRow(e.value, e.key)),
        ],
      ),
    )
        .animate(delay: 300.ms)
        .fadeIn(duration: AppAnimations.slow)
        .slideY(begin: 0.04, end: 0, curve: AppAnimations.easeOutQuint);
  }

  Widget _buildEventRow(_LineageEvent event, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider,
            width: index < 4 ? 1 : 0,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: event.color,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: event.color.withValues(alpha: 0.25)),
            ),
            child: Text(event.type,
                style: AppTextStyles.badgeLabel.copyWith(color: event.color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(event.description,
                style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Text(event.ago, style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class _LineageNode {
  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;
  final String hint;
  const _LineageNode(this.name, this.icon, this.color, this.subtitle, this.hint);
}

class _LineStat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _LineStat(this.label, this.value, this.icon, this.color);
}

class _LineageEvent {
  final String type;
  final String description;
  final Color color;
  final String ago;
  const _LineageEvent(this.type, this.description, this.color, this.ago);
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter for animated flow arrows
// ─────────────────────────────────────────────────────────────────────────────

class _FlowLanePainter extends CustomPainter {
  final double progress;
  _FlowLanePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Source arrows (left side)
    for (int i = 0; i < 4; i++) {
      final y = size.height * (i + 0.5) / 4;
      _drawArrow(canvas, size, Offset(0, y), Offset(cx - 40, cy),
          const Color(0xFF1E3A5F), const Color(0xFF3B82F6), progress, i);
    }
    // Target arrows (right side)
    for (int i = 0; i < 4; i++) {
      final y = size.height * (i + 0.5) / 4;
      _drawArrow(canvas, size, Offset(cx + 40, cy), Offset(size.width, y),
          const Color(0xFF1E3A5F), const Color(0xFF00C896),
          (progress + 0.5) % 1.0, i);
    }
  }

  void _drawArrow(Canvas canvas, Size size, Offset start, Offset end,
      Color baseColor, Color pulseColor, double prog, int index) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + (end.dx - start.dx) * 0.4, start.dy,
        start.dx + (end.dx - start.dx) * 0.6, end.dy,
        end.dx, end.dy,
      );

    // Base line
    canvas.drawPath(
      path,
      Paint()
        ..color = baseColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Pulse dot
    final metrics = path.computeMetrics().first;
    final offset = (prog + index * 0.25) % 1.0;
    final tangent = metrics.getTangentForOffset(metrics.length * offset);
    if (tangent != null) {
      canvas.drawCircle(
        tangent.position,
        3.0,
        Paint()
          ..color = pulseColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );
      // Glow
      canvas.drawCircle(
        tangent.position,
        5.0,
        Paint()
          ..color = pulseColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowLanePainter old) => old.progress != progress;
}
