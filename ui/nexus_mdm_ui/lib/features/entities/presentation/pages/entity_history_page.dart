import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EntityHistoryPage extends StatefulWidget {
  final String entityId;
  const EntityHistoryPage({super.key, required this.entityId});

  @override
  State<EntityHistoryPage> createState() => _EntityHistoryPageState();
}

class _EntityHistoryPageState extends State<EntityHistoryPage> {
  final _apiClient = ApiClient();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String _error = '';
  int _total = 0;
  final int _pageSize = 20;

  DateTime? _asOfDate;
  Map<String, dynamic>? _asOfData;
  bool _asOfLoading = false;
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/history',
        queryParameters: {'page': 1, 'page_size': _pageSize},
      );
      final items = (resp.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _history = items;
        _total = resp.data?['total'] as int? ?? items.length;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _queryAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() { _asOfDate = picked; _asOfLoading = true; _asOfData = null; });
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/as-of',
        queryParameters: {'as_of': picked.toIso8601String()},
      );
      setState(() {
        _asOfData = resp.data?['entity'] as Map<String, dynamic>? ?? resp.data ?? {};
        _asOfLoading = false;
      });
    } catch (e) {
      setState(() { _asOfLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Version History', style: AppTextStyles.titleLarge),
        actions: [
          TextButton.icon(
            onPressed: _queryAsOf,
            icon: Icon(Icons.schedule, color: AppColors.primary),
            label: Text('View As Of', style: TextStyle(color: AppColors.primary)),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : Row(
                  children: [
                    Expanded(flex: 2, child: _buildTimeline()),
                    if (_asOfData != null || _asOfLoading)
                      Expanded(child: _buildAsOfPanel()),
                    if (_expandedIndex != null && _asOfData == null && !_asOfLoading)
                      Expanded(child: _buildVersionDetail(_history[_expandedIndex!])),
                  ],
                ),
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
          FilledButton(onPressed: _loadHistory, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: AppColors.secondaryText),
            const SizedBox(height: 16),
            Text('No history available',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_total > _pageSize)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Showing $_pageSize of $_total versions',
                style: AppTextStyles.bodySmall),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _history.length,
            itemBuilder: (ctx, i) => _buildHistoryTile(i),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTile(int i) {
    final item = _history[i];
    final isActive = item['status'] == 'Active';
    final isExpanded = _expandedIndex == i;
    return InkWell(
      onTap: () => setState(() => _expandedIndex = isExpanded ? null : i),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.secondaryText,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
                if (i < _history.length - 1)
                  Container(width: 2, height: 80, color: AppColors.surface),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isExpanded ? AppColors.elevatedCard : AppColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: isExpanded
                    ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isActive ? AppColors.primary : AppColors.secondaryText)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item['status'] as String? ?? 'Unknown',
                          style: TextStyle(
                            color: isActive ? AppColors.primary : AppColors.secondaryText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('v${item['version_number'] ?? i + 1}',
                          style: AppTextStyles.labelLarge),
                      const Spacer(),
                      Text(_fmt(item['recorded_at'] as String?),
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                  if (item['change_reason'] != null) ...[
                    const SizedBox(height: 4),
                    Text(item['change_reason'] as String,
                        style: AppTextStyles.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (item['valid_from'] != null || item['valid_to'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Valid: ${_fmt(item['valid_from'] as String?)} → ${item['valid_to'] != null ? _fmt(item['valid_to'] as String?) : 'present'}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionDetail(Map<String, dynamic> version) {
    final attrs = version['attributes'] as Map<String, dynamic>? ?? {};
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.primary.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Version Snapshot', style: AppTextStyles.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _expandedIndex = null),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: attrs.isEmpty
                ? Center(child: Text('No attributes', style: AppTextStyles.bodyMedium))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: attrs.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(e.key, style: AppTextStyles.bodySmall),
                          ),
                          Expanded(
                            child: Text(e.value.toString(), style: AppTextStyles.bodyMedium),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAsOfPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.primary.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'As Of: ${_asOfDate != null ? _fmt(_asOfDate!.toIso8601String()) : ''}',
                    style: AppTextStyles.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() { _asOfData = null; _asOfDate = null; }),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_asOfLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_asOfData != null)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _asOfData!.entries.map((e) {
                  if (e.key == 'attributes' && e.value is Map) {
                    return _buildAttrsSection(e.value as Map);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 120, child: Text(e.key, style: AppTextStyles.bodySmall)),
                        Expanded(child: Text(e.value.toString(), style: AppTextStyles.bodyMedium)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttrsSection(Map attrs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Attributes',
              style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
        ),
        ...attrs.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(e.key.toString(), style: AppTextStyles.bodySmall)),
              Expanded(child: Text(e.value.toString(), style: AppTextStyles.bodyMedium)),
            ],
          ),
        )),
      ],
    );
  }
}
