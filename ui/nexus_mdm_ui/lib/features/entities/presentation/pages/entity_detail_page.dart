import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/constants/app_constants.dart';
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
import '../../data/relationship_repository.dart';

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
  late final RelationshipRepository _relRepository;
  bool _isLoading = true;
  CanonicalEntity? _entity;

  // Relationships state
  List<EntityRelationshipRecord> _relationships = [];
  bool _relationshipsLoading = false;

  // History state
  List<_HistoryEvent> _historyEvents = [];
  bool _historyLoading = true;
  final Set<String> _dismissedRecs = {};

  // AI Suggestions state
  List<Map<String, dynamic>> _aiSuggestions = [];
  bool _aiSuggestionsLoading = false;
  bool _aiSuggestionTriggering = false;

  @override
  void initState() {
    super.initState();
    _repository = EntityRepository(ApiClient());
    _relRepository = RelationshipRepository(ApiClient());
    _tabController = TabController(
        length: 6, vsync: this,
        initialIndex: widget.showLineage ? 3 : 0);
    _loadEntity();
    _loadRelationships();
    _loadHistory();
    _loadAiSuggestions();
  }

  Future<Options?> _authOpts() async {
    final tenantId = await AuthManager.getTenantId() ?? '';
    if (tenantId.isEmpty) return null;
    return Options(headers: {AppConstants.tenantHeaderKey: tenantId});
  }

  Future<void> _loadAiSuggestions() async {
    if (!mounted) return;
    setState(() => _aiSuggestionsLoading = true);
    try {
      final client = GetIt.instance<ApiClient>();
      final opts = await _authOpts();
      final resp = await client.get<Map<String, dynamic>>(
        '${AppConstants.aiSuggestionsPath}?entity_id=${widget.entityId}',
        options: opts,
      );
      final items = (resp.data?['data'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _aiSuggestions = items.cast<Map<String, dynamic>>();
          _aiSuggestionsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _aiSuggestionsLoading = false);
    }
  }

  Future<void> _triggerAiSuggestion(String type, [Map<String, dynamic>? body]) async {
    setState(() => _aiSuggestionTriggering = true);
    try {
      final client = GetIt.instance<ApiClient>();
      final opts = await _authOpts();
      final path = '${AppConstants.entitiesPath}/${widget.entityId}/ai-suggestions/$type';
      await client.post<Map<String, dynamic>>(path, data: body ?? {}, options: opts);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI analysis queued â€” check back in a moment.')),
        );
        unawaited(_loadAiSuggestions());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to trigger AI suggestion.')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiSuggestionTriggering = false);
    }
  }

  Future<void> _approveAiSuggestion(String suggestionId) async {
    try {
      final client = GetIt.instance<ApiClient>();
      final opts = await _authOpts();
      await client.patch<Map<String, dynamic>>(
        '${AppConstants.aiSuggestionsPath}/$suggestionId/approve',
        options: opts,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggestion approved and applied.')),
        );
        unawaited(_loadAiSuggestions());
        unawaited(_loadEntity());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to approve suggestion.')),
        );
      }
    }
  }

  Future<void> _rejectAiSuggestion(String suggestionId) async {
    try {
      final client = GetIt.instance<ApiClient>();
      final opts = await _authOpts();
      await client.patch<Map<String, dynamic>>(
        '${AppConstants.aiSuggestionsPath}/$suggestionId/reject',
        options: opts,
      );
      if (mounted) {
        setState(() {
          _aiSuggestions.removeWhere((s) => s['id'] == suggestionId);
        });
      }
    } catch (_) {}
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
      if (result case Success<CanonicalEntity>(:final data)) {
        _entity = data;
      }
      // On failure _entity stays null â†’ _buildNotFound shown.
    });
  }

  Future<void> _loadHistory() async {
    final api = ApiClient();
    try {
      final resp = await api.get<Map<String, dynamic>>(
        AppConstants.auditEventsPath,
        queryParameters: {
          'aggregate_type': 'entity',
          'aggregate_id': widget.entityId,
          'page_size': '50',
        },
      );
      if (!mounted) return;
      final items = (resp.data?['items'] as List<dynamic>? ?? []);
      setState(() {
        _historyEvents = items
            .map((e) => _HistoryEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _loadRelationships() async {
    setState(() => _relationshipsLoading = true);
    // tenant_id is injected by the auth interceptor; pass a placeholder here.
    final result = await _relRepository.listForEntity(
      tenantId: '',
      entityId: widget.entityId,
    );
    if (!mounted) return;
    setState(() {
      _relationshipsLoading = false;
      if (result case Success<List<EntityRelationshipRecord>>(:final data)) {
        _relationships = data;
      }
      // On failure keep _relationships empty â€” empty state will show.
    });
  }

  Future<void> _submitForReview(CanonicalEntity entity) async {
    final api = ApiClient();
    try {
      await api.patch<Map<String, dynamic>>(
        '${AppConstants.entitiesPath}/${entity.id}',
        data: {'status': 'PendingReview'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submitted for review.'),
        backgroundColor: Colors.green,
      ));
      _loadEntity();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to submit for review. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
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
                _buildRelationshipsTab(),
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
                        Text('â€¢',
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/dashboard/lineage/${entity.id}'),
                    icon: const Icon(Icons.account_tree_outlined, size: 16),
                    label: const Text('Lineage'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/dashboard/match-queue'),
                    icon: const Icon(Icons.merge_type_rounded, size: 16),
                    label: const Text('Find Matches'),
                  ),
                  if (entity.status == EntityStatus.pending)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                      ),
                      onPressed: () => _submitForReview(entity),
                      icon: const Icon(Icons.rate_review_outlined, size: 16),
                      label: const Text('Submit for Review'),
                    ),
                  ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/dashboard/entities/${_entity!.id}/edit',
                      extra: _entity,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More actions',
                    color: AppColors.surface,
                    onSelected: (v) {
                      final id = _entity!.id;
                      final name = Uri.encodeQueryComponent(entity.displayName);
                      switch (v) {
                        case 'xrefs':     context.push('/dashboard/entities/$id/xrefs');
                        case 'comments':  context.push('/dashboard/entities/$id/comments');
                        case 'history':   context.push('/dashboard/entities/$id/history');
                        case 'hierarchy': context.push('/dashboard/entities/$id/hierarchy?name=$name');
                        case 'unmerge':   context.push('/dashboard/entities/$id/unmerge');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'xrefs',     child: ListTile(leading: Icon(Icons.link_outlined),           title: Text('Cross-References'), dense: true)),
                      PopupMenuItem(value: 'comments',  child: ListTile(leading: Icon(Icons.chat_bubble_outline),     title: Text('Comments'),         dense: true)),
                      PopupMenuItem(value: 'history',   child: ListTile(leading: Icon(Icons.history),                 title: Text('Version History'),  dense: true)),
                      PopupMenuItem(value: 'hierarchy', child: ListTile(leading: Icon(Icons.account_tree_outlined),   title: Text('Hierarchy'),         dense: true)),
                      PopupMenuItem(value: 'unmerge',   child: ListTile(leading: Icon(Icons.call_split_outlined),     title: Text('Unmerge'),          dense: true)),
                    ],
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
          Tab(text: 'Relationships'),
        ],
      ),
    );
  }

  Widget _buildAttributesTab(CanonicalEntity entity) {
    final attrs = entity.attributes.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (attrs.isEmpty) {
      return Center(
        child: Text('No attributes loaded.', style: AppTextStyles.bodySmall),
      );
    }

    final rows = attrs
        .map((a) => (a.displayName, a.name, a.value, a.sourceSystem, a.confidence, a.hasConflict))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${rows.length} attributes from ${entity.sourceSystems.length} sources',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: rows.asMap().entries.map((entry) {
                final i = entry.key;
                return _buildAttributeRow(entry.value, i == rows.length - 1);
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
    final pending = _aiSuggestions.where((s) => s['status'] == 'pending').toList();
    final past    = _aiSuggestions.where((s) => s['status'] != 'pending').toList();

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
                'Generated by Azile AI v2.1 Â· ${DateTime.now().difference(entity.updatedAt).inHours}h ago',
                style: AppTextStyles.timestamp,
              ),
              const Spacer(),
              // Trigger buttons
              if (_aiSuggestionTriggering)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'Request AI analysis',
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  onSelected: (type) {
                    if (type == 'address-parse') {
                      _triggerAiSuggestion('address-parse',
                          {'raw_address_field': 'address'});
                    } else {
                      _triggerAiSuggestion(type);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'address-parse',
                        child: Text('Parse address fields')),
                    PopupMenuItem(value: 'anomaly',
                        child: Text('Detect anomalies')),
                    PopupMenuItem(value: 'enrichment',
                        child: Text('Suggest enrichment')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),

          // â”€â”€ Pending suggestions (require approval) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_aiSuggestionsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pending.isNotEmpty) ...[
            Text('Pending Approval (${pending.length})',
                style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.warning)),
            const SizedBox(height: 8),
            ...pending.map((s) => _buildSuggestionCard(s, isPending: true)),
            const SizedBox(height: 20),
          ],

          // â”€â”€ Static AI summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.aiPurple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.aiPurple.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: AppColors.aiPurple, size: 18),
                    const SizedBox(width: 8),
                    Text('Entity Analysis',
                        style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.aiPurple)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_buildAiSummary(entity), style: AppTextStyles.aiMessage),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 16),

          // Recommendations â€” generated from real entity data
          ..._buildAiRecommendations(entity),

          // â”€â”€ Applied / rejected history â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (past.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Past Suggestions',
                style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.mutedText)),
            const SizedBox(height: 8),
            ...past.map((s) => _buildSuggestionCard(s, isPending: false)),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> s, {required bool isPending}) {
    final type       = s['suggestion_type'] as String? ?? '';
    final status     = s['status']          as String? ?? '';
    final rationale  = s['rationale']       as String? ?? '';
    final confidence = (s['confidence']     as num?)?.toDouble() ?? 0.0;
    final id         = s['id']              as String? ?? '';
    final items      = (s['suggestion'] as List<dynamic>?) ?? [];

    final typeLabel = switch (type) {
      'address_parse' => 'Address Parse',
      'anomaly'       => 'Anomaly Detection',
      'enrichment'    => 'Enrichment',
      _               => type,
    };
    final statusColor = switch (status) {
      'pending'  => AppColors.warning,
      'applied'  => AppColors.success,
      'rejected' => AppColors.mutedText,
      _          => AppColors.mutedText,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined,
                  color: AppColors.aiPurple, size: 16),
              const SizedBox(width: 6),
              Text(typeLabel, style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status,
                    style: AppTextStyles.timestamp.copyWith(color: statusColor)),
              ),
              const SizedBox(width: 8),
              Text('${(confidence * 100).round()}% confidence',
                  style: AppTextStyles.timestamp),
            ],
          ),
          if (rationale.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(rationale, style: AppTextStyles.bodySmall),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...items.take(5).map((item) {
              final field = (item as Map<String, dynamic>)['field'] as String? ?? '';
              final val   = item['proposed_value'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Text('$field: ', style: AppTextStyles.timestamp),
                    Expanded(
                      child: Text(val,
                          style: AppTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (isPending && id.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _rejectAiSuggestion(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _approveAiSuggestion(id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Approve & Apply'),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  List<Widget> _buildAiRecommendations(CanonicalEntity entity) {
    final cards = <Widget>[];

    void add(String key, Widget w) {
      if (_dismissedRecs.contains(key)) return;
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 12));
      cards.add(w);
    }

    // Conflict recommendations â€” one card per conflicted attribute (max 3)
    final conflictedAttrs = entity.attributes.values
        .where((a) => a.hasConflict)
        .take(3)
        .toList();
    for (final attr in conflictedAttrs) {
      final key = 'Resolve ${attr.displayName} Conflict';
      final sources = attr.conflicts.isNotEmpty
          ? attr.conflicts.map((c) => c.sourceSystem).join(' vs ')
          : 'multiple sources';
      add(key, _buildAiRecommendationCard(
        key,
        'Conflicting values detected from $sources. Review and designate the authoritative value to improve record quality.',
        Icons.compare_arrows_outlined,
        AppColors.warning,
        'Conflict',
        onTakeAction: () => _tabController.animateTo(2),
        onDismiss: () => setState(() => _dismissedRecs.add(key)),
      ));
    }

    // Duplicates
    if (entity.duplicateCount > 0) {
      final n = entity.duplicateCount;
      final key = '$n Potential Duplicate${n == 1 ? '' : 's'} Detected';
      add(key, _buildAiRecommendationCard(
        key,
        '$n entr${n == 1 ? 'y' : 'ies'} share high attribute similarity with this record. Review match candidates to merge or dismiss.',
        Icons.copy_outlined,
        AppColors.error,
        '$n match${n == 1 ? '' : 'es'}',
        onTakeAction: () => context.go('/dashboard/match-queue'),
        onDismiss: () => setState(() => _dismissedRecs.add(key)),
      ));
    }

    // Low trust score (only if no conflicts to avoid redundant quality message)
    if (entity.trustScore < 0.75 && conflictedAttrs.isEmpty) {
      final score = (entity.trustScore * 100).round();
      const key = 'Data Quality Below Threshold';
      add(key, _buildAiRecommendationCard(
        key,
        'Trust score of $score% is below the recommended 75%. Connect additional verified source systems or resolve attribute conflicts to improve confidence.',
        Icons.verified_outlined,
        AppColors.info,
        '$score% trust',
        onDismiss: () => setState(() => _dismissedRecs.add(key)),
      ));
    }

    // Single source (only when record is otherwise healthy)
    if (entity.sourceSystems.length == 1 && cards.isEmpty) {
      const key = 'Single Source System';
      add(key, _buildAiRecommendationCard(
        key,
        'This entity is sourced only from ${entity.primarySource}. Connecting additional source systems enables cross-validation and increases data confidence.',
        Icons.device_hub_outlined,
        AppColors.info,
        'Optional',
        onDismiss: () => setState(() => _dismissedRecs.add(key)),
      ));
    }

    // Healthy â€” no issues found
    if (cards.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No recommendations â€” this record looks healthy.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.success),
                ),
              ),
            ],
          ),
        ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
      ];
    }

    return cards;
  }

  Widget _buildAiRecommendationCard(
    String title,
    String description,
    IconData icon,
    Color color,
    String badge, {
    VoidCallback? onTakeAction,
    VoidCallback? onDismiss,
  }) {
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
                    if (onTakeAction != null)
                      OutlinedButton(
                        onPressed: onTakeAction,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 28),
                          textStyle: AppTextStyles.buttonSmall,
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                        ),
                        child: const Text('Take Action'),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onDismiss,
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

    final conflicted = entity.attributes.values
        .where((a) => a.hasConflict && a.conflicts.isNotEmpty)
        .toList();

    if (conflicted.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 36, color: AppColors.primary),
            ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
            const SizedBox(height: 16),
            Text('No conflicts detected', style: AppTextStyles.titleMedium)
                .animate(delay: 100.ms).fadeIn(),
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
        children: conflicted.asMap().entries.map((entry) {
          final i = entry.key;
          final attr = entry.value;
          final values = [
            (attr.sourceSystem, attr.value.toString(), attr.confidence),
            ...attr.conflicts.map((c) => (c.sourceSystem, c.value.toString(), c.confidence)),
          ];
          return Column(
            children: [
              if (i > 0) const SizedBox(height: 12),
              _buildConflictItem(
                attr.displayName,
                '${values.length} different values across source systems.',
                values,
                onResolve: (chosenValue) =>
                    _resolveConflict(entity.id, attr.name, chosenValue),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _resolveConflict(
      String entityId, String attrKey, String chosenValue) async {
    final api = ApiClient();
    try {
      await api.patch<Map<String, dynamic>>(
        '${AppConstants.entitiesPath}/$entityId',
        data: {
          'attributes': [
            {'key': attrKey, 'value': chosenValue},
          ],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Conflict resolved.'),
        backgroundColor: Colors.green,
      ));
      _loadEntity();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to resolve conflict. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Widget _buildConflictItem(
    String field,
    String description,
    List<(String, String, double)> values, {
    void Function(String value)? onResolve,
  }) {
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
                      onPressed:
                          onResolve != null ? () => onResolve(v.$2) : null,
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
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 48, color: AppColors.mutedText),
            const SizedBox(height: 12),
            Text('No history yet', style: AppTextStyles.titleSmall),
            const SizedBox(height: 6),
            Text('Events will appear here as changes are made.',
                style: AppTextStyles.bodySmall),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _historyEvents.length,
      separatorBuilder: (_, __) => Container(
        width: 2,
        height: 20,
        margin: const EdgeInsets.only(left: 17),
        color: AppColors.divider,
      ),
      itemBuilder: (context, i) {
        final event = _historyEvents[i];
        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.circle, size: 10, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.label, style: AppTextStyles.bodyMedium),
                  Text(_formatTime(event.timestamp), style: AppTextStyles.timestamp),
                ],
              ),
            ),
          ],
        ).animate(delay: (i * 60).ms).fadeIn(duration: 300.ms);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Relationships tab
  // ---------------------------------------------------------------------------

  static const Map<String, Color> _entityTypeColors = {
    'CUSTOMER':     AppColors.primary,
    'VENDOR':       AppColors.warning,
    'MATERIAL':     Color(0xFFFF6B35), // deep orange
    'PRODUCT':      AppColors.success,
    'ACCOUNT':      Color(0xFF00BCD4), // teal
    'EMPLOYEE':     AppColors.aiPurple,
    'LOCATION':     Color(0xFF26A69A), // teal-green
    'ORGANIZATION': Color(0xFFFFB800), // amber
    'ASSET':        AppColors.mutedText,
    'PERSON':       AppColors.primary,
  };

  Color _colorForType(String type) =>
      _entityTypeColors[type.toUpperCase()] ?? AppColors.secondaryText;

  Widget _buildRelationshipsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _buildRelationshipsSection(),
    );
  }

  Widget _buildRelationshipsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Header row ----
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Cross-Domain Relationships', style: AppTextStyles.titleMedium),
            const SizedBox(width: 10),
            if (!_relationshipsLoading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_relationships.length}',
                  style: AppTextStyles.badgeLabel
                      .copyWith(color: AppColors.primary),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Add relationship',
              icon: const Icon(Icons.add_circle_outline,
                  color: AppColors.primary, size: 22),
              onPressed: () => _showAddRelationshipDialog(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ---- Body ----
        if (_relationshipsLoading)
          _buildRelationshipsShimmer()
        else if (_relationships.isEmpty)
          _buildRelationshipsEmpty()
        else
          _buildRelationshipsList(),
      ],
    );
  }

  Widget _buildRelationshipsShimmer() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.elevatedCard,
              borderRadius: BorderRadius.circular(10),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 1200.ms, color: AppColors.divider),
        ),
      ),
    );
  }

  Widget _buildRelationshipsEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hub_outlined,
                size: 28, color: AppColors.primary),
          ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
          const SizedBox(height: 14),
          Text('No relationships yet',
              style: AppTextStyles.titleSmall)
              .animate(delay: 80.ms).fadeIn(),
          const SizedBox(height: 6),
          Text(
            'Connect this entity to others across domains.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ).animate(delay: 120.ms).fadeIn(),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showAddRelationshipDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Relationship'),
          ).animate(delay: 160.ms).fadeIn(),
        ],
      ),
    );
  }

  Widget _buildRelationshipsList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: _relationships.asMap().entries.map((entry) {
          final i = entry.key;
          final rel = entry.value;
          final isLast = i == _relationships.length - 1;
          return _buildRelationshipRow(rel, isLast, i);
        }).toList(),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildRelationshipRow(
      EntityRelationshipRecord rel, bool isLast, int index) {
    final otherType = rel.otherEntityType();
    final otherId = rel.otherEntityId(widget.entityId);
    final truncatedId =
        otherId.length > 8 ? '${otherId.substring(0, 8)}â€¦' : otherId;
    final typeColor = _colorForType(otherType);

    IconData directionIcon;
    String directionTooltip;
    if (rel.isFromEntity) {
      directionIcon = Icons.arrow_forward_rounded;
      directionTooltip = 'Outgoing';
    } else {
      directionIcon = Icons.arrow_back_rounded;
      directionTooltip = 'Incoming';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          // Direction icon
          Tooltip(
            message: directionTooltip,
            child: Icon(directionIcon,
                size: 16, color: AppColors.secondaryText),
          ),
          const SizedBox(width: 10),

          // Relationship type name
          Expanded(
            flex: 3,
            child: Text(
              rel.typeDisplayName.isNotEmpty
                  ? rel.typeDisplayName
                  : rel.typeName,
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),

          // Target entity ID (truncated, monospace)
          Expanded(
            flex: 2,
            child: Text(
              truncatedId,
              style: AppTextStyles.codeStyle.copyWith(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),

          // Entity type chip with colored dot
          if (otherType.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: typeColor.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: typeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    otherType,
                    style: AppTextStyles.badgeLabel
                        .copyWith(color: typeColor),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),

          // Strength bar (only when < 1.0)
          if (rel.strength < 1.0) ...[
            SizedBox(
              width: 56,
              child: TrustScoreBar(
                score: rel.strength,
                height: 4,
                showPercentage: false,
                animate: false,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(rel.strength * 100).round()}%',
              style: AppTextStyles.timestamp,
            ),
            const SizedBox(width: 6),
          ],

          // Delete button
          IconButton(
            tooltip: 'Remove relationship',
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.mutedText),
            constraints: const BoxConstraints(
                minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _confirmDeleteRelationship(rel),
          ),
        ],
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 300.ms);
  }

  // ---------------------------------------------------------------------------
  // Add relationship dialog
  // ---------------------------------------------------------------------------

  Future<void> _showAddRelationshipDialog() async {
    List<RelationshipType> types = [];
    String? selectedTypeId;
    final targetController = TextEditingController();
    double strength = 1.0;
    bool isCreating = false;
    String? errorMessage;

    // Eagerly fetch types inside the dialog so we can show a loader.
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Load types once on first build.
            if (types.isEmpty && !isCreating) {
              _relRepository
                  .listTypes(tenantId: '')
                  .then((result) {
                if (result case Success<List<RelationshipType>>(:final data)) {
                  setDialogState(() => types = data);
                }
              });
            }

            return Dialog(
              backgroundColor: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          const Icon(Icons.hub_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Text('Add Relationship',
                              style: AppTextStyles.titleMedium),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18,
                                color: AppColors.secondaryText),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Relationship type dropdown
                      Text('Relationship Type',
                          style: AppTextStyles.labelMedium),
                      const SizedBox(height: 8),
                      types.isEmpty
                          ? Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.elevatedCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.divider),
                              ),
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: selectedTypeId,
                              dropdownColor: AppColors.elevatedCard,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.elevatedCard,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.divider),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.divider),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                hintText: 'Select a typeâ€¦',
                                hintStyle: AppTextStyles.inputHint,
                              ),
                              items: types
                                  .map((t) => DropdownMenuItem(
                                        value: t.typeId,
                                        child: Text(t.displayName,
                                            style:
                                                AppTextStyles.bodyMedium),
                                      ))
                                  .toList(),
                              onChanged: (v) => setDialogState(
                                  () => selectedTypeId = v),
                            ),
                      const SizedBox(height: 16),

                      // Target entity ID field
                      Text('Target Entity ID',
                          style: AppTextStyles.labelMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: targetController,
                        style: AppTextStyles.inputText,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.elevatedCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.divider),
                          ),
                          hintText: 'e.g. ent-00123â€¦',
                          hintStyle: AppTextStyles.inputHint,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Strength slider
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Strength',
                              style: AppTextStyles.labelMedium),
                          Text(
                            '${(strength * 100).round()}%',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor:
                              AppColors.primary.withValues(alpha: 0.2),
                          thumbColor: AppColors.primary,
                          overlayColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: strength,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          onChanged: (v) =>
                              setDialogState(() => strength = v),
                        ),
                      ),

                      // Error message
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.error),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: isCreating
                                ? null
                                : () async {
                                    final typeId = selectedTypeId;
                                    final toId =
                                        targetController.text.trim();
                                    if (typeId == null) {
                                      setDialogState(() =>
                                          errorMessage =
                                              'Please select a relationship type.');
                                      return;
                                    }
                                    if (toId.isEmpty) {
                                      setDialogState(() =>
                                          errorMessage =
                                              'Please enter a target entity ID.');
                                      return;
                                    }
                                    setDialogState(() {
                                      isCreating = true;
                                      errorMessage = null;
                                    });
                                    final result =
                                        await _relRepository.create(
                                      tenantId: '',
                                      entityId: widget.entityId,
                                      typeId: typeId,
                                      toEntityId: toId,
                                      strength: strength,
                                    );
                                    if (!ctx.mounted) return;
                                    if (result is Failure) {
                                      setDialogState(() {
                                        isCreating = false;
                                        errorMessage =
                                            'Failed to create relationship.';
                                      });
                                    } else {
                                      Navigator.of(ctx).pop();
                                      _loadRelationships();
                                    }
                                  },
                            icon: isCreating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.add, size: 16),
                            label: const Text('Create'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    targetController.dispose();
  }

  Future<void> _confirmDeleteRelationship(
      EntityRelationshipRecord rel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: Text('Remove Relationship',
            style: AppTextStyles.titleSmall),
        content: Text(
          'Remove the "${rel.typeDisplayName.isNotEmpty ? rel.typeDisplayName : rel.typeName}" '
          'relationship? This cannot be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final result = await _relRepository.delete(
      tenantId: '',
      relationshipId: rel.relationshipId,
    );
    if (!mounted) return;
    if (result is Success) {
      setState(() =>
          _relationships.removeWhere(
              (r) => r.relationshipId == rel.relationshipId));
    }
  }

  // ---------------------------------------------------------------------------

  String _buildAiSummary(CanonicalEntity entity) {
    final score = (entity.trustScore * 100).round();
    final sources = entity.sourceSystems.length;
    final conflictCount = entity.attributes.values.where((a) => a.hasConflict).length;

    final base = 'Trust score of $score% reflects data consistency across $sources connected source system${sources == 1 ? '' : 's'}.';

    if (conflictCount == 0) {
      return '$base All attribute values are consistent â€” no conflicts detected.';
    }

    final conflictedFields = entity.attributes.values
        .where((a) => a.hasConflict)
        .map((a) => a.displayName)
        .take(3)
        .join(', ');

    return '$base $conflictCount attribute${conflictCount == 1 ? '' : 's'} have conflicting values across sources ($conflictedFields). Review and resolve to improve record quality.';
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class _HistoryEvent {
  final String eventType;
  final DateTime timestamp;

  const _HistoryEvent({required this.eventType, required this.timestamp});

  factory _HistoryEvent.fromJson(Map<String, dynamic> json) {
    return _HistoryEvent(
      eventType: json['event_type'] as String? ?? 'Unknown event',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get label {
    // Convert snake_case event type to a readable sentence.
    return eventType
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
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
