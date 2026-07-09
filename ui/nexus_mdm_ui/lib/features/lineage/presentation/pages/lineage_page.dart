import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_animations.dart';
import '../../data/lineage_repository.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// LineagePage â€” Visual data-flow overview of the MDM lineage graph
// When [entityId] is provided, the Recent Events section shows real lineage
// data for that entity from the API.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class LineagePage extends StatefulWidget {
  final String? entityId;
  const LineagePage({super.key, this.entityId});

  @override
  State<LineagePage> createState() => _LineagePageState();
}

class _LineagePageState extends State<LineagePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  int _selectedNode = -1;

  late final LineageRepository _lineageRepo;
  List<LineageRecord>? _entityLineage;
  bool _lineageLoading = false;

  LineageGraphData _graphData = LineageGraphData.empty;
  bool _graphLoading = false;

  // Real data loaded from API
  List<_LineageNode> _sourceNodes = [];
  List<_LineStat> _stats = [];
  List<_LineageEvent> _globalEvents = [];
  bool _globalEventsLoading = false;

  // Target nodes: distribution sinks â€” no dedicated API yet, use sensible defaults
  static const _targetNodes = [
    _LineageNode('Data Warehouse', Icons.warehouse_outlined, Color(0xFF00C896),
        'Golden records', 'Mode: CDC'),
    _LineageNode('Analytics BI', Icons.bar_chart_outlined, Color(0xFF3B82F6),
        'Reporting layer', 'Mode: Pull'),
    _LineageNode('Kafka Stream', Icons.stream_outlined, Color(0xFFFF6B35),
        'Event streaming', 'Mode: Webhook'),
    _LineageNode('Downstream API', Icons.upload_outlined, AppColors.primary,
        'Push targets', 'Mode: Push'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _lineageRepo = LineageRepository(ApiClient());
    _loadLineageStats();
    _loadSourceSystems();
    _loadGraph();
    if (widget.entityId != null) {
      _loadEntityLineage(widget.entityId!);
    } else {
      _loadGlobalEvents();
    }
  }

  Future<void> _loadGraph() async {
    setState(() => _graphLoading = true);
    final data = await _lineageRepo.getLineageGraph();
    if (mounted) setState(() { _graphData = data; _graphLoading = false; });
  }

  Future<void> _loadLineageStats() async {
    final api = ApiClient();
    try {
      final resp = await api.get<Map<String, dynamic>>(AppConstants.lineageStatsPath);
      final data = resp.data;
      if (!mounted || data == null) return;
      final total = data['total_lineage_events'] as int? ?? 0;
      setState(() {
        _stats = [
          _LineStat('Total Lineage Events', _compactNum(total), Icons.timeline_rounded, AppColors.primary),
          _LineStat('Source Systems', '${_sourceNodes.length}', Icons.hub_rounded, const Color(0xFF00C896)),
          _LineStat('Active Pipelines', '${_sourceNodes.length + _targetNodes.length}', Icons.speed_rounded, const Color(0xFF8B5CF6)),
          _LineStat('Lineage Types', '${(data['by_type'] as Map?)?.length ?? 0}', Icons.verified_rounded, const Color(0xFF3B82F6)),
        ];
      });
    } catch (_) {}
  }

  Future<void> _loadSourceSystems() async {
    final api = ApiClient();
    try {
      final resp = await api.get<Map<String, dynamic>>(AppConstants.sourceSystemsPath);
      final items = resp.data?['data'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _sourceNodes = items.map((e) {
          final m = e as Map<String, dynamic>;
          final type = (m['connector_type'] as String? ?? '').toLowerCase();
          return _LineageNode(
            m['name'] as String? ?? 'Unknown',
            _iconForConnector(type),
            _colorForConnector(type),
            type,
            m['sync_mode'] as String? ?? 'manual',
          );
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadGlobalEvents() async {
    setState(() => _globalEventsLoading = true);
    final api = ApiClient();
    try {
      final resp = await api.get<Map<String, dynamic>>(
        AppConstants.lineagePath,
        queryParameters: {'limit': '10'},
      );
      if (!mounted) return;
      final items = resp.data?['data'] as List<dynamic>? ?? [];
      setState(() {
        _globalEvents = items.map((e) {
          final m = e as Map<String, dynamic>;
          final ltype = m['lineage_type'] as String? ?? 'Unknown';
          final src = (m['source_entity_id'] as String? ?? '').substring(0, 8);
          final tgt = (m['target_entity_id'] as String? ?? '').substring(0, 8);
          final ts = m['created_at'] as String? ?? '';
          final dt = DateTime.tryParse(ts) ?? DateTime.now();
          return _LineageEvent(ltype, '$srcâ€¦ â†’ $tgtâ€¦', _lineageTypeColor(ltype), _formatAgo(dt));
        }).toList();
        _globalEventsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _globalEventsLoading = false);
    }
  }

  Future<void> _loadEntityLineage(String entityId) async {
    setState(() => _lineageLoading = true);
    try {
      final records = await _lineageRepo.getEntityLineage(entityId);
      if (mounted) setState(() { _entityLineage = records; _lineageLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _lineageLoading = false);
    }
  }

  static IconData _iconForConnector(String type) {
    switch (type) {
      case 'salesforce':  return Icons.cloud_outlined;
      case 'sap':         return Icons.precision_manufacturing_outlined;
      case 'oracle':      return Icons.storage_outlined;
      case 'manual':      return Icons.edit_outlined;
      case 'hubspot':     return Icons.hub_outlined;
      case 'kafka':       return Icons.stream_outlined;
      case 'csv':         return Icons.table_chart_outlined;
      case 'rest_api':    return Icons.api_outlined;
      default:            return Icons.device_hub_outlined;
    }
  }

  static Color _colorForConnector(String type) {
    switch (type) {
      case 'salesforce': return AppColors.primary;
      case 'sap':        return const Color(0xFF00C896);
      case 'oracle':     return const Color(0xFFFF6B35);
      case 'manual':     return const Color(0xFF8B5CF6);
      case 'hubspot':    return const Color(0xFFFF7A59);
      case 'kafka':      return const Color(0xFF3B82F6);
      default:           return AppColors.secondaryText;
    }
  }

  static String _compactNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _exportLineage() {
    final buf = StringBuffer();
    if (_entityLineage != null && _entityLineage!.isNotEmpty) {
      buf.writeln('Lineage ID,Type,Source Entity,Target Entity,Created At');
      for (final rec in _entityLineage!) {
        buf.writeln('"${rec.lineageId}","${rec.lineageType}",'
            '"${rec.sourceEntityId}","${rec.targetEntityId}",'
            '"${rec.createdAt.toIso8601String()}"');
      }
    } else {
      buf.writeln('Event Type,Description,Time Ago');
      for (final ev in _globalEvents) {
        final desc = ev.description.replaceAll('"', '""');
        buf.writeln('"${ev.type}","$desc","${ev.ago}"');
      }
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lineage data copied to clipboard'),
      backgroundColor: AppColors.success,
    ));
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
            _buildEntityLineageGraph(),
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
          onPressed: () {
            _loadLineageStats();
            _loadSourceSystems();
            if (widget.entityId != null) {
              _loadEntityLineage(widget.entityId!);
            } else {
              _loadGlobalEvents();
            }
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.secondaryText,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _exportLineage,
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
    if (_stats.isEmpty) {
      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
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
                  Text('Azile MDM',
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
    Widget bodyContent;
    if (_lineageLoading || _globalEventsLoading) {
      bodyContent = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_entityLineage != null && _entityLineage!.isEmpty) {
      bodyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('No lineage records for this entity.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
        ),
      );
    } else if (_entityLineage != null) {
      final liveEvents = _entityLineage!.take(10).toList().asMap().entries.map((e) {
        final r = e.value;
        final color = _lineageTypeColor(r.lineageType);
        final ago = _formatAgo(r.createdAt);
        final desc = '${r.sourceEntityId.substring(0, 8)}â€¦ â†’ ${r.targetEntityId.substring(0, 8)}â€¦';
        return _buildEventRow(_LineageEvent(r.lineageType, desc, color, ago), e.key);
      }).toList();
      bodyContent = Column(children: liveEvents);
    } else if (_globalEvents.isNotEmpty) {
      bodyContent = Column(
        children: _globalEvents.asMap().entries.map((e) => _buildEventRow(e.value, e.key)).toList(),
      );
    } else {
      bodyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('No lineage events yet.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
        ),
      );
    }

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
              Text(
                widget.entityId != null ? 'Entity Lineage' : 'Recent Lineage Events',
                style: AppTextStyles.titleSmall,
              ),
              const Spacer(),
              if (widget.entityId != null)
                TextButton.icon(
                  onPressed: () => _loadEntityLineage(widget.entityId!),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text('Refresh',
                      style: AppTextStyles.buttonSmall.copyWith(color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          bodyContent,
        ],
      ),
    )
        .animate(delay: 300.ms)
        .fadeIn(duration: AppAnimations.slow)
        .slideY(begin: 0.04, end: 0, curve: AppAnimations.easeOutQuint);
  }

  Color _lineageTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'derived':       return AppColors.primary;
      case 'merged':        return const Color(0xFF8B5CF6);
      case 'transformed':   return const Color(0xFF3B82F6);
      case 'replicated':    return const Color(0xFF00C896);
      default:              return AppColors.secondaryText;
    }
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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

  // ---------------------------------------------------------------------------
  // BL-068: Entity Lineage DAG
  // ---------------------------------------------------------------------------

  Widget _buildEntityLineageGraph() {
    if (_graphLoading) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_graphData.isEmpty) return const SizedBox.shrink();

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
              const Icon(Icons.account_tree_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Entity Relationship Graph', style: AppTextStyles.titleSmall),
              const Spacer(),
              Text(
                '${_graphData.nodes.length} nodes Â· ${_graphData.edges.length} edges',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 320,
            child: _EntityDagWidget(
              nodes: _graphData.nodes,
              edges: _graphData.edges,
            ),
          ),
        ],
      ),
    )
        .animate(delay: 250.ms)
        .fadeIn(duration: AppAnimations.slow)
        .slideY(begin: 0.04, end: 0, curve: AppAnimations.easeOutQuint);
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Models
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Custom painter for animated flow arrows
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// BL-068 â€” Entity DAG widget + painters
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _EntityDagWidget extends StatelessWidget {
  final List<LineageGraphNode> nodes;
  final List<LineageGraphEdge> edges;

  const _EntityDagWidget({required this.nodes, required this.edges});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      const nodeW = 130.0;
      const nodeH = 48.0;

      final sourceIds = edges.map((e) => e.source).toSet();
      final targetIds = edges.map((e) => e.target).toSet();

      final sourceOnly = nodes.where((n) => sourceIds.contains(n.id) && !targetIds.contains(n.id)).toList();
      final targetOnly = nodes.where((n) => targetIds.contains(n.id) && !sourceIds.contains(n.id)).toList();
      final middle     = nodes.where((n) => sourceIds.contains(n.id) && targetIds.contains(n.id)).toList();
      final isolated   = nodes.where((n) => !sourceIds.contains(n.id) && !targetIds.contains(n.id)).toList();

      final Map<String, Offset> positions = {};

      void layoutColumn(List<LineageGraphNode> col, double cx) {
        if (col.isEmpty) return;
        final spacing = h / (col.length + 1);
        for (int i = 0; i < col.length; i++) {
          positions[col[i].id] = Offset(cx - nodeW / 2, spacing * (i + 1) - nodeH / 2);
        }
      }

      layoutColumn(sourceOnly + isolated, nodeW / 2 + 16);
      layoutColumn(middle, w / 2);
      layoutColumn(targetOnly, w - nodeW / 2 - 16);

      return Stack(
        children: [
          CustomPaint(
            size: Size(w, h),
            painter: _DagEdgePainter(
              edges: edges,
              positions: positions,
              nodeW: nodeW,
              nodeH: nodeH,
            ),
          ),
          ...nodes.map((node) {
            final pos = positions[node.id];
            if (pos == null) return const SizedBox.shrink();
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              width: nodeW,
              height: nodeH,
              child: _DagNodeBox(node: node),
            );
          }),
        ],
      );
    });
  }
}

class _DagNodeBox extends StatelessWidget {
  final LineageGraphNode node;
  const _DagNodeBox({required this.node});

  static Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'customer':     return AppColors.primary;
      case 'product':      return const Color(0xFF00C896);
      case 'vendor':       return const Color(0xFFFF6B35);
      case 'location':     return const Color(0xFF3B82F6);
      case 'employee':     return const Color(0xFF8B5CF6);
      case 'organization': return const Color(0xFFFFB800);
      default:             return AppColors.secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(node.entityType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node.label,
              style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          Text(node.entityType,
              style: AppTextStyles.labelSmall.copyWith(color: color, fontSize: 9),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _DagEdgePainter extends CustomPainter {
  final List<LineageGraphEdge> edges;
  final Map<String, Offset> positions;
  final double nodeW;
  final double nodeH;

  const _DagEdgePainter({
    required this.edges,
    required this.positions,
    required this.nodeW,
    required this.nodeH,
  });

  static Color _edgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'derived':     return AppColors.primary;
      case 'merged':      return const Color(0xFF8B5CF6);
      case 'transformed': return const Color(0xFF3B82F6);
      case 'replicated':  return const Color(0xFF00C896);
      default:            return AppColors.secondaryText;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final srcPos = positions[edge.source];
      final tgtPos = positions[edge.target];
      if (srcPos == null || tgtPos == null) continue;

      final src = Offset(srcPos.dx + nodeW, srcPos.dy + nodeH / 2);
      final tgt = Offset(tgtPos.dx, tgtPos.dy + nodeH / 2);
      final color = _edgeColor(edge.lineageType);
      final ctrl = (tgt.dx - src.dx) / 3;

      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..cubicTo(
          src.dx + ctrl, src.dy,
          tgt.dx - ctrl, tgt.dy,
          tgt.dx, tgt.dy,
        );

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      // Arrowhead at target
      const aSize = 6.0;
      final arrow = Path()
        ..moveTo(tgt.dx, tgt.dy)
        ..lineTo(tgt.dx - aSize, tgt.dy - aSize / 2)
        ..lineTo(tgt.dx - aSize, tgt.dy + aSize / 2)
        ..close();
      canvas.drawPath(arrow,
          Paint()..color = color.withValues(alpha: 0.8)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_DagEdgePainter old) =>
      old.edges != edges || old.positions != positions;
}
