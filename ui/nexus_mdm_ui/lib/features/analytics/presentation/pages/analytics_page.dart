import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/models/dashboard_stats.dart';
import '../../../../shared/models/api_responses.dart';
import '../../data/analytics_repository.dart';

// ─────────────────────────────────────────────
// Internal model (replaces hardcoded constants)
// ─────────────────────────────────────────────

class _KpiCard {
  final String label;
  final String value;
  final String trend;
  final bool trendUp;
  final IconData icon;
  final Gradient gradient;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.trendUp,
    required this.icon,
    required this.gradient,
  });
}

// ─────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = true;
  String? _error;
  AnalyticsData? _data;
  String _period = 'Last 30 days';
  int _touchedPieIndex = -1;
  int? _hoveredStewardRow;

  final _periods = ['Last 7 days', 'Last 30 days', 'Last 90 days', 'Last Year'];
  final _repo = GetIt.instance<AnalyticsRepository>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    final result = await _repo.getAnalytics();
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        setState(() { _data = data; _isLoading = false; });
      case Failure(:final exception):
        setState(() { _error = exception.message; _isLoading = false; });
    }
  }

  // ── Derived KPI cards from real stats ─────────

  List<_KpiCard> _buildKpiCards(DashboardStats s) {
    final nf = NumberFormat('#,###');
    final growthSign = s.entityGrowthRate >= 0 ? '+' : '';
    final grSign     = s.goldenRecordGrowthRate >= 0 ? '+' : '';
    final aiSign     = s.aiScoreDelta >= 0 ? '+' : '';
    final pdSign     = s.pendingReviewDelta >= 0 ? '+' : '';

    return [
      _KpiCard(
        label: 'Total Entities',
        value: nf.format(s.totalEntities),
        trend: '$growthSign${s.entityGrowthRate.toStringAsFixed(1)}%',
        trendUp: s.entityGrowthRate >= 0,
        icon: Icons.hub_rounded,
        gradient: AppColors.primaryGradient,
      ),
      _KpiCard(
        label: 'Golden Records',
        value: nf.format(s.totalGoldenRecords),
        trend: '$grSign${s.goldenRecordGrowthRate.toStringAsFixed(1)}%',
        trendUp: s.goldenRecordGrowthRate >= 0,
        icon: Icons.stars_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFE6A800)],
        ),
      ),
      _KpiCard(
        label: 'AI Match Score',
        value: '${s.aiMatchScore.toStringAsFixed(1)}%',
        trend: '$aiSign${s.aiScoreDelta.toStringAsFixed(1)}%',
        trendUp: s.aiScoreDelta >= 0,
        icon: Icons.merge_type_rounded,
        gradient: AppColors.blueGradient,
      ),
      _KpiCard(
        label: 'Data Quality',
        value: '${s.overallDataQuality.toStringAsFixed(1)}%',
        trend: s.overallDataQuality >= 80 ? 'Good' : 'Needs work',
        trendUp: s.overallDataQuality >= 80,
        icon: Icons.verified_rounded,
        gradient: AppColors.purpleGradient,
      ),
      _KpiCard(
        label: 'Pending Review',
        value: nf.format(s.pendingReview),
        trend: '$pdSign${s.pendingReviewDelta}',
        trendUp: s.pendingReviewDelta <= 0,
        icon: Icons.pending_actions_rounded,
        gradient: AppColors.warningGradient,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          if (_error != null) _buildError(),
          _buildKpiRow(),
          const SizedBox(height: 24),
          _buildChartsRow(),
          const SizedBox(height: 24),
          _buildBottomRow(),
          const SizedBox(height: 24),
          _buildExportRow(),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analytics & Reports', style: AppTextStyles.headlineSmall)
                .animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 4),
            Text(
              'Platform performance, data quality, and steward metrics',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText),
            ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
          ],
        ),
        const Spacer(),
        DropdownButton<String>(
          value: _period,
          dropdownColor: AppColors.elevatedCard,
          style: AppTextStyles.bodyMedium,
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.secondaryText, size: 20),
          items: _periods
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (v) {
            setState(() => _period = v!);
            _loadData();
          },
        ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: AppColors.secondaryText, size: 20),
          tooltip: 'Refresh',
          onPressed: _loadData,
        ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Failed to load analytics: $_error',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ),
          TextButton(
            onPressed: _loadData,
            child: Text('Retry', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // ── KPI Row ────────────────────────────────

  Widget _buildKpiRow() {
    if (_isLoading) {
      return SizedBox(
        height: 130,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) =>
              const SizedBox(width: 220, child: StatCardShimmer()),
        ),
      );
    }
    if (_data == null) return const SizedBox.shrink();
    final cards = _buildKpiCards(_data!.stats);
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _KpiWidget(card: cards[i], index: i),
      ),
    );
  }

  // ── Middle Charts Row ──────────────────────

  Widget _buildChartsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildMatchActivityBarChart()),
        const SizedBox(width: 20),
        Expanded(flex: 5, child: _buildQualityLineChart()),
      ],
    );
  }

  Widget _buildMatchActivityBarChart() {
    if (_isLoading) return const ChartShimmer(height: 280);
    if (_data == null) return const SizedBox.shrink();
    final activity = _data!.stats.matchActivity;

    if (activity.isEmpty) {
      return Container(
        height: 280,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text('No match activity data yet',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
        ),
      );
    }

    final maxY = activity
        .map((a) => (a.autoMerged + a.manualMerged + a.rejected + a.pending).toDouble())
        .reduce((a, b) => a > b ? a : b)
        .ceilToDouble() + 5;

    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match Activity (14 days)', style: AppTextStyles.titleSmall),
          const SizedBox(height: 4),
          Text('Daily auto-merged + human-reviewed matches',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.elevatedCard,
                    tooltipBorder: const BorderSide(color: AppColors.divider),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final a = activity[group.x.toInt()];
                      final label = DateFormat('MMM d').format(a.date);
                      return BarTooltipItem(
                        '$label\n${rod.toY.toStringAsFixed(0)} matches',
                        AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryText, height: 1.5),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 2,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= activity.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('d').format(activity[idx].date),
                            style: AppTextStyles.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: AppTextStyles.labelSmall,
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: activity.asMap().entries.map((e) {
                  final a = e.value;
                  final total = (a.autoMerged + a.manualMerged).toDouble();
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: total,
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.primary.withValues(alpha: 0.6),
                            AppColors.primary,
                          ],
                        ),
                        width: 14,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
              swapAnimationDuration: const Duration(milliseconds: 600),
              swapAnimationCurve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildQualityLineChart() {
    if (_isLoading) return const ChartShimmer(height: 280);
    if (_data == null) return const SizedBox.shrink();

    final quality = _data!.stats.overallDataQuality;
    final activity = _data!.stats.matchActivity;

    // Build a daily quality proxy from matchActivity:
    // quality_i = auto_merged / (auto_merged + manual_merged + rejected + pending) * 100
    final List<FlSpot> spots;
    if (activity.isNotEmpty) {
      spots = activity.asMap().entries.map((e) {
        final a = e.value;
        final total = a.total;
        final score = total > 0
            ? (a.autoMerged / total) * 100.0
            : quality;
        return FlSpot(e.key.toDouble(), score.clamp(0.0, 100.0));
      }).toList();
    } else {
      spots = [FlSpot(0, quality)];
    }

    final minY = (spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 5)
        .clamp(0.0, 100.0);
    final maxY = (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 5)
        .clamp(0.0, 100.0);

    return Container(
      height: 280,
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
              Text('Auto-Merge Quality Trend', style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${quality.toStringAsFixed(1)}% overall',
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Daily auto-merge rate over match activity window',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.elevatedCard,
                    tooltipBorder: const BorderSide(color: AppColors.divider),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) => touchedSpots
                        .map((s) => LineTooltipItem(
                              'Day ${s.x.toInt() + 1}: ${s.y.toStringAsFixed(1)}%',
                              AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.primaryText),
                            ))
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: spots.length > 8 ? 2 : 1,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= activity.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('d').format(activity[idx].date),
                            style: AppTextStyles.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(0)}%',
                        style: AppTextStyles.labelSmall,
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.25),
                          AppColors.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    ).animate(delay: 80.ms).fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0);
  }

  // ── Bottom Row ─────────────────────────────

  Widget _buildBottomRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: _buildMatchPieChart()),
        const SizedBox(width: 20),
        Expanded(flex: 6, child: _buildTopStewardsTable()),
      ],
    );
  }

  Widget _buildMatchPieChart() {
    if (_isLoading) return const ChartShimmer(height: 320);
    if (_data == null) return const SizedBox.shrink();

    final activity = _data!.stats.matchActivity;
    int totalAuto = 0, totalManual = 0, totalRejected = 0;
    for (final a in activity) {
      totalAuto    += a.autoMerged;
      totalManual  += a.manualMerged;
      totalRejected += a.rejected;
    }
    final grand = (totalAuto + totalManual + totalRejected).toDouble();

    final sections = grand > 0
        ? [
            ('Auto-merged',    totalAuto    / grand * 100, AppColors.primary),
            ('Human-approved', totalManual  / grand * 100, AppColors.aiPurple),
            ('Rejected',       totalRejected/ grand * 100, AppColors.error),
          ]
        : [
            ('Auto-merged',    0.0, AppColors.primary),
            ('Human-approved', 0.0, AppColors.aiPurple),
            ('Rejected',       0.0, AppColors.error),
          ];

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
          Text('Match Performance', style: AppTextStyles.titleSmall),
          const SizedBox(height: 4),
          Text('Distribution of match outcomes (14-day window)',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 20),
          if (grand > 0)
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    final touched = i == _touchedPieIndex;
                    return PieChartSectionData(
                      value: s.$2,
                      color: s.$3,
                      title: touched ? '${s.$2.toStringAsFixed(1)}%' : '',
                      radius: touched ? 72 : 60,
                      titleStyle: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                  pieTouchData: PieTouchData(
                    touchCallback: (event, resp) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            resp == null ||
                            resp.touchedSection == null) {
                          _touchedPieIndex = -1;
                          return;
                        }
                        _touchedPieIndex =
                            resp.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  sectionsSpace: 3,
                  centerSpaceRadius: 36,
                  borderData: FlBorderData(show: false),
                ),
                swapAnimationDuration: const Duration(milliseconds: 600),
                swapAnimationCurve: Curves.easeOutCubic,
              ),
            )
          else
            const SizedBox(
              height: 180,
              child: Center(child: Text('No match data yet')),
            ),
          const SizedBox(height: 16),
          ...sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: s.$3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.$1,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.primaryText)),
                    ),
                    Text(
                      '${s.$2.toStringAsFixed(1)}%',
                      style: AppTextStyles.labelMedium.copyWith(color: s.$3),
                    ),
                  ],
                ),
              )),
        ],
      ),
    ).animate(delay: 160.ms).fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildTopStewardsTable() {
    if (_isLoading) return const ChartShimmer(height: 320);
    if (_data == null) return const SizedBox.shrink();
    final stewards = _data!.stewards;

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
              Text('Top Stewards', style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('All time', style: AppTextStyles.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Review performance by data steward',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          if (stewards.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Text(
                'No reviews recorded yet',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.secondaryText),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('NAME', style: AppTextStyles.tableHeader)),
                  Expanded(flex: 2, child: Text('REVIEWS', style: AppTextStyles.tableHeader, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('APPROVAL %', style: AppTextStyles.tableHeader, textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('AVG TIME', style: AppTextStyles.tableHeader, textAlign: TextAlign.center)),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            ...stewards.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final isHovered = _hoveredStewardRow == i;
              final initials = s.displayName
                  .split(' ')
                  .where((w) => w.isNotEmpty)
                  .map((w) => w[0])
                  .take(2)
                  .join();
              final avgTimeLabel = s.avgReviewMin < 1
                  ? '< 1 min'
                  : '${s.avgReviewMin.toStringAsFixed(1)} min';

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredStewardRow = i),
                onExit:  (_) => setState(() => _hoveredStewardRow = null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  color: isHovered
                      ? AppColors.elevatedCard.withValues(alpha: 0.5)
                      : Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.chartPalette[
                                        i % AppColors.chartPalette.length]
                                    .withValues(alpha: 0.2),
                                child: Text(
                                  initials,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.chartPalette[
                                        i % AppColors.chartPalette.length],
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(s.displayName,
                                    style: AppTextStyles.tableCell,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            NumberFormat('#,###').format(s.totalReviews),
                            style: AppTextStyles.tableCell,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Text(
                                '${s.approvalPct.toStringAsFixed(1)}%',
                                style: AppTextStyles.tableCell.copyWith(
                                  color: s.approvalPct >= 90
                                      ? AppColors.primary
                                      : AppColors.warning,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: s.approvalPct / 100,
                                  backgroundColor: AppColors.divider,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    s.approvalPct >= 90
                                        ? AppColors.primary
                                        : AppColors.warning,
                                  ),
                                  minHeight: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            avgTimeLabel,
                            style: AppTextStyles.tableCell,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    ).animate(delay: 240.ms).fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0);
  }

  // ── Export Row ─────────────────────────────

  Widget _buildExportRow() {
    return Row(
      children: [
        _ExportButton(
          icon: Icons.picture_as_pdf_outlined,
          label: 'Export PDF',
          onTap: () { _triggerExport('pdf'); },
        ),
        const SizedBox(width: 12),
        _ExportButton(
          icon: Icons.table_chart_outlined,
          label: 'Export Excel',
          onTap: () { _triggerExport('excel'); },
        ),
        const SizedBox(width: 12),
        _ExportButton(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () { _triggerExport('share'); },
        ),
      ],
    ).animate(delay: 320.ms).fadeIn(duration: 400.ms);
  }

  Future<void> _triggerExport(String format) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing export...'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      await ApiClient().post(
        '/v1/analytics/export',
        data: {'format': format, 'period': _period},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report queued — check your email or notification center'),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export not available yet'),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────

class _KpiWidget extends StatelessWidget {
  final _KpiCard card;
  final int index;

  const _KpiWidget({required this.card, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: -18,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                gradient: card.gradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: card.gradient,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(card.icon,
                        color: AppColors.navyBackground, size: 18),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (card.trendUp ? AppColors.primary : AppColors.error)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          card.trendUp
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 11,
                          color: card.trendUp
                              ? AppColors.primary
                              : AppColors.error,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          card.trend,
                          style: AppTextStyles.badgeLabel.copyWith(
                            color: card.trendUp
                                ? AppColors.primary
                                : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(card.value,
                  style: AppTextStyles.statValue.copyWith(fontSize: 22)),
              const SizedBox(height: 2),
              Text(card.label, style: AppTextStyles.statLabel),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 350.ms)
        .slideX(begin: 0.05, end: 0, duration: 350.ms);
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: AppTextStyles.buttonSmall),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.secondaryText,
        side: const BorderSide(color: AppColors.divider),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}
