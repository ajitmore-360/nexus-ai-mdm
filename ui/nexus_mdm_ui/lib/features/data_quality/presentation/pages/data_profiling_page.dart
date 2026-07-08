import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';

class DataProfilingPage extends StatefulWidget {
  const DataProfilingPage({super.key});

  @override
  State<DataProfilingPage> createState() => _DataProfilingPageState();
}

class _DataProfilingPageState extends State<DataProfilingPage> {
  final _apiClient = ApiClient();

  String _selectedEntityType = AppConstants.entityTypes.first;
  Map<String, dynamic>? _profile;
  bool _loading = false;
  bool _running = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = ''; _profile = null; });
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '${AppConstants.dataProfilingBase}/$_selectedEntityType',
      );
      setState(() {
        _profile = resp.data?['profile'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      // 404 = no profile yet (not an error state)
      setState(() {
        _profile = null;
        _loading = false;
        if (!e.toString().contains('404') && !e.toString().contains('Not Found')) {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _runProfile() async {
    setState(() => _running = true);
    try {
      final resp = await _apiClient.post<Map<String, dynamic>>(
        '${AppConstants.dataProfilingBase}/$_selectedEntityType/run',
      );
      final profile = resp.data?['profile'] as Map<String, dynamic>?;
      setState(() {
        _profile = profile;
        _running = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profiling complete')),
        );
      }
    } catch (e) {
      setState(() => _running = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Map<String, dynamic> get _attributes {
    return (_profile?['attributes'] as Map<String, dynamic>?) ?? {};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Data Profiling', style: AppTextStyles.titleLarge),
        actions: [
          // Entity type selector
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedEntityType,
                dropdownColor: AppColors.surface,
                style: AppTextStyles.bodyMedium,
                items: AppConstants.entityTypes
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedEntityType = v);
                  _loadProfile();
                },
              ),
            ),
          ),
          _running
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : FilledButton.icon(
                  onPressed: _runProfile,
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Run Profile'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProfile),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : _profile == null
                  ? _buildEmpty()
                  : _buildProfile(),
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
          FilledButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 80, color: AppColors.secondaryText),
          const SizedBox(height: 20),
          Text('No profile available', style: AppTextStyles.titleMedium.copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 8),
          Text(
            'Click "Run Profile" to analyze $_selectedEntityType entities',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _running
              ? const CircularProgressIndicator()
              : FilledButton.icon(
                  onPressed: _runProfile,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Run Profile'),
                ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    final recordCount = _profile!['record_count'] as int? ?? 0;
    final profiledAt = _profile!['profiled_at'] as String? ?? '';
    final attrs = _attributes;

    // Compute summary stats
    final nullRates = attrs.values
        .map((a) => ((a as Map?)?['null_rate'] as num? ?? 0).toDouble())
        .toList();
    final avgNullRate = nullRates.isEmpty
        ? 0.0
        : nullRates.fold(0.0, (s, r) => s + r) / nullRates.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          _buildSummaryRow(recordCount, attrs.length, avgNullRate, profiledAt),
          const SizedBox(height: 32),
          // Attribute detail table
          _buildAttributeTable(attrs),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int records, int attrCount, double avgNull, String profiledAt) {
    final fmtDate = profiledAt.isNotEmpty
        ? (DateTime.tryParse(profiledAt)?.toLocal().toString().substring(0, 16) ?? profiledAt)
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Profile: $_selectedEntityType', style: AppTextStyles.titleMedium),
            Text('Last run: $fmtDate', style: AppTextStyles.bodySmall),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _summaryCard('Total Records', _fmtNum(records), Icons.dataset_outlined, AppColors.cyan),
            const SizedBox(width: 12),
            _summaryCard('Attributes', '$attrCount', Icons.schema_outlined, AppColors.primary),
            const SizedBox(width: 12),
            _summaryCard('Avg Null Rate', '${(avgNull * 100).toStringAsFixed(1)}%',
                Icons.remove_circle_outline, avgNull < 0.05 ? AppColors.success : AppColors.warning),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: AppTextStyles.statValue.copyWith(fontSize: 22, color: color)),
                  Text(label, style: AppTextStyles.statLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributeTable(Map<String, dynamic> attrs) {
    if (attrs.isEmpty) {
      return Center(child: Text('No attribute data', style: AppTextStyles.bodySmall));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ATTRIBUTE STATISTICS', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(AppColors.elevatedCard),
              dataRowColor: WidgetStatePropertyAll(AppColors.cardSurface),
              columns: const [
                DataColumn(label: Text('Attribute')),
                DataColumn(label: Text('Null Rate'), numeric: true),
                DataColumn(label: Text('Distinct'), numeric: true),
                DataColumn(label: Text('Min')),
                DataColumn(label: Text('Max')),
                DataColumn(label: Text('Top Values')),
                DataColumn(label: Text('Formats')),
                DataColumn(label: Text('Outliers'), numeric: true),
              ],
              rows: attrs.entries.map((entry) {
                final name = entry.key;
                final a = entry.value as Map? ?? {};
                final nullRate = (a['null_rate'] as num? ?? 0).toDouble();
                final distinct = a['distinct_count'] as int? ?? 0;
                final min = a['min']?.toString() ?? '—';
                final max = a['max']?.toString() ?? '—';
                final topVals = (a['top_values'] as List? ?? []).take(3).join(', ');
                final outliers = (a['outlier_ids'] as List? ?? []).length;
                final nullColor = nullRate < 0.05
                    ? AppColors.success
                    : nullRate < 0.15
                        ? AppColors.warning
                        : AppColors.error;
                return DataRow(cells: [
                  DataCell(Text(name, style: AppTextStyles.labelLarge)),
                  DataCell(Text(
                    '${(nullRate * 100).toStringAsFixed(1)}%',
                    style: AppTextStyles.tableCell.copyWith(color: nullColor),
                  )),
                  DataCell(Text(_fmtNum(distinct), style: AppTextStyles.tableCell)),
                  DataCell(Text(min, style: AppTextStyles.tableCell)),
                  DataCell(Text(max, style: AppTextStyles.tableCell)),
                  DataCell(SizedBox(
                    width: 180,
                    child: Text(topVals.isEmpty ? '—' : topVals,
                        style: AppTextStyles.tableCell, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(SizedBox(
                    width: 160,
                    child: Wrap(
                      spacing: 4,
                      children: (a['format_patterns'] as Map? ?? {})
                          .keys
                          .take(3)
                          .map((k) => Chip(
                                label: Text(k.toString(), style: AppTextStyles.chipLabel),
                                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),
                  )),
                  DataCell(Text(
                    '$outliers',
                    style: AppTextStyles.tableCell.copyWith(
                        color: outliers > 0 ? AppColors.warning : null),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _fmtNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
