import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/models/entity.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/trust_score_bar.dart';
import '../../../../shared/widgets/entity_avatar.dart';
import '../../../../shared/widgets/ai_badge.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../data/entity_repository.dart';

class EntityDetailPage extends StatefulWidget {
  final String entityId;
  final bool showLineage;

  const EntityDetailPage({
    super.key,
    required this.entityId,
    this.showLineage = false,
  });

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final EntityRepository _repository;
  bool _isLoading = true;
  CanonicalEntity? _entity;

  @override
  void initState() {
    super.initState();
    _repository = EntityRepository(ApiClient());
    _tabController = TabController(
        length: 5, vsync: this,
        initialIndex: widget.showLineage ? 3 : 0);
    _loadEntity();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEntity() async {
    final result = await _repository.getEntity(widget.entityId);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      switch (result) {
        case Success<CanonicalEntity>(:final data):
          _entity = data;
        case Failure():
          // Fall back to demo data — pick by id or first available.
          final demos = CanonicalEntity.demoList;
          _entity = demos.isEmpty
              ? null
              : demos.firstWhere(
                  (e) => e.id == widget.entityId,
                  orElse: () => demos.first,
                );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingState();
    if (_entity == null) return _buildNotFound();
    return _buildContent();
  }

  Widget _buildLoadingState() {
    return const Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _ShimmerBox(width: 48, height: 48, radius: 12),
              SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ShimmerBox(width: 200, height: 22, radius: 4),
                SizedBox(height: 8),
                _ShimmerBox(width: 120, height: 14, radius: 4),
              ])),
            ]),
            SizedBox(height: 24),
            _ShimmerBox(width: double.infinity, height: 48, radius: 8),
            SizedBox(height: 16),
            EntityListShimmer(count: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.mutedText),
            const SizedBox(height: 16),
            Text('Entity not found', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard/entities'),
              child: const Text('Back to Explorer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final entity = _entity!;
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildEntityHeader(entity),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAttributesTab(entity),
                _buildAiInsightsTab(entity),
                _buildConflictsTab(entity),
                _buildLineageTab(entity),
                _buildHistoryTab(entity),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityHeader(CanonicalEntity entity) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb
          Row(
            children: [
              GestureDetector(
                onTap: () => context.go('/dashboard/entities'),
                child: Text(
                  'Entity Explorer',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primary),
                ),
              ),
              const Icon(Icons.chevron_right, size: 14,
                  color: AppColors.mutedText),
              Text(entity.displayName, style: AppTextStyles.bodySmall),
            ],
          ),
          const SizedBox(height: 16),

          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntityAvatar(
                type: entity.type,
                size: 56,
                showGoldenRing: entity.isGolden,
              ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entity.displayName,
                          style: AppTextStyles.headlineSmall,
                        ).animate().fadeIn(delay: 50.ms),
                        const SizedBox(width: 12),
                        StatusBadge(status: entity.status)
                            .animate(delay: 100.ms).fadeIn(),
                        if (entity.isGolden) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.statusGolden.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: AppColors.statusGolden.withValues(alpha:0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars_rounded,
                                    color: AppColors.statusGolden, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'GOLDEN RECORD',
                                  style: AppTextStyles.badgeLabel.copyWith(
                                    color: AppColors.statusGolden,
                                  ),
                                ),
                              ],
                            ),
                          ).animate(delay: 150.ms).fadeIn(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          entity.typeDisplayName,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('•',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.mutedText)),
                        const SizedBox(width: 12),
                        Text(
                          entity.id,
                          style: AppTextStyles.codeStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildScoreChip('Trust', entity.trustScore,
                            AppColors.primary),
                        const SizedBox(width: 12),
                        _buildScoreChip('Quality', entity.qualityScore,
                            AppColors.info),
                        const SizedBox(width: 16),
                        const Icon(Icons.source_outlined,
                            size: 14, color: AppColors.secondaryText),
                        const SizedBox(width: 4),
                        Text(
                          '${entity.sourceSystems.length} source${entity.sourceSystems.length != 1 ? 's' : ''}',
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(width: 16),
                        if (entity.hasDuplicates) ...[
                          const Icon(Icons.copy_outlined,
                              size: 14, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Text(
                            '${entity.duplicateCount} duplicate${entity.duplicateCount != 1 ? 's' : ''}',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.warning),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/dashboard/lineage/${entity.id}'),
                    icon: const Icon(Icons.account_tree_outlined, size: 16),
                    label: const Text('Lineage'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/dashboard/match-queue'),
                    icon: const Icon(Icons.merge_type_rounded, size: 16),
                    label: const Text('Find Matches'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/dashboard/entities/${_entity!.id}/edit',
                      extra: _entity,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                ],
              ).animate(delay: 200.ms).fadeIn(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreChip(String label, double score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha:0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.secondaryText),
          ),
          const SizedBox(width: 6),
          Text(
            '${(score * 100).round()}%',
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.cardSurface,
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Attributes'),
          Tab(text: 'AI Insights'),
          Tab(text: 'Conflicts'),
          Tab(text: 'Lineage'),
          Tab(text: 'History'),
        ],
      ),
    );
  }

  Widget _buildAttributesTab(CanonicalEntity entity) {
    final demoAttrs = [
      ('Full Name', 'full_name', entity.displayName, 'Salesforce CRM', 0.99, false),
      ('Email', 'email', 'a.chen@company.com', 'Salesforce CRM', 0.95, true),
      ('Phone', 'phone', '+1 (555) 012-3456', 'HubSpot', 0.88, false),
      ('Department', 'department', 'Engineering', 'Workday HR', 0.97, false),
      ('Title', 'title', 'Senior Data Architect', 'Salesforce CRM', 0.91, true),
      ('Location', 'location', 'San Francisco, CA', 'Workday HR', 0.85, false),
      ('LinkedIn', 'linkedin', 'linkedin.com/in/achen', 'Manual Entry', 0.72, false),
      ('Source ID', 'source_id', 'SF-000123456', 'Salesforce CRM', 1.0, false),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${demoAttrs.length} attributes from ${entity.sourceSystems.length} sources',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: demoAttrs.asMap().entries.map((entry) {
                final i = entry.key;
                final attr = entry.value;
                return _buildAttributeRow(attr, i == demoAttrs.length - 1);
              }).toList(),
            ),
          ).animate().fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildAttributeRow(
      (String, String, dynamic, String, double, bool) attr, bool isLast) {
    final (displayName, fieldName, value, source, confidence, hasConflict) = attr;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: AppTextStyles.titleSmall),
                Text(fieldName,
                    style: AppTextStyles.timestamp),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.toString(),
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    if (hasConflict)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha:0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 12, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              'CONFLICT',
                              style: AppTextStyles.badgeLabel.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(source,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TrustScoreBar(
                        score: confidence,
                        height: 4,
                        showPercentage: true,
                        animate: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiInsightsTab(CanonicalEntity entity) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiBadge(label: 'AI Analysis'),
              const SizedBox(width: 8),
              Text(
                'Generated by Nexus AI v2.1 · ${DateTime.now().difference(entity.updatedAt).inHours}h ago',
                style: AppTextStyles.timestamp,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // AI Summary card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.aiPurple.withValues(alpha:0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.aiPurple.withValues(alpha:0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.aiPurple, size: 18),
                    const SizedBox(width: 8),
                    Text('Entity Analysis',
                        style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.aiPurple)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This entity appears to be a high-confidence canonical record for a senior technical professional. '
                  'The trust score of ${(entity.trustScore * 100).round()}% reflects strong data consistency across ${entity.sourceSystems.length} connected source systems. '
                  'Email field shows a minor conflict between Salesforce CRM and HubSpot — likely a work vs personal email distinction. '
                  'Recommend reviewing title attribute from Workday HR vs Salesforce CRM for canonicalization.',
                  style: AppTextStyles.aiMessage,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 16),

          // Recommendations
          _buildAiRecommendationCard(
            'Resolve Email Conflict',
            'Two email values detected from different sources. Recommend designating the Salesforce CRM email as primary based on confidence score.',
            Icons.email_outlined,
            AppColors.warning,
            '94% confidence',
          ),
          const SizedBox(height: 12),
          _buildAiRecommendationCard(
            'Potential Duplicate Detected',
            '3 entities in the system share high name and phone similarity. Review match candidates in the Match Queue.',
            Icons.copy_outlined,
            AppColors.error,
            '87% match score',
          ),
          const SizedBox(height: 12),
          _buildAiRecommendationCard(
            'Complete LinkedIn Profile',
            'Adding a verified LinkedIn URL would increase completeness score by 8% and improve entity confidence.',
            Icons.link_outlined,
            AppColors.info,
            'Optional',
          ),
        ],
      ),
    );
  }

  Widget _buildAiRecommendationCard(
    String title,
    String description,
    IconData icon,
    Color color,
    String badge,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: AppTextStyles.titleSmall),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: AppTextStyles.badgeLabel
                            .copyWith(color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description, style: AppTextStyles.bodySmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 28),
                        textStyle: AppTextStyles.buttonSmall,
                        foregroundColor: color,
                        side: BorderSide(color: color.withValues(alpha:0.5)),
                      ),
                      child: const Text('Take Action'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        minimumSize: const Size(0, 28),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 400.ms);
  }

  Widget _buildConflictsTab(CanonicalEntity entity) {
    if (entity.conflictCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 36, color: AppColors.primary),
            ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
            const SizedBox(height: 16),
            Text('No conflicts detected',
                style: AppTextStyles.titleMedium).animate(delay: 100.ms).fadeIn(),
            const SizedBox(height: 6),
            Text('All attribute values are consistent across sources.',
                style: AppTextStyles.bodySmall).animate(delay: 150.ms).fadeIn(),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildConflictItem(
            'Email Address',
            'Two different email values exist across source systems.',
            [
              ('Salesforce CRM', 'a.chen@techcorp.com', 0.95),
              ('HubSpot', 'alex.chen@gmail.com', 0.72),
            ],
          ),
          const SizedBox(height: 12),
          _buildConflictItem(
            'Job Title',
            'Job title varies between HR and CRM systems.',
            [
              ('Salesforce CRM', 'Senior Data Architect', 0.91),
              ('Workday HR', 'Principal Data Engineer', 0.88),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConflictItem(
    String field,
    String description,
    List<(String, String, double)> values,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(field,
                  style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: AppTextStyles.bodySmall),
          const SizedBox(height: 12),
          ...values.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.$1,
                              style: AppTextStyles.labelSmall
                                  .copyWith(color: AppColors.primary)),
                          Text(v.$2,
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ),
                    TrustScoreBar(
                      score: v.$3,
                      width: 80,
                      showLabel: false,
                      animate: false,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 28),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                      child: const Text('Use this'),
                    ),
                  ],
                ),
              )),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildLineageTab(CanonicalEntity entity) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.account_tree_outlined,
                color: AppColors.navyBackground, size: 40),
          ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
          const SizedBox(height: 20),
          Text('Data Lineage', style: AppTextStyles.headlineSmall)
              .animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 8),
          Text(
            'Visual lineage graph for ${entity.displayName}',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText),
          ).animate(delay: 150.ms).fadeIn(),
          const SizedBox(height: 24),
          ...entity.sourceSystems.map((src) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.source_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(src, style: AppTextStyles.bodyMedium),
                      const Icon(Icons.arrow_forward,
                          size: 14, color: AppColors.mutedText),
                      Text(entity.displayName,
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                ).animate(delay: (200 + entity.sourceSystems.indexOf(src) * 60).ms).fadeIn(),
              )),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(CanonicalEntity entity) {
    final events = [
      ('Golden record status assigned', DateTime.now().subtract(const Duration(hours: 3))),
      ('Attribute conflict resolved: email', DateTime.now().subtract(const Duration(hours: 8))),
      ('Entity merged from duplicate (ent-006)', DateTime.now().subtract(const Duration(days: 1))),
      ('Imported from Workday HR', DateTime.now().subtract(const Duration(days: 3))),
      ('Entity created from Salesforce CRM', DateTime.now().subtract(const Duration(days: 14))),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: events.length,
      separatorBuilder: (_, __) => Container(
        width: 2,
        height: 20,
        margin: const EdgeInsets.only(left: 17),
        color: AppColors.divider,
      ),
      itemBuilder: (context, i) {
        final event = events[i];
        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha:0.5)),
              ),
              child: const Icon(Icons.circle,
                  size: 10, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.$1, style: AppTextStyles.bodyMedium),
                  Text(_formatTime(event.$2),
                      style: AppTextStyles.timestamp),
                ],
              ),
            ),
          ],
        ).animate(delay: (i * 60).ms).fadeIn(duration: 300.ms);
      },
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// Shimmer helper
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const _ShimmerBox({required this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
