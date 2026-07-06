import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/ai_badge.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../data/match_queue_repository.dart';
import '../../../admin/data/entity_type_repository.dart';

class MatchQueuePage extends StatefulWidget {
  final String? reviewId;
  final bool mergeMode;

  const MatchQueuePage({
    super.key,
    this.reviewId,
    this.mergeMode = false,
  });

  @override
  State<MatchQueuePage> createState() => _MatchQueuePageState();
}

class _MatchQueuePageState extends State<MatchQueuePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final MatchQueueRepository _repo;

  late final EntityTypeRepository _entityTypeRepo;
  bool _isLoading = true;
  List<ReviewItem> _allItems = [];
  QueueMetrics? _metrics;
  final Set<String> _selectedIds = {};
  String _activeTab = 'all';
  String? _selectedDomain; // null means "All"
  List<String> _domainOptions = [];
  List<String>? _stewardEntityTypes; // null = no restriction

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final api = ApiClient();
    _repo = MatchQueueRepository(client: api);
    _entityTypeRepo = EntityTypeRepository(api);
    _initStewardScopeAndLoad();
  }

  Future<void> _initStewardScopeAndLoad() async {
    final role = await AuthManager.getUserRole();
    if (role?.toLowerCase() == 'steward') {
      final types = await AuthManager.getAssignedEntityTypes();
      if (mounted) {
        setState(() {
          _stewardEntityTypes = types;
          if (types.length == 1) _selectedDomain = types.first;
        });
      }
    }
    _loadEntityTypes();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadEntityTypes() async {
    final tenantId = await _resolveTenantId();
    final result = await _entityTypeRepo.listEntityTypes(tenantId);
    if (!mounted) return;
    if (result case Success<List<EntityTypeModel>>(:final data)) {
      var options = data.map((e) => e.code).toList();
      if (_stewardEntityTypes != null && _stewardEntityTypes!.isNotEmpty) {
        final allowed = _stewardEntityTypes!.map((t) => t.toLowerCase()).toSet();
        options = options
            .where((o) => allowed.contains(o.toLowerCase()))
            .toList();
      }
      setState(() => _domainOptions = options);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final tenantId = await _resolveTenantId();

    // Enforce steward scope: if no domain explicitly chosen and steward has
    // exactly one type, pass it so the backend never returns out-of-scope items.
    final effectiveDomain = _selectedDomain ??
        (_stewardEntityTypes?.length == 1
            ? _stewardEntityTypes!.first
            : null);

    // Fire both calls in parallel.
    final results = await Future.wait([
      _repo.getQueueMetrics(tenantId: tenantId),
      _repo.listQueue(
        tenantId: tenantId,
        entityType: effectiveDomain,
      ),
    ]);

    if (!mounted) return;

    final metricsResult = results[0] as ApiResult<QueueMetrics>;
    final queueResult = results[1] as ApiResult<List<ReviewItem>>;

    setState(() {
      _isLoading = false;
      if (metricsResult case Success<QueueMetrics>(:final data)) {
        _metrics = data;
      }
      if (queueResult case Success<List<ReviewItem>>(:final data)) {
        _allItems = data;
      } else if (queueResult case Failure<List<ReviewItem>>()) {
        // Keep list empty; no crash.
        _allItems = [];
      }
    });
  }

  Future<String> _resolveTenantId() async {
    try {
      final id = await AuthManager.getTenantId();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return 'default';
  }

  // ---------------------------------------------------------------------------
  // Derived lists
  // ---------------------------------------------------------------------------

  List<ReviewItem> get _filteredItems {
    // Safety net for multi-type stewards when domain is "All":
    // backend has no multi-type param so we filter client-side.
    var items = _allItems;
    if (_stewardEntityTypes != null &&
        _stewardEntityTypes!.length > 1 &&
        _selectedDomain == null) {
      final allowed =
          _stewardEntityTypes!.map((t) => t.toLowerCase()).toSet();
      items = items
          .where((c) => allowed.contains(c.entityType.toLowerCase()))
          .toList();
    }

    switch (_activeTab) {
      case 'critical':
        return items
            .where((c) => c.priority.toLowerCase() == 'critical')
            .toList();
      case 'high':
        return items
            .where((c) => c.priority.toLowerCase() == 'high')
            .toList();
      case 'normal':
        return items
            .where((c) =>
                c.priority.toLowerCase() == 'normal' ||
                c.priority.toLowerCase() == 'low')
            .toList();
      default:
        return List<ReviewItem>.from(items);
    }
  }

  int get _pendingCount => _metrics?.pendingTotal ?? _allItems.length;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          if (_metrics != null) _buildMetricsBanner(),
          _buildTabBar(),
          if (_selectedIds.isNotEmpty) _buildBulkActionBar(),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _filteredItems.isEmpty
                    ? const EmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'Queue is clear!',
                        description:
                            'All match candidates have been reviewed. Great work!',
                      )
                    : _buildItemList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_pendingCount pending reviews',
                style: AppTextStyles.headlineSmall,
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 4),
              Text(
                'Sorted by confidence score · AI-powered recommendations',
                style: AppTextStyles.bodySmall,
              ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
            ],
          ),
          const Spacer(),
          // Domain dropdown
          _buildDomainDropdown(),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.filter_list_rounded, size: 16),
            label: const Text('Refresh'),
          ).animate(delay: 200.ms).fadeIn(),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _selectedIds.isNotEmpty ? _bulkApprove : null,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Approve All High'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ).animate(delay: 250.ms).fadeIn(),
        ],
      ),
    );
  }

  Widget _buildDomainDropdown() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _selectedDomain != null
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _selectedDomain != null
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedDomain,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Domain',
              style: AppTextStyles.labelMedium
                  .copyWith(color: AppColors.secondaryText),
            ),
          ),
          dropdownColor: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(8),
          icon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: _selectedDomain != null
                  ? AppColors.primary
                  : AppColors.secondaryText,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _selectedDomain = value;
              _selectedIds.clear();
            });
            _loadData();
          },
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('All Domains',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primaryText)),
              ),
            ),
            ..._domainOptions.map(
              (domain) => DropdownMenuItem<String?>(
                value: domain,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(domain,
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.primaryText)),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: 150.ms).fadeIn();
  }

  // ---------------------------------------------------------------------------
  // Metrics banner
  // ---------------------------------------------------------------------------

  Widget _buildMetricsBanner() {
    final m = _metrics!;
    final hasSla = m.slaBreached > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasSla
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          _metricChip(
            label: 'Pending',
            value: '${m.pendingTotal}',
            color: AppColors.primary,
          ),
          const SizedBox(width: 16),
          _metricChip(
            label: 'Avg Age',
            value: '${m.avgAgeHours.toStringAsFixed(1)}h',
            color: AppColors.secondaryText,
          ),
          if (hasSla) ...[
            const SizedBox(width: 16),
            _metricChip(
              label: 'SLA Breached',
              value: '${m.slaBreached}',
              color: AppColors.error,
              icon: Icons.warning_amber_rounded,
            ),
          ],
          const Spacer(),
          ...m.pendingByPriority.entries
              .where((e) => e.value > 0)
              .map((e) => Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _metricChip(
                      label: _capitalized(e.key),
                      value: '${e.value}',
                      color: _priorityColor(e.key),
                    ),
                  )),
        ],
      ),
    ).animate(delay: 50.ms).fadeIn(duration: 350.ms);
  }

  Widget _metricChip({
    required String label,
    required String value,
    required Color color,
    IconData? icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          '$label: ',
          style: AppTextStyles.labelSmall
              .copyWith(color: AppColors.secondaryText),
        ),
        Text(
          value,
          style: AppTextStyles.labelMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab bar
  // ---------------------------------------------------------------------------

  Widget _buildTabBar() {
    final counts = [
      _allItems.length,
      _allItems.where((c) => c.priority.toLowerCase() == 'critical').length,
      _allItems.where((c) => c.priority.toLowerCase() == 'high').length,
      _allItems
          .where((c) =>
              c.priority.toLowerCase() == 'normal' ||
              c.priority.toLowerCase() == 'low')
          .length,
    ];
    final tabs = [
      ('All', 'all', counts[0]),
      ('Critical', 'critical', counts[1]),
      ('High', 'high', counts[2]),
      ('Normal', 'normal', counts[3]),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: tabs.map((tab) {
          final isActive = _activeTab == tab.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _activeTab = tab.$2),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      tab.$1,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.secondaryText,
                      ),
                    ),
                    if (tab.$3 > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${tab.$3}',
                          style: AppTextStyles.badgeLabel.copyWith(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bulk action bar
  // ---------------------------------------------------------------------------

  Widget _buildBulkActionBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedIds.length} selected',
            style:
                AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _bulkApprove,
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Merge All'),
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTextStyles.buttonSmall,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _bulkReject,
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Reject All'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTextStyles.buttonSmall,
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // List
  // ---------------------------------------------------------------------------

  Widget _buildLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _MatchCardShimmer(),
    );
  }

  Widget _buildItemList() {
    final items = _filteredItems;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _buildMatchCard(items[i], i)
          .animate(delay: (i * 80).ms)
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.05, end: 0, duration: 400.ms),
    );
  }

  // ---------------------------------------------------------------------------
  // Match card
  // ---------------------------------------------------------------------------

  Widget _buildMatchCard(ReviewItem item, int index) {
    final isSelected = _selectedIds.contains(item.candidateId);
    final priority = item.priority.toLowerCase();
    final slaBreached = item.isSlaBreached;

    return GestureDetector(
      onTap: () => _showMatchDetail(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.4)
                : _getPriorityBorderColor(priority),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(item.candidateId);
                        } else {
                          _selectedIds.remove(item.candidateId);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            PriorityBadge(
                              priority: _capitalized(item.priority),
                            ),
                            const SizedBox(width: 8),
                            // SLA breach badge
                            if (slaBreached)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.error
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 10, color: AppColors.error),
                                    const SizedBox(width: 3),
                                    Text(
                                      'SLA',
                                      style: AppTextStyles.badgeLabel
                                          .copyWith(color: AppColors.error),
                                    ),
                                  ],
                                ),
                              ),
                            if (item.aiExplanation != null) ...[
                              const SizedBox(width: 8),
                              AiBadge(
                                label: 'AI',
                                confidence: item.overallScore,
                                compact: false,
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _timeAgo(item.createdAt),
                              style: AppTextStyles.timestamp,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Entity chips
                        Row(
                          children: [
                            Expanded(
                              child: _buildEntityChip(
                                item.sourceEntityName,
                                item.requestId,
                                Icons.hub_rounded,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                children: [
                                  Icon(Icons.compare_arrows_rounded,
                                      color: AppColors.primary, size: 20),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _buildEntityChip(
                                item.targetEntityName,
                                item.candidateId,
                                Icons.hub_outlined,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Score bar
              Row(
                children: [
                  Text('Match Score', style: AppTextStyles.labelSmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: item.overallScore.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getScoreColor(item.overallScore)
                                      .withValues(alpha: 0.7),
                                  _getScoreColor(item.overallScore),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: _getScoreColor(item.overallScore)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(item.overallScore * 100).round()}%',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: _getScoreColor(item.overallScore),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Field match chips
              if (item.fieldMatches.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: item.fieldMatches.take(4).map((fm) {
                    final isExact = fm.score >= 0.999;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getFieldMatchColor(fm.score)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _getFieldMatchColor(fm.score)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isExact
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                            size: 12,
                            color: _getFieldMatchColor(fm.score),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _capitalized(fm.field),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: _getFieldMatchColor(fm.score),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(fm.score * 100).round()}%',
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: _getFieldMatchColor(fm.score),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

              if (item.fieldMatches.isNotEmpty) const SizedBox(height: 12),

              // AI explanation
              if (item.aiExplanation != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.aiPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.aiPurple.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 14, color: AppColors.aiPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.aiExplanation!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondaryText,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              if (item.aiExplanation != null) const SizedBox(height: 12),

              const SizedBox(height: 4),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveItem(item),
                      icon:
                          const Icon(Icons.merge_type_rounded, size: 16),
                      label: const Text('Merge'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectItem(item),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Not a Dup'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _deferItem(item),
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: const Text('Defer'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      textStyle: AppTextStyles.buttonSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showMatchDetail(item),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    tooltip: 'View full detail',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.elevatedCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntityChip(String name, String id, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  id,
                  style: AppTextStyles.timestamp,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color helpers
  // ---------------------------------------------------------------------------

  Color _getPriorityBorderColor(String priority) {
    switch (priority) {
      case 'critical':
        return AppColors.error.withValues(alpha: 0.3);
      case 'high':
        return AppColors.warning.withValues(alpha: 0.3);
      default:
        return AppColors.divider;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return AppColors.error;
      case 'high':
        return AppColors.warning;
      default:
        return AppColors.secondaryText;
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 0.85) return AppColors.primary;
    if (score >= 0.65) return AppColors.warning;
    return AppColors.error;
  }

  Color _getFieldMatchColor(double similarity) {
    if (similarity >= 0.9) return AppColors.primary;
    if (similarity >= 0.7) return AppColors.warning;
    return AppColors.error;
  }

  // ---------------------------------------------------------------------------
  // Action handlers
  // ---------------------------------------------------------------------------

  Future<void> _approveItem(ReviewItem item) async {
    // Optimistic remove
    setState(() {
      _allItems = _allItems.where((c) => c.candidateId != item.candidateId).toList();
      _selectedIds.remove(item.candidateId);
    });

    final tenantId = await _resolveTenantId();
    final result = await _repo.approve(
      tenantId: tenantId,
      requestId: item.requestId,
      candidateId: item.candidateId,
    );

    if (!mounted) return;

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item.sourceEntityName} merged with ${item.targetEntityName}',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => setState(() => _allItems.add(item)),
            ),
          ),
        );
      case Failure(:final exception):
        // Revert
        setState(() => _allItems.add(item));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merge failed: ${exception.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  Future<void> _rejectItem(ReviewItem item) async {
    // Optimistic remove
    setState(() {
      _allItems = _allItems.where((c) => c.candidateId != item.candidateId).toList();
      _selectedIds.remove(item.candidateId);
    });

    final tenantId = await _resolveTenantId();
    final result = await _repo.reject(
      tenantId: tenantId,
      requestId: item.requestId,
      candidateId: item.candidateId,
    );

    if (!mounted) return;

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marked as not a duplicate'),
            backgroundColor: AppColors.elevatedCard,
          ),
        );
      case Failure(:final exception):
        setState(() => _allItems.add(item));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reject failed: ${exception.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  Future<void> _deferItem(ReviewItem item) async {
    final tenantId = await _resolveTenantId();
    final result = await _repo.defer(
      tenantId: tenantId,
      requestId: item.requestId,
      candidateId: item.candidateId,
    );

    if (!mounted) return;

    switch (result) {
      case Success():
        setState(() {
          _allItems = _allItems
              .where((c) => c.candidateId != item.candidateId)
              .toList();
          _selectedIds.remove(item.candidateId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${item.sourceEntityName} deferred for later review'),
          ),
        );
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Defer failed: ${exception.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  Future<void> _bulkApprove() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final removed = _allItems
        .where((c) => _selectedIds.contains(c.candidateId))
        .toList();

    // Optimistic update
    setState(() {
      _allItems = _allItems
          .where((c) => !_selectedIds.contains(c.candidateId))
          .toList();
      _selectedIds.clear();
    });

    final tenantId = await _resolveTenantId();
    final result =
        await _repo.bulkApprove(tenantId: tenantId, candidateIds: ids);

    if (!mounted) return;

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} matches merged successfully'),
          ),
        );
      case Failure(:final exception):
        // Revert
        setState(() => _allItems.addAll(removed));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk merge failed: ${exception.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  Future<void> _bulkReject() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final removed = _allItems
        .where((c) => _selectedIds.contains(c.candidateId))
        .toList();

    setState(() {
      _allItems = _allItems
          .where((c) => !_selectedIds.contains(c.candidateId))
          .toList();
      _selectedIds.clear();
    });

    final tenantId = await _resolveTenantId();
    final result =
        await _repo.bulkReject(tenantId: tenantId, candidateIds: ids);

    if (!mounted) return;

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${ids.length} candidates marked as not duplicates'),
            backgroundColor: AppColors.elevatedCard,
          ),
        );
      case Failure(:final exception):
        setState(() => _allItems.addAll(removed));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk reject failed: ${exception.message}'),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  void _showMatchDetail(ReviewItem item) {
    showDialog(
      context: context,
      builder: (context) => _ReviewItemDetailDialog(item: item),
    );
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  String _capitalized(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ---------------------------------------------------------------------------
// Detail dialog (adapted for ReviewItem)
// ---------------------------------------------------------------------------

class _ReviewItemDetailDialog extends StatelessWidget {
  final ReviewItem item;

  const _ReviewItemDetailDialog({required this.item});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Match Review', style: AppTextStyles.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${item.sourceEntityName} ↔ ${item.targetEntityName}',
                style: AppTextStyles.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Overall score: ${(item.overallScore * 100).round()}%'
                '${item.entityType.isNotEmpty ? " \xb7 ${item.entityType}" : ""}',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: item.fieldMatches.isEmpty
                    ? Center(
                        child: Text(
                          'No field-level breakdown available.',
                          style: AppTextStyles.bodySmall,
                        ),
                      )
                    : ListView(
                        children:
                            item.fieldMatches.map((fm) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.navyBackground,
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.divider),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      _cap(fm.field),
                                      style:
                                          AppTextStyles.labelMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(fm.sourceValue,
                                            style: AppTextStyles
                                                .bodySmall
                                                .copyWith(
                                                    color: AppColors
                                                        .primaryText)),
                                        Text(fm.targetValue,
                                            style: AppTextStyles
                                                .bodySmall),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4),
                                    decoration: BoxDecoration(
                                      color: fm.score >= 0.9
                                          ? AppColors.primary
                                              .withValues(alpha: 0.1)
                                          : AppColors.warning
                                              .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${(fm.score * 100).round()}%',
                                      style: AppTextStyles.labelMedium
                                          .copyWith(
                                        color: fm.score >= 0.9
                                            ? AppColors.primary
                                            : AppColors.warning,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side:
                          const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('Not a Duplicate'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.merge_type_rounded,
                        size: 16),
                    label: const Text('Confirm Merge'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Shimmer placeholder
// ---------------------------------------------------------------------------

class _MatchCardShimmer extends StatelessWidget {
  const _MatchCardShimmer();

  @override
  Widget build(BuildContext context) {
    return LoadingShimmer(
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
