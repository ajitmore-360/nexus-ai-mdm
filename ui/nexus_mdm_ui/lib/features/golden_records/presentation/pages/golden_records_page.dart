import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/golden_record.dart';
import '../../../../shared/models/entity.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/golden_records_repository.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Page
// ──────────────────────────────────────────────────────────────────────────────

class GoldenRecordsPage extends StatefulWidget {
  const GoldenRecordsPage({super.key});

  @override
  State<GoldenRecordsPage> createState() => _GoldenRecordsPageState();
}

class _GoldenRecordsPageState extends State<GoldenRecordsPage> {
  bool _isLoading = true;
  List<GoldenRecord> _records = [];
  String _searchQuery = '';
  String _activeFilter = 'all';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = GetIt.instance<GoldenRecordsRepository>();
    final result = await repo.getGoldenRecords();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result case Success(:final data)) {
        _records = data;
      }
      // On failure _records stays empty — EmptyState widget is shown
    });
  }

  List<GoldenRecord> get _filtered {
    return _records.where((r) {
      final matchesSearch = _searchQuery.isEmpty ||
          r.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.tags.any((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));
      final matchesFilter = switch (_activeFilter) {
        'verified'     => r.isVerified,
        'unverified'   => !r.isVerified,
        'person'       => r.entityType == EntityType.person,
        'organization' => r.entityType == EntityType.organization,
        'product'      => r.entityType == EntityType.product,
        _              => true,
      };
      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final verifiedCount = _records.where((r) => r.isVerified).length;
    final avgTrust = _records.isEmpty
        ? 0.0
        : _records.map((r) => r.trustScore).reduce((a, b) => a + b) / _records.length;
    final totalSources = _records.isEmpty
        ? 0
        : _records.map((r) => r.contributingSourceCount).reduce((a, b) => a + b);

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildKpiBar(_records.length, verifiedCount, avgTrust, totalSources),
          _buildSearchAndFilter(),
          Expanded(
            child: _isLoading
                ? _buildShimmer()
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.stars_outlined,
                        title: 'No golden records found',
                        description: 'Try adjusting your search or filter criteria.',
                      )
                    : _buildList(filtered),
          ),
        ],
      ),
    );
  }

  // ── KPI Bar ──────────────────────────────────────────────────────────────────

  Widget _buildKpiBar(int total, int verified, double avgTrust, int totalSources) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        children: [
          _KpiCard(
            label: 'Golden Records',
            value: '$total',
            icon: Icons.stars_rounded,
            color: AppColors.statusGolden,
          ).animate().fadeIn(duration: 350.ms),
          const SizedBox(width: 12),
          _KpiCard(
            label: 'Verified',
            value: '$verified',
            sub: '${total > 0 ? (verified / total * 100).round() : 0}% of total',
            icon: Icons.verified_rounded,
            color: AppColors.primary,
          ).animate(delay: 60.ms).fadeIn(duration: 350.ms),
          const SizedBox(width: 12),
          _KpiCard(
            label: 'Avg Trust Score',
            value: '${(avgTrust * 100).round()}%',
            icon: Icons.shield_outlined,
            color: AppColors.info,
          ).animate(delay: 120.ms).fadeIn(duration: 350.ms),
          const SizedBox(width: 12),
          _KpiCard(
            label: 'Contributing Sources',
            value: '$totalSources',
            sub: 'across all records',
            icon: Icons.storage_rounded,
            color: AppColors.aiPurple,
          ).animate(delay: 180.ms).fadeIn(duration: 350.ms),
        ],
      ),
    );
  }

  // ── Search + Filter Bar ───────────────────────────────────────────────────────

  Widget _buildSearchAndFilter() {
    final filters = <(String, String)>[
      ('All', 'all'),
      ('Verified', 'verified'),
      ('Unverified', 'unverified'),
      ('Person', 'person'),
      ('Organization', 'organization'),
      ('Product', 'product'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          // Search field
          SizedBox(
            width: 300,
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Search by name, ID, or tag…',
                hintStyle: AppTextStyles.inputHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.mutedText),
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Filter chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((f) {
                  final isActive = _activeFilter == f.$2;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _activeFilter = f.$2),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.elevatedCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.divider,
                          ),
                        ),
                        child: Text(
                          f.$1,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isActive ? AppColors.primary : AppColors.secondaryText,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Count
          Text(
            '${_filtered.length} records',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Widget _buildList(List<GoldenRecord> records) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildCard(records[i], i),
    );
  }

  Widget _buildCard(GoldenRecord record, int index) {
    return GestureDetector(
      onTap: () => context.go('/dashboard/entities/${record.entityId}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: record.isVerified
                ? AppColors.statusGolden.withValues(alpha: 0.25)
                : AppColors.divider,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: record.isVerified
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                      )
                    : AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _entityTypeIcon(record.entityType),
                color: Colors.white,
                size: 22,
              ),
            ),

            const SizedBox(width: 14),

            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(record.displayName, style: AppTextStyles.titleSmall),
                      const SizedBox(width: 8),
                      _EntityTypeChip(type: record.entityType),
                      const SizedBox(width: 8),
                      if (record.isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.statusGolden.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.statusGolden.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_rounded, size: 11, color: AppColors.statusGolden),
                              const SizedBox(width: 4),
                              Text(
                                'VERIFIED',
                                style: AppTextStyles.badgeLabel.copyWith(
                                  color: AppColors.statusGolden,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      Text(
                        record.id,
                        style: AppTextStyles.timestamp.copyWith(color: AppColors.mutedText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quality scores row
                  Row(
                    children: [
                      _QualityBar(label: 'Completeness', value: record.completenessScore, color: AppColors.primary),
                      const SizedBox(width: 16),
                      _QualityBar(label: 'Consistency', value: record.consistencyScore, color: AppColors.info),
                      const SizedBox(width: 16),
                      _QualityBar(label: 'Accuracy', value: record.accuracyScore, color: AppColors.aiPurple),
                      const SizedBox(width: 20),
                      // Trust score circle
                      _TrustCircle(score: record.trustScore),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Sources + tags row
                  Row(
                    children: [
                      const Icon(Icons.storage_rounded, size: 12, color: AppColors.mutedText),
                      const SizedBox(width: 4),
                      ...record.contributingSources.take(3).map((src) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.elevatedCard,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Text(src, style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
                            ),
                          )),
                      if (record.contributingSourceCount > 3)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.elevatedCard,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${record.contributingSourceCount - 3}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.mutedText,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      const Spacer(),
                      // Merged count
                      if (record.mergedEntityCount > 1)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.merge_rounded, size: 12, color: AppColors.statusMerged),
                            const SizedBox(width: 4),
                            Text(
                              '${record.mergedEntityCount} merged',
                              style: AppTextStyles.labelSmall.copyWith(color: AppColors.statusMerged),
                            ),
                          ],
                        ),
                      const SizedBox(width: 12),
                      // Tags
                      ...record.tags.take(2).map((tag) => Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: AppTextStyles.badgeLabel.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 60).ms)
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.04, end: 0, duration: 350.ms);
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => LoadingShimmer(
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  IconData _entityTypeIcon(EntityType type) {
    switch (type) {
      case EntityType.person:
        return Icons.person_rounded;
      case EntityType.organization:
        return Icons.business_rounded;
      case EntityType.product:
        return Icons.inventory_2_rounded;
      default:
        return Icons.hub_rounded;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Supporting Widgets
// ──────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppTextStyles.titleMedium.copyWith(color: color)),
                Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText)),
                if (sub != null)
                  Text(sub!, style: AppTextStyles.timestamp.copyWith(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _QualityBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTextStyles.tableHeader.copyWith(fontSize: 9)),
              Text(
                '${(value * 100).round()}%',
                style: AppTextStyles.badgeLabel.copyWith(color: color, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 3)],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustCircle extends StatelessWidget {
  final double score;
  const _TrustCircle({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 0.9
        ? AppColors.statusGolden
        : score >= 0.75
            ? AppColors.primary
            : AppColors.warning;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 4,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeCap: StrokeCap.round,
          ),
          Text(
            '${(score * 100).round()}',
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityTypeChip extends StatelessWidget {
  final EntityType type;
  const _EntityTypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      EntityType.person       => ('Person', AppColors.info),
      EntityType.organization => ('Org', AppColors.aiPurple),
      EntityType.product      => ('Product', AppColors.warning),
      _                       => ('Entity', AppColors.mutedText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: AppTextStyles.badgeLabel.copyWith(color: color, fontSize: 9)),
    );
  }
}
