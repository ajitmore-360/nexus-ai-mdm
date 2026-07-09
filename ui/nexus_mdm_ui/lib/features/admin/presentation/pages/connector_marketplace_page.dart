import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class ConnectorMarketplacePage extends StatefulWidget {
  const ConnectorMarketplacePage({super.key});

  @override
  State<ConnectorMarketplacePage> createState() => _ConnectorMarketplacePageState();
}

class _ConnectorMarketplacePageState extends State<ConnectorMarketplacePage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();

  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _instances = [];
  bool _loading = true;
  String _error = '';
  String _filterCategory = 'All';
  String _searchQuery = '';

  late TabController _tabCtrl;

  static const _categoryColors = <String, Color>{
    'CRM': AppColors.cyan,
    'ERP': AppColors.primary,
    'Data Warehouse': AppColors.warning,
    'Cloud Storage': AppColors.success,
    'Marketing': AppColors.error,
    'E-commerce': AppColors.warning,
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final results = await Future.wait([
        _api.get<Map<String, dynamic>>('/connector-catalog'),
        _api.get<Map<String, dynamic>>('/connectors'),
      ]);
      setState(() {
        _catalog = (results[0].data?['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _instances = (results[1].data?['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<String> get _categories {
    final cats = <String>{'All'};
    for (final c in _catalog) {
      final cat = c['category'] as String?;
      if (cat != null) cats.add(cat);
    }
    return cats.toList();
  }

  List<Map<String, dynamic>> get _filteredCatalog {
    return _catalog.where((c) {
      final matchCat = _filterCategory == 'All' || c['category'] == _filterCategory;
      final matchSearch = _searchQuery.isEmpty ||
          (c['display_name'] as String? ?? '')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (c['vendor'] as String? ?? '')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
  }

  Future<void> _addInstance(Map<String, dynamic> connector) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Connect ${connector['display_name']}',
            style: AppTextStyles.titleMedium),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Give this connector instance a name.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Instance name',
              hintText: '${connector['display_name']} Production',
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.divider)),
            ),
            style: AppTextStyles.bodyMedium,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _api.post<Map<String, dynamic>>('/connectors', data: {
        'connector_code': connector['connector_code'],
        'instance_name': nameCtrl.text.trim(),
        'config': <String, dynamic>{},
      });
      await _loadData();
      _showSnack('Connector added successfully');
      _tabCtrl.animateTo(1);
    } catch (e) {
      _showSnack('Failed to add connector: $e', isError: true);
    }
  }

  Future<void> _testInstance(String id, String name) async {
    try {
      final resp = await _api.post<Map<String, dynamic>>('/connectors/$id/test', data: {});
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final ms = data?['latency_ms'] ?? '-';
      _showSnack('$name: connected ($ms ms)');
    } catch (e) {
      _showSnack('Connection test failed: $e', isError: true);
    }
  }

  Future<void> _deleteInstance(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Remove $name', style: AppTextStyles.titleMedium),
        content: Text('This will disconnect the integration.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete<void>('/connectors/$id');
      await _loadData();
    } catch (e) {
      _showSnack('Remove failed: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  bool _isConnected(String code) =>
      _instances.any((i) => i['connector_code'] == code);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.secondaryText,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Marketplace'),
            Tab(text: 'Connected (${_instances.length})'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? _buildError()
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [_buildCatalog(), _buildInstances()],
                    ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.extension_outlined, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Certified Connectors', style: AppTextStyles.titleMedium),
              Text('Connect Nexus MDM to your enterprise systems',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ]),
          ),
          Text('${_catalog.length} connectors available',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        const SizedBox(height: 12),
        Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        const SizedBox(height: 12),
        TextButton(onPressed: _loadData, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildCatalog() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search connectors…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider)),
                ),
                style: AppTextStyles.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _filterCategory,
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _filterCategory = v ?? 'All'),
              dropdownColor: AppColors.surface,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryText),
              underline: const SizedBox(),
            ),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              childAspectRatio: 1.4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _filteredCatalog.length,
            itemBuilder: (_, i) => _catalogCard(_filteredCatalog[i]),
          ),
        ),
      ],
    );
  }

  Widget _catalogCard(Map<String, dynamic> conn) {
    final code = conn['connector_code'] as String? ?? '';
    final category = conn['category'] as String? ?? '';
    final connected = _isConnected(code);
    final catColor = _categoryColors[category] ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: connected
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _initials(conn['display_name'] as String? ?? ''),
                  style: AppTextStyles.labelLarge.copyWith(color: catColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(conn['display_name'] as String? ?? '',
                    style: AppTextStyles.titleSmall,
                    overflow: TextOverflow.ellipsis),
                Text(conn['vendor'] as String? ?? '',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText)),
              ]),
            ),
            if (connected)
              const Icon(Icons.check_circle, color: AppColors.success, size: 16),
          ]),
          const SizedBox(height: 8),
          _chip(category, catColor.withValues(alpha: 0.12), catColor),
          const Spacer(),
          if (conn['description'] != null)
            Text(conn['description'] as String,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: connected
                ? OutlinedButton(
                    onPressed: () => _tabCtrl.animateTo(1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Connected'),
                  )
                : ElevatedButton(
                    onPressed: () => _addInstance(conn),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Connect'),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInstances() {
    if (_instances.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.extension_outlined, size: 64, color: AppColors.secondaryText),
          const SizedBox(height: 16),
          Text('No connected systems', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text('Browse the Marketplace to connect your first system.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _tabCtrl.animateTo(0),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Browse Marketplace'),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _instances.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _instanceCard(_instances[i]),
    );
  }

  Widget _instanceCard(Map<String, dynamic> inst) {
    final id = inst['connector_instance_id'] as String? ?? '';
    final name = inst['instance_name'] as String? ?? '';
    final code = inst['connector_code'] as String? ?? '';
    final isActive = inst['is_active'] as bool? ?? false;
    final syncStatus = inst['sync_status'] as String?;

    Color statusColor;
    IconData statusIcon;
    if (syncStatus == 'success') {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_outline;
    } else if (syncStatus == 'error') {
      statusColor = AppColors.error;
      statusIcon = Icons.error_outline;
    } else if (syncStatus == 'syncing') {
      statusColor = AppColors.warning;
      statusIcon = Icons.sync;
    } else {
      statusColor = AppColors.secondaryText;
      statusIcon = Icons.circle_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(_initials(name),
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ),
        title: Text(name, style: AppTextStyles.titleSmall),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            _chip(isActive ? 'Active' : 'Inactive',
                isActive
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.secondaryText.withValues(alpha: 0.12),
                isActive ? AppColors.success : AppColors.secondaryText),
            if (syncStatus != null)
              _chip(syncStatus,
                  statusColor.withValues(alpha: 0.12), statusColor),
          ]),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(statusIcon, color: statusColor, size: 20),
            tooltip: 'Test connection',
            onPressed: () => _testInstance(id, name),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
            tooltip: 'Remove',
            onPressed: () => _deleteInstance(id, name),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: AppTextStyles.chipLabel.copyWith(color: fg)),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}
