import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/match_candidate.dart';
import '../../../../shared/widgets/ai_badge.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/status_badge.dart';

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
  bool _isLoading = true;
  List<MatchCandidate> _allCandidates = [];
  final Set<String> _selectedIds = {};
  String _activeTab = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCandidates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _allCandidates = MatchCandidate.demoList;
    });
  }

  List<MatchCandidate> get _filteredCandidates {
    switch (_activeTab) {
      case 'critical':
        return _allCandidates
            .where((c) => c.priority == MatchPriority.critical)
            .toList();
      case 'high':
        return _allCandidates
            .where((c) => c.priority == MatchPriority.high)
            .toList();
      case 'normal':
        return _allCandidates
            .where((c) =>
                c.priority == MatchPriority.normal ||
                c.priority == MatchPriority.low)
            .toList();
      default:
        return _allCandidates
            .where((c) => c.decision == MatchDecision.pending)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          if (_selectedIds.isNotEmpty) _buildBulkActionBar(),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _filteredCandidates.isEmpty
                    ? const EmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'Queue is clear!',
                        description:
                            'All match candidates have been reviewed. Great work!',
                      )
                    : _buildCandidateList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_allCandidates.where((c) => c.isPending).length} pending reviews',
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
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.filter_list_rounded, size: 16),
            label: const Text('Filter'),
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

  Widget _buildTabBar() {
    final counts = [
      _allCandidates.where((c) => c.isPending).length,
      _allCandidates.where((c) => c.priority == MatchPriority.critical).length,
      _allCandidates.where((c) => c.priority == MatchPriority.high).length,
      _allCandidates
          .where((c) =>
              c.priority == MatchPriority.normal ||
              c.priority == MatchPriority.low)
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
                      ? AppColors.primary.withValues(alpha:0.12)
                      : AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary.withValues(alpha:0.4)
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
                              ? AppColors.primary.withValues(alpha:0.2)
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

  Widget _buildBulkActionBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedIds.length} selected',
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _bulkApprove,
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Merge All'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTextStyles.buttonSmall,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _bulkReject,
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Reject All'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _MatchCardShimmer(),
    );
  }

  Widget _buildCandidateList() {
    final candidates = _filteredCandidates;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          _buildMatchCard(candidates[i], i).animate(
            delay: (i * 80).ms,
          ).fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0, duration: 400.ms),
    );
  }

  Widget _buildMatchCard(MatchCandidate candidate, int index) {
    final isSelected = _selectedIds.contains(candidate.id);

    return GestureDetector(
      onTap: () => _showMatchDetail(candidate),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha:0.06)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha:0.4)
                : _getPriorityBorderColor(candidate.priority),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(candidate.id);
                        } else {
                          _selectedIds.remove(candidate.id);
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
                            PriorityBadge(priority: candidate.priorityDisplayName),
                            const SizedBox(width: 8),
                            if (candidate.hasAiRecommendation) ...[
                              AiBadge(
                                label: 'AI',
                                confidence: candidate.aiConfidence,
                                compact: false,
                              ),
                              const SizedBox(width: 8),
                            ],
                            const Spacer(),
                            Text(
                              candidate.createdAt.difference(DateTime.now()).inHours.abs() < 24
                                  ? '${DateTime.now().difference(candidate.createdAt).inHours}h ago'
                                  : '${DateTime.now().difference(candidate.createdAt).inDays}d ago',
                              style: AppTextStyles.timestamp,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Entity names
                        Row(
                          children: [
                            Expanded(
                              child: _buildEntityChip(
                                candidate.sourceEntityName,
                                candidate.sourceEntityId,
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
                                candidate.targetEntityName,
                                candidate.targetEntityId,
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
                          widthFactor: candidate.overallScore.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getScoreColor(candidate.overallScore)
                                      .withValues(alpha:0.7),
                                  _getScoreColor(candidate.overallScore),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: _getScoreColor(candidate.overallScore)
                                      .withValues(alpha:0.4),
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
                    '${(candidate.overallScore * 100).round()}%',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: _getScoreColor(candidate.overallScore),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Field matches summary
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: candidate.fieldMatches.take(4).map((field) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getFieldMatchColor(field.similarity)
                          .withValues(alpha:0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getFieldMatchColor(field.similarity)
                            .withValues(alpha:0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          field.isExact
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 12,
                          color: _getFieldMatchColor(field.similarity),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          field.displayName,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: _getFieldMatchColor(field.similarity),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(field.similarity * 100).round()}%',
                          style: AppTextStyles.badgeLabel.copyWith(
                            color: _getFieldMatchColor(field.similarity),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // AI explanation (if available)
              if (candidate.aiExplanation != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.aiPurple.withValues(alpha:0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.aiPurple.withValues(alpha:0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 14, color: AppColors.aiPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          candidate.aiExplanation!,
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

              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveCandidate(candidate),
                      icon: const Icon(Icons.merge_type_rounded, size: 16),
                      label: const Text('Merge'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectCandidate(candidate),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Not a Dup'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
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
                    onPressed: () => _showMatchDetail(candidate),
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
              color: AppColors.primary.withValues(alpha:0.12),
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

  Color _getPriorityBorderColor(MatchPriority priority) {
    switch (priority) {
      case MatchPriority.critical:
        return AppColors.error.withValues(alpha:0.3);
      case MatchPriority.high:
        return AppColors.warning.withValues(alpha:0.3);
      default:
        return AppColors.divider;
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

  void _approveCandidate(MatchCandidate candidate) {
    setState(() {
      _allCandidates = _allCandidates.where((c) => c.id != candidate.id).toList();
      _selectedIds.remove(candidate.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${candidate.sourceEntityName} merged with ${candidate.targetEntityName}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() => _allCandidates.add(candidate));
          },
        ),
      ),
    );
  }

  void _rejectCandidate(MatchCandidate candidate) {
    setState(() {
      _allCandidates = _allCandidates.where((c) => c.id != candidate.id).toList();
      _selectedIds.remove(candidate.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Marked as not a duplicate'),
        backgroundColor: AppColors.elevatedCard,
      ),
    );
  }

  void _bulkApprove() {
    final selected = _selectedIds.toList();
    setState(() {
      _allCandidates = _allCandidates
          .where((c) => !_selectedIds.contains(c.id))
          .toList();
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selected.length} matches merged successfully'),
      ),
    );
  }

  void _bulkReject() {
    final selected = _selectedIds.toList();
    setState(() {
      _allCandidates = _allCandidates
          .where((c) => !_selectedIds.contains(c.id))
          .toList();
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selected.length} candidates marked as not duplicates'),
        backgroundColor: AppColors.elevatedCard,
      ),
    );
  }

  void _showMatchDetail(MatchCandidate candidate) {
    showDialog(
      context: context,
      builder: (context) => _MatchDetailDialog(candidate: candidate),
    );
  }
}

class _MatchDetailDialog extends StatelessWidget {
  final MatchCandidate candidate;

  const _MatchDetailDialog({required this.candidate});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
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
                '${candidate.sourceEntityName} ↔ ${candidate.targetEntityName}',
                style: AppTextStyles.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Overall score: ${(candidate.overallScore * 100).round()}% · ${candidate.matchAlgorithm}',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: candidate.fieldMatches.map((field) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.navyBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(field.displayName,
                                      style: AppTextStyles.labelMedium),
                                  Text(field.algorithm,
                                      style: AppTextStyles.timestamp),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(field.sourceValue.toString(),
                                      style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.primaryText)),
                                  Text(field.targetValue.toString(),
                                      style: AppTextStyles.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: field.similarity >= 0.9
                                    ? AppColors.primary.withValues(alpha:0.1)
                                    : AppColors.warning.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(field.similarity * 100).round()}%',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: field.similarity >= 0.9
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
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('Not a Duplicate'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.merge_type_rounded, size: 16),
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
}

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
