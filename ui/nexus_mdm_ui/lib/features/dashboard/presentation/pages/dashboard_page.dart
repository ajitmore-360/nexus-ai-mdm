import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../shared/models/dashboard_stats.dart';
import '../../../../shared/models/activity_item.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/entity_avatar.dart';
import '../../data/dashboard_repository.dart';
import '../../../admin/presentation/pages/platform_dashboard_page.dart';
import 'business_admin_dashboard_page.dart';
import 'steward_dashboard_page.dart';

class DashboardPage extends StatefulWidget {
  final String? section;

  const DashboardPage({super.key, this.section});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardRepository _repository;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isProductAdmin = false;
  bool _isBusinessAdmin = false;
  bool _isSteward = false;
  String _errorMessage = '';
  DashboardStats _stats = DashboardStats.empty;
  List<ActivityItem> _activities = const [];
  QualityDimensions _quality = QualityDimensions.empty;
  List<StewardStat> _stewards = const [];
  int _touchedChartIndex = -1;
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    _repository = DashboardRepository(ApiClient());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final tenantId = await AuthManager.getTenantId() ?? '';
    final displayName = await AuthManager.getUserName() ?? '';
    final role        = await AuthManager.getUserRole() ?? '';
    if (!mounted) return;
    if (role == 'super_admin') {
      setState(() { _isProductAdmin = true; _isLoading = false; });
      return;
    }
    if (role == 'business_admin') {
      setState(() { _isBusinessAdmin = true; _isLoading = false; });
      return;
    }
    if (role == 'steward') {
      setState(() { _isSteward = true; _isLoading = false; });
      return;
    }
    setState(() {
      _firstName = displayName.isNotEmpty
          ? displayName.split(' ').first
          : '';
    });

    final results = await Future.wait([
      _repository.getStats(tenantId),
      _repository.getActivityFeed(tenantId),
      _repository.getQualityDimensions(),
      _repository.getStewardPerformance(),
    ]);

    if (!mounted) return;

    final statsResult    = results[0] as ApiResult<DashboardStats>;
    final activityResult = results[1] as ApiResult<List<ActivityItem>>;
    final quality        = results[2] as QualityDimensions;
    final stewards       = results[3] as List<StewardStat>;

    setState(() {
      _isLoading = false;
      _quality   = quality;
      _stewards  = stewards;
      switch (statsResult) {
        case Success<DashboardStats>(:final data):
          _stats = data;
        case Failure<DashboardStats>(:final exception):
          _hasError = true;
          _errorMessage = exception.message;
          _stats = DashboardStats.empty;
      }
      switch (activityResult) {
        case Success<List<ActivityItem>>(:final data):
          _activities = data;
        case Failure<List<ActivityItem>>(:final exception):
          _activities = const [];
          if (!_hasError) {
            _hasError = true;
            _errorMessage = exception.message;
          }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isProductAdmin) return const PlatformDashboardPage();
    if (_isBusinessAdmin) return const BusinessAdminDashboardPage();
    if (_isSteward) return const StewardDashboardPage();
    if (widget.section != null && widget.section != 'main') {
      return _buildPlaceholderSection();
    }
    return _buildMainDashboard();
  }

  Widget _buildPlaceholderSection() {
    final sectionMap = {
      'golden': ('Golden Records', Icons.stars_rounded, 'View and manage all golden master records'),
      'quality': ('Data Quality', Icons.health_and_safety_rounded, 'Monitor and improve your data quality metrics'),
      'governance': ('Governance', Icons.policy_rounded, 'Configure data governance rules and policies'),
      'analytics': ('Analytics', Icons.analytics_rounded, 'Deep insights into your MDM performance'),
      'settings': ('Settings', Icons.settings_rounded, 'Configure your Azile AI MDM platform'),
    };

    final config = sectionMap[widget.section] ??
        ('Dashboard', Icons.dashboard_rounded, '');

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
            child: Icon(config.$2, color: AppColors.navyBackground, size: 40),
          ).animate().fadeIn().scaleXY(begin: 0.8, end: 1.0),
          const SizedBox(height: 24),
          Text(config.$1, style: AppTextStyles.headlineSmall).animate(delay: 100.ms).fadeIn(),
          const SizedBox(height: 8),
          Text(
            config.$3,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText),
            textAlign: TextAlign.center,
          ).animate(delay: 200.ms).fadeIn(),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_rounded,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Coming in next sprint',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ).animate(delay: 300.ms).fadeIn(),
        ],
      ),
    );
  }

  Widget _buildMainDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_hasError) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(),
          ],
          const SizedBox(height: 24),
          _buildStatCards(),
          const SizedBox(height: 24),
          _buildChartsRow(),
          const SizedBox(height: 24),
          _buildQualityDimensions(),
          const SizedBox(height: 24),
          _buildStewardPerformance(),
          const SizedBox(height: 24),
          _buildActivityFeed(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not reach server â€” showing demo data. $_errorMessage',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: _loadData,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _firstName.isEmpty ? 'Welcome back' : 'Good morning, $_firstName',
              style: AppTextStyles.headlineSmall,
            )
                .animate()
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText),
            ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => context.go('/dashboard/ai-prism'),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Ask AI'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.aiPurple,
            side: const BorderSide(color: AppColors.aiPurple),
          ),
        ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => context.go('/dashboard/entities'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Entity'),
        ).animate(delay: 250.ms).fadeIn(duration: 400.ms),
      ],
    );
  }

  Widget _buildStatCards() {
    if (_isLoading) {
      return GridView(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getCrossAxisCount(),
          crossAxisSpacing: AppConstants.gridSpacing,
          mainAxisSpacing: AppConstants.gridSpacing,
          mainAxisExtent: 180,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          StatCardShimmer(),
          StatCardShimmer(),
          StatCardShimmer(),
          StatCardShimmer(),
        ],
      );
    }

    final cards = [
      StatCard(
        title: 'Total Entities',
        value: _formatNumber(_stats.totalEntities),
        subtitle: '+${_stats.newEntitiesToday} today',
        icon: Icons.hub_rounded,
        gradient: AppColors.primaryGradient,
        trendValue: _stats.entityGrowthRate,
        trendPositive: true,
        onTap: () => context.go('/dashboard/entities'),
        animationDelay: 0,
      ),
      StatCard(
        title: 'Golden Records',
        value: _formatNumber(_stats.totalGoldenRecords),
        subtitle: '${_stats.totalEntities > 0 ? (_stats.totalGoldenRecords / _stats.totalEntities * 100).toStringAsFixed(1) : "0.0"}% coverage',
        icon: Icons.stars_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFE6A800)],
        ),
        trendValue: _stats.goldenRecordGrowthRate,
        trendPositive: true,
        onTap: () => context.go('/dashboard/golden-records'),
        animationDelay: 80,
      ),
      StatCard(
        title: 'Pending Review',
        value: _formatNumber(_stats.pendingReview),
        subtitle: '${_stats.pendingReviewDelta} from yesterday',
        icon: Icons.pending_actions_rounded,
        gradient: AppColors.warningGradient,
        trendValue: _stats.pendingReviewDelta.toDouble(),
        trendPositive: _stats.pendingReviewDelta <= 0,
        onTap: () => context.go('/dashboard/match-queue'),
        animationDelay: 160,
      ),
      StatCard(
        title: 'AI Match Score',
        value: '${_stats.aiMatchScore.toStringAsFixed(1)}%',
        subtitle: 'Model accuracy',
        icon: Icons.auto_awesome_rounded,
        gradient: AppColors.purpleGradient,
        trendValue: _stats.aiScoreDelta,
        trendPositive: true,
        animationDelay: 240,
      ),
    ];

    return GridView(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getCrossAxisCount(),
        crossAxisSpacing: AppConstants.gridSpacing,
        mainAxisSpacing: AppConstants.gridSpacing,
        mainAxisExtent: 180,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  int _getCrossAxisCount() {
    final width = MediaQuery.of(context).size.width;
    if (width > 1400) return 4;
    if (width > 1000) return 2;
    return 1;
  }

  Widget _buildChartsRow() {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 1100;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: _buildMatchActivityChart()),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _buildDuplicateSourcesChart()),
        ],
      );
    }
    return Column(
      children: [
        _buildMatchActivityChart(),
        const SizedBox(height: 16),
        _buildDuplicateSourcesChart(),
      ],
    );
  }

  Widget _buildMatchActivityChart() {
    if (_isLoading) return const ChartShimmer(height: 280);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Match Activity', style: AppTextStyles.titleSmall),
              const Spacer(),
              _buildChartLegend(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Auto-merged, manual, and rejected â€” last 14 days',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: _stats.matchActivity.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bar_chart_rounded,
                            size: 40, color: AppColors.mutedText),
                        const SizedBox(height: 8),
                        Text(
                          'No match activity yet',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mutedText),
                        ),
                      ],
                    ),
                  )
                : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _stats.matchActivity
                        .map((a) => a.total.toDouble())
                        .fold(0.0, (prev, v) => v > prev ? v : prev) *
                    1.25,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.elevatedCard,
                    tooltipBorder: const BorderSide(
                        color: AppColors.divider),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final activity =
                          _stats.matchActivity[group.x.toInt()];
                      return BarTooltipItem(
                        '${DateFormat('MMM d').format(activity.date)}\n'
                        'Auto: ${activity.autoMerged}\n'
                        'Manual: ${activity.manualMerged}\n'
                        'Rejected: ${activity.rejected}',
                        AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryText,
                          height: 1.6,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: AppTextStyles.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx % 2 != 0 ||
                            idx >= _stats.matchActivity.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('d/M')
                                .format(_stats.matchActivity[idx].date),
                            style: AppTextStyles.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 100,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups:
                    _stats.matchActivity.asMap().entries.map((entry) {
                  final i = entry.key;
                  final activity = entry.value;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: activity.autoMerged.toDouble(),
                        color: AppColors.primary,
                        width: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: activity.manualMerged.toDouble(),
                        color: AppColors.aiPurple,
                        width: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: activity.rejected.toDouble(),
                        color: AppColors.error.withValues(alpha:0.7),
                        width: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                    barsSpace: 3,
                  );
                }).toList(),
              ),
              swapAnimationDuration: const Duration(milliseconds: 600),
              swapAnimationCurve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  Widget _buildChartLegend() {
    return Row(
      children: [
        _legendDot(AppColors.primary, 'Auto-merged'),
        const SizedBox(width: 12),
        _legendDot(AppColors.aiPurple, 'Manual'),
        const SizedBox(width: 12),
        _legendDot(AppColors.error.withValues(alpha:0.7), 'Rejected'),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }

  Widget _buildDuplicateSourcesChart() {
    if (_isLoading) return const ChartShimmer(height: 280);

    final sources = _stats.topDuplicateSources;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Duplicate Sources', style: AppTextStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Sources generating most matches',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: sources.asMap().entries.map((entry) {
                  final i = entry.key;
                  final src = entry.value;
                  final isTouch = i == _touchedChartIndex;
                  return PieChartSectionData(
                    value: src.count.toDouble(),
                    color: AppColors.chartPalette[i % AppColors.chartPalette.length],
                    title: isTouch
                        ? '${(src.percentage * 100).round()}%'
                        : '',
                    radius: isTouch ? 60 : 50,
                    titleStyle: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.navyBackground,
                      fontWeight: FontWeight.w700,
                    ),
                    badgeWidget: null,
                  );
                }).toList(),
                pieTouchData: PieTouchData(
                  touchCallback: (event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedChartIndex = -1;
                        return;
                      }
                      _touchedChartIndex = pieTouchResponse
                          .touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                borderData: FlBorderData(show: false),
              ),
              swapAnimationDuration: const Duration(milliseconds: 600),
              swapAnimationCurve: Curves.easeOutCubic,
            ),
          ),

          const SizedBox(height: 16),

          // Legend
          ...sources.asMap().entries.map((entry) {
            final i = entry.key;
            final src = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.chartPalette[
                          i % AppColors.chartPalette.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      src.source,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    src.count.toString(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${(src.percentage * 100).round()}%',
                      style: AppTextStyles.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    )
        .animate(delay: 100.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  Widget _buildActivityFeed() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Recent Activity', style: AppTextStyles.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/dashboard/analytics'),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'System events and user actions',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const EntityListShimmer(count: 5)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activities.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, i) =>
                  _buildActivityItem(_activities[i]),
            ),
        ],
      ),
    )
        .animate(delay: 200.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  Widget _buildActivityItem(ActivityItem item) {
    final iconData = _getActivityIcon(item.type);
    final color = _getActivityColor(item.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActivityAvatar(icon: iconData, color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      item.sourceSystem,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.mutedText,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.timeAgo,
                      style: AppTextStyles.timestamp,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (item.entityId != null)
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onPressed: () =>
                  context.go('/dashboard/entities/${item.entityId}'),
              color: AppColors.secondaryText,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.entityCreated:
        return Icons.add_circle_outline_rounded;
      case ActivityType.entityUpdated:
        return Icons.edit_outlined;
      case ActivityType.entityMerged:
        return Icons.merge_rounded;
      case ActivityType.matchFound:
        return Icons.merge_type_rounded;
      case ActivityType.matchReviewed:
        return Icons.check_circle_outline_rounded;
      case ActivityType.goldenRecordCreated:
        return Icons.stars_rounded;
      case ActivityType.goldenRecordUpdated:
        return Icons.star_outline_rounded;
      case ActivityType.dataQualityAlert:
        return Icons.warning_amber_rounded;
      case ActivityType.ruleTriggered:
        return Icons.policy_outlined;
      case ActivityType.userAction:
        return Icons.person_outline_rounded;
    }
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.goldenRecordCreated:
      case ActivityType.goldenRecordUpdated:
        return AppColors.statusGolden;
      case ActivityType.matchFound:
      case ActivityType.matchReviewed:
        return AppColors.primary;
      case ActivityType.entityMerged:
        return AppColors.aiPurple;
      case ActivityType.dataQualityAlert:
        return AppColors.error;
      case ActivityType.ruleTriggered:
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  // ---------------------------------------------------------------------------
  // BL-067: Quality Dimensions card
  // ---------------------------------------------------------------------------

  Widget _buildQualityDimensions() {
    final dims = [
      ('Completeness', _quality.completeness),
      ('Accuracy',     _quality.accuracy),
      ('Consistency',  _quality.consistency),
      ('Uniqueness',   _quality.uniqueness),
      ('Timeliness',   _quality.timeliness),
      ('Validity',     _quality.validity),
    ];

    Color barColor(double v) {
      if (v < 0.70) return AppColors.error;
      if (v < 0.85) return AppColors.warning;
      return AppColors.success;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Data Quality Dimensions', style: AppTextStyles.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: barColor(_quality.overallScore).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Overall ${(_quality.overallScore * 100).toStringAsFixed(1)}%',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: barColor(_quality.overallScore),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...dims.map((d) {
              final label = d.$1;
              final value = d.$2;
              final color = barColor(value);
              final pct   = (value * 100).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: AppTextStyles.bodySmall),
                        const Spacer(),
                        Text('$pct%',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [const FontFeature.tabularFigures()],
                            )),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: AppColors.cardSurface,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BL-067: Steward Performance card
  // ---------------------------------------------------------------------------

  Widget _buildStewardPerformance() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Steward Performance', style: AppTextStyles.titleMedium),
            const SizedBox(height: 16),
            if (_stewards.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No steward data available',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.secondaryText)),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      AppColors.surface),
                  columnSpacing: 20,
                  dataRowMinHeight: 44,
                  headingTextStyle: AppTextStyles.labelSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                  columns: const [
                    DataColumn(label: Text('STEWARD')),
                    DataColumn(label: Text('REVIEWS'), numeric: true),
                    DataColumn(label: Text('APPROVED'), numeric: true),
                    DataColumn(label: Text('REJECTED'), numeric: true),
                    DataColumn(label: Text('APPROVAL %'), numeric: true),
                    DataColumn(label: Text('AVG TIME'), numeric: true),
                  ],
                  rows: _stewards.map((s) {
                    final approvalColor = s.approvalPct >= 85
                        ? AppColors.success
                        : s.approvalPct >= 70
                            ? AppColors.warning
                            : AppColors.error;
                    return DataRow(cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.displayName,
                                style: AppTextStyles.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600)),
                            Text(s.email,
                                style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.secondaryText)),
                          ],
                        ),
                      ),
                      DataCell(Text(s.totalReviews.toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                              fontFeatures: [const FontFeature.tabularFigures()]))),
                      DataCell(Text(s.approvedCount.toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.success,
                              fontFeatures: [const FontFeature.tabularFigures()]))),
                      DataCell(Text(s.rejectedCount.toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                              fontFeatures: [const FontFeature.tabularFigures()]))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: approvalColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${s.approvalPct.toStringAsFixed(1)}%',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: approvalColor,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [const FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(
                        s.avgReviewMin < 60
                            ? '${s.avgReviewMin.toStringAsFixed(0)}m'
                            : '${(s.avgReviewMin / 60).toStringAsFixed(1)}h',
                        style: AppTextStyles.bodySmall.copyWith(
                            fontFeatures: [const FontFeature.tabularFigures()]),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
