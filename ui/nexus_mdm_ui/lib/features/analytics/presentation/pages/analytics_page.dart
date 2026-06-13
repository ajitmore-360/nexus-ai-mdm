import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/loading_shimmer.dart';

// ─────────────────────────────────────────────
// Models & demo data
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

class _Steward {
  final String name;
  final int reviews;
  final double approvalPct;
  final String avgTime;

  const _Steward({
    required this.name,
    required this.reviews,
    required this.approvalPct,
    required this.avgTime,
  });
}

const _kpiCards = [
  _KpiCard(
    label: 'Total Entities',
    value: '4,200,421',
    trend: '+1.2%',
    trendUp: true,
    icon: Icons.hub_rounded,
    gradient: AppColors.primaryGradient,
  ),
  _KpiCard(
    label: 'Golden Records',
    value: '892,103',
    trend: '+0.8%',
    trendUp: true,
    icon: Icons.stars_rounded,
    gradient: LinearGradient(
      colors: [Color(0xFFFFD700), Color(0xFFE6A800)],
    ),
  ),
  _KpiCard(
    label: 'Match Rate',
    value: '94.2%',
    trend: '+2.1%',
    trendUp: true,
    icon: Icons.merge_type_rounded,
    gradient: AppColors.blueGradient,
  ),
  _KpiCard(
    label: 'Auto-merge Rate',
    value: '68.6%',
    trend: '+3.4%',
    trendUp: true,
    icon: Icons.auto_awesome_rounded,
    gradient: AppColors.purpleGradient,
  ),
  _KpiCard(
    label: 'Avg Review Time',
    value: '2.3 min',
    trend: '-0.8%',
    trendUp: false,
    icon: Icons.timer_outlined,
    gradient: AppColors.warningGradient,
  ),
];

// Entity growth: 12 months of bar values (thousands)
const _entityGrowthData = [
  320.0, 348.0, 367.0, 390.0, 412.0, 430.0,
  455.0, 471.0, 489.0, 508.0, 526.0, 540.0,
];
const _growthMonths = [
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
];

// Quality score: 30 data points, range 90-100
final _qualityScoreData = List.generate(30, (i) {
  final base = 91.0 + (i * 0.27);
  final noise = (i % 3 == 0 ? -0.4 : (i % 5 == 0 ? 0.6 : 0.1));
  return base + noise;
});

const _stewards = [
  _Steward(name: 'Sarah Chen', reviews: 342, approvalPct: 94.2, avgTime: '1.8 min'),
  _Steward(name: 'Marcus Webb', reviews: 289, approvalPct: 91.7, avgTime: '2.1 min'),
  _Steward(name: 'Priya Sharma', reviews: 261, approvalPct: 96.1, avgTime: '1.5 min'),
  _Steward(name: 'James Taylor', reviews: 198, approvalPct: 88.3, avgTime: '3.2 min'),
  _Steward(name: 'Ana Kovacs', reviews: 174, approvalPct: 92.5, avgTime: '2.4 min'),
];

// ─────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _isLoading = false;
  String _period = 'Last 30 days';
  int _touchedPieIndex = -1;
  int? _hoveredStewardRow;

  final _periods = [
    'Last 7 days',
    'Last 30 days',
    'Last 90 days',
    'Last Year',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
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
                .animate()
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 4),
            Text(
              'Platform performance, data quality, and steward metrics',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText),
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
          onChanged: (v) => setState(() {
            _period = v!;
            _isLoading = true;
            Future.delayed(const Duration(milliseconds: 600),
                () => setState(() => _isLoading = false));
          }),
        ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
      ],
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
          itemBuilder: (_, __) => const SizedBox(
            width: 220,
            child: StatCardShimmer(),
          ),
        ),
      );
    }

    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kpiCards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _KpiWidget(card: _kpiCards[i], index: i),
      ),
    );
  }

  // ── Middle Charts Row ──────────────────────

  Widget _buildChartsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildGrowthBarChart()),
        const SizedBox(width: 20),
        Expanded(flex: 5, child: _buildQualityLineChart()),
      ],
    );
  }

  Widget _buildGrowthBarChart() {
    if (_isLoading) return const ChartShimmer(height: 280);
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
          Text('Entity Growth (12 months)',
              style: AppTextStyles.titleSmall),
          const SizedBox(height: 4),
          Text('Monthly entity count in thousands',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 600,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.elevatedCard,
                    tooltipBorder:
                        const BorderSide(color: AppColors.divider),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${_growthMonths[group.x.toInt()]}\n'
                        '${rod.toY.toStringAsFixed(0)}K entities',
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
                      getTitlesWidget: (value, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _growthMonths[value.toInt()],
                          style: AppTextStyles.labelSmall,
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 200,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}K',
                        style: AppTextStyles.labelSmall,
                      ),
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
                  horizontalInterval: 200,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _entityGrowthData.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value,
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.primary.withValues(alpha:0.6),
                            AppColors.primary,
                          ],
                        ),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
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
    final spots = _qualityScoreData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

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
              Text('Data Quality Score Trend',
                  style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_qualityScoreData.last.toStringAsFixed(1)}%',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('30-day rolling quality score (90–100%)',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 89,
                maxY: 101,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.elevatedCard,
                    tooltipBorder:
                        const BorderSide(color: AppColors.divider),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              'Day ${s.x.toInt() + 1}: ${s.y.toStringAsFixed(1)}%',
                              AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primaryText),
                            ))
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 5,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'D${v.toInt() + 1}',
                          style: AppTextStyles.labelSmall,
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 2,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(0)}%',
                        style: AppTextStyles.labelSmall,
                      ),
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
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
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
                          AppColors.primary.withValues(alpha:0.25),
                          AppColors.primary.withValues(alpha:0.0),
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
    )
        .animate(delay: 80.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0);
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

    const sections = [
      ('Auto-merged', 68.6, AppColors.primary),
      ('Human-approved', 23.6, AppColors.aiPurple),
      ('Rejected', 7.8, AppColors.error),
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
          Text('Distribution of match outcomes',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 20),
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
                    title: touched ? '${s.$2}%' : '',
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
          ),
          const SizedBox(height: 16),
          ...sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
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
                      '${s.$2}%',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: s.$3),
                    ),
                  ],
                ),
              )),
        ],
      ),
    )
        .animate(delay: 160.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0);
  }

  Widget _buildTopStewardsTable() {
    if (_isLoading) return const ChartShimmer(height: 320);
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('This period',
                    style: AppTextStyles.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Review performance by data steward',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('NAME',
                        style: AppTextStyles.tableHeader)),
                Expanded(
                    flex: 2,
                    child: Text('REVIEWS',
                        style: AppTextStyles.tableHeader,
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('APPROVAL %',
                        style: AppTextStyles.tableHeader,
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('AVG TIME',
                        style: AppTextStyles.tableHeader,
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          ..._stewards.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final isHovered = _hoveredStewardRow == i;
            return MouseRegion(
              onEnter: (_) => setState(() => _hoveredStewardRow = i),
              onExit: (_) => setState(() => _hoveredStewardRow = null),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                color: isHovered
                    ? AppColors.elevatedCard.withValues(alpha:0.5)
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
                              backgroundColor: AppColors.chartPalette[i % AppColors.chartPalette.length].withValues(alpha:0.2),
                              child: Text(
                                s.name.split(' ').map((w) => w[0]).take(2).join(),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.chartPalette[i % AppColors.chartPalette.length],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(s.name,
                                  style: AppTextStyles.tableCell,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          NumberFormat('#,###').format(s.reviews),
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
                                color: s.approvalPct >= 93
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
                                  s.approvalPct >= 93
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
                          s.avgTime,
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
      ),
    )
        .animate(delay: 240.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.05, end: 0);
  }

  // ── Export Row ─────────────────────────────

  Widget _buildExportRow() {
    return Row(
      children: [
        _ExportButton(
          icon: Icons.picture_as_pdf_outlined,
          label: 'Export PDF',
          onTap: () => _showExportSnackBar('PDF'),
        ),
        const SizedBox(width: 12),
        _ExportButton(
          icon: Icons.table_chart_outlined,
          label: 'Export Excel',
          onTap: () => _showExportSnackBar('Excel'),
        ),
        const SizedBox(width: 12),
        _ExportButton(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () => _showExportSnackBar('share link'),
        ),
      ],
    ).animate(delay: 320.ms).fadeIn(duration: 400.ms);
  }

  void _showExportSnackBar(String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generating $type report...'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: AppColors.primary,
          onPressed: () {},
        ),
      ),
    );
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
            color: Colors.black.withValues(alpha:0.15),
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
                    width: 36,
                    height: 36,
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
                          .withValues(alpha:0.12),
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
                  style: AppTextStyles.statValue
                      .copyWith(fontSize: 22)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}
