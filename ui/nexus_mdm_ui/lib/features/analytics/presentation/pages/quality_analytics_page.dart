import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';

class QualityAnalyticsPage extends StatefulWidget {
  const QualityAnalyticsPage({super.key});

  @override
  State<QualityAnalyticsPage> createState() => _QualityAnalyticsPageState();
}

class _QualityAnalyticsPageState extends State<QualityAnalyticsPage> {
  final _apiClient = ApiClient();

  List<Map<String, dynamic>> _trends = [];
  List<Map<String, dynamic>> _dimensions = [];
  List<Map<String, dynamic>> _sources = [];
  bool _loading = true;
  bool _snapshotLoading = false;
  String _error = '';
  String? _userRole;
  String? _selectedEntityType;

  final List<String> _entityTypes = ['(All)', ...AppConstants.entityTypes];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userRole = await AuthManager.getUserRole();
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final etParam = (_selectedEntityType != null && _selectedEntityType != '(All)')
          ? _selectedEntityType
          : null;
      final futures = await Future.wait([
        _apiClient.get<Map<String, dynamic>>(
          AppConstants.qualityTrendsPath,
          queryParameters: {
            'days': 30,
            if (etParam != null) 'entity_type': etParam,
          },
        ),
        _apiClient.get<Map<String, dynamic>>(
          AppConstants.qualityDimensionPath,
          queryParameters: {
            if (etParam != null) 'entity_type': etParam,
          },
        ),
        _apiClient.get<Map<String, dynamic>>(AppConstants.sourceQualityPath),
      ]);
      setState(() {
        _trends = (futures[0].data?['trends'] as List? ?? []).cast<Map<String, dynamic>>();
        _dimensions = (futures[1].data?['dimensions'] as List? ?? []).cast<Map<String, dynamic>>();
        _sources = (futures[2].data?['sources'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _triggerSnapshot() async {
    setState(() => _snapshotLoading = true);
    try {
      await _apiClient.post<void>('/v1/analytics/quality-snapshot');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot triggered — data will update shortly')),
        );
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _snapshotLoading = false);
    }
  }

  // Compute summary KPIs from trends
  double get _overallScore {
    if (_trends.isEmpty) return 0;
    return (_trends.last['overall_score'] as num? ?? 0).toDouble();
  }

  double get _prevScore {
    if (_trends.length < 2) return _overallScore;
    return (_trends[_trends.length - 2]['overall_score'] as num? ?? 0).toDouble();
  }

  bool get _isTrendUp => _overallScore >= _prevScore;

  Color _dimensionColor(double score) {
    if (score >= 90) return AppColors.success;
    if (score >= 75) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Quality Analytics', style: AppTextStyles.titleLarge),
        actions: [
          // Entity type filter
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedEntityType ?? '(All)',
                dropdownColor: AppColors.surface,
                style: AppTextStyles.bodyMedium,
                items: _entityTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) {
                  setState(() => _selectedEntityType = v == '(All)' ? null : v);
                  _loadAll();
                },
              ),
            ),
          ),
          if (_userRole == 'admin' || _userRole == 'super_admin')
            _snapshotLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(
                    onPressed: _triggerSnapshot,
                    icon: Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                    label: Text('Snapshot', style: TextStyle(color: AppColors.primary)),
                  ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 8),
          Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadAll, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKpiRow(),
          const SizedBox(height: 32),
          _buildTrendsSection(),
          const SizedBox(height: 32),
          _buildDimensionsSection(),
          const SizedBox(height: 32),
          _buildSourceRankingSection(),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    final total = _sources.fold<int>(0, (s, e) => s + ((e['record_count'] as num?)?.toInt() ?? 0));
    final violations = _dimensions.where((d) {
      final score = (d['score'] as num? ?? 100).toDouble();
      return score < 75;
    }).length;

    return Row(
      children: [
        _kpiCard('Total Records', _fmt(total), Icons.dataset_outlined, AppColors.cyan),
        const SizedBox(width: 16),
        _kpiCard('Quality Score', '${_overallScore.toStringAsFixed(1)}%',
            Icons.verified_outlined, _dimensionColor(_overallScore)),
        const SizedBox(width: 16),
        _kpiCard('30d Trend', _isTrendUp ? '↑ Improving' : '↓ Declining',
            _isTrendUp ? Icons.trending_up : Icons.trending_down,
            _isTrendUp ? AppColors.success : AppColors.error),
        const SizedBox(width: 16),
        _kpiCard('Dim Violations', '$violations / ${_dimensions.length}',
            Icons.warning_amber_outlined, violations > 0 ? AppColors.warning : AppColors.success),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(value, style: AppTextStyles.statValue.copyWith(color: color, fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.statLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUALITY TREND (30 DAYS)',
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _trends.isEmpty
              ? Center(child: Text('No trend data', style: AppTextStyles.bodySmall))
              : _buildSparkline(),
        ),
      ],
    );
  }

  Widget _buildSparkline() {
    final scores = _trends
        .map((t) => (t['overall_score'] as num? ?? 0).toDouble())
        .toList();
    if (scores.isEmpty) return const SizedBox.shrink();
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final range = (maxScore - minScore).clamp(1.0, 100.0);

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight - 24;

      return Stack(
        children: [
          CustomPaint(
            size: Size(w, h),
            painter: _SparklinePainter(scores: scores, minScore: minScore, range: range,
                color: AppColors.primary),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Text('${maxScore.toStringAsFixed(1)}%', style: AppTextStyles.bodySmall),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Text('${minScore.toStringAsFixed(1)}%', style: AppTextStyles.bodySmall),
          ),
          if (_trends.isNotEmpty)
            Positioned(
              top: 0,
              right: 0,
              child: Text('Latest: ${scores.last.toStringAsFixed(1)}%',
                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
            ),
        ],
      );
    });
  }

  Widget _buildDimensionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUALITY DIMENSIONS', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 16),
        if (_dimensions.isEmpty)
          Text('No dimension data available', style: AppTextStyles.bodySmall)
        else
          ...(_dimensions.map((d) {
            final name = d['dimension'] as String? ?? '';
            final score = (d['score'] as num? ?? 0).toDouble();
            final color = _dimensionColor(score);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: AppTextStyles.labelLarge),
                      Row(children: [
                        Icon(
                          score >= 90 ? Icons.check_circle_outline
                              : score >= 75 ? Icons.warning_amber_outlined
                              : Icons.error_outline,
                          color: color,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text('${score.toStringAsFixed(1)}%',
                            style: AppTextStyles.labelLarge.copyWith(color: color)),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          })),
      ],
    );
  }

  Widget _buildSourceRankingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SOURCE SYSTEM RANKING', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 16),
        if (_sources.isEmpty)
          Text('No source data available', style: AppTextStyles.bodySmall)
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text('RANK', style: AppTextStyles.tableHeader)),
                      Expanded(child: Text('SOURCE', style: AppTextStyles.tableHeader)),
                      SizedBox(width: 80, child: Text('RECORDS', style: AppTextStyles.tableHeader, textAlign: TextAlign.right)),
                      SizedBox(width: 80, child: Text('SCORE', style: AppTextStyles.tableHeader, textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ..._sources.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final score = (s['quality_score'] as num? ?? 0).toDouble();
                  final rankNum = s['rank'] as int? ?? (i + 1);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text('#$rankNum',
                                  style: AppTextStyles.tableCell.copyWith(
                                      color: rankNum == 1 ? AppColors.warning : null)),
                            ),
                            Expanded(child: Text(s['source_system'] as String? ?? '—',
                                style: AppTextStyles.tableCell)),
                            SizedBox(
                              width: 80,
                              child: Text(_fmt(s['record_count'] as int? ?? 0),
                                  style: AppTextStyles.tableCell, textAlign: TextAlign.right),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text('${score.toStringAsFixed(1)}%',
                                  style: AppTextStyles.tableCell.copyWith(color: _dimensionColor(score)),
                                  textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      ),
                      if (i < _sources.length - 1) const Divider(height: 1),
                    ],
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> scores;
  final double minScore;
  final double range;
  final Color color;

  const _SparklinePainter({
    required this.scores,
    required this.minScore,
    required this.range,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (scores.length - 1);

    for (int i = 0; i < scores.length; i++) {
      final x = i * stepX;
      final y = size.height - ((scores[i] - minScore) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo((scores.length - 1) * stepX, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw last point dot
    final lastX = (scores.length - 1) * stepX;
    final lastY = size.height - ((scores.last - minScore) / range * size.height);
    canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.scores != scores || old.color != color;
}
