import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EnrichmentConfigPage extends StatefulWidget {
  const EnrichmentConfigPage({super.key});

  @override
  State<EnrichmentConfigPage> createState() => _EnrichmentConfigPageState();
}

class _EnrichmentConfigPageState extends State<EnrichmentConfigPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();

  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _configs = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String _error = '';

  late TabController _tabCtrl;

  static const _categoryIcons = <String, IconData>{
    'company': Icons.business_outlined,
    'person': Icons.person_outlined,
    'address': Icons.location_on_outlined,
    'email': Icons.email_outlined,
    'phone': Icons.phone_outlined,
    'identity': Icons.badge_outlined,
  };

  static const _categoryColors = <String, Color>{
    'company': AppColors.primary,
    'person': AppColors.cyan,
    'address': AppColors.success,
    'email': AppColors.warning,
    'phone': AppColors.error,
    'identity': AppColors.secondaryText,
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
        _api.get<Map<String, dynamic>>('/enrichment-providers'),
        _api.get<Map<String, dynamic>>('/enrichment-configs'),
        _api.get<Map<String, dynamic>>('/enrichment-requests'),
      ]);
      setState(() {
        _providers = (results[0].data?['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _configs = (results[1].data?['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _requests = (results[2].data?['data'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Map<String, dynamic>? _configFor(String providerCode) {
    try {
      return _configs.firstWhere((c) => c['provider_code'] == providerCode);
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleProvider(Map<String, dynamic> provider) async {
    final code = provider['provider_code'] as String;
    final existing = _configFor(code);
    final currentlyEnabled = existing?['is_enabled'] as bool? ?? false;
    if (existing == null && !currentlyEnabled) {
      await _showConfigDialog(provider, isNew: true);
    } else {
      try {
        await _api.put<Map<String, dynamic>>('/enrichment-configs/$code', data: {
          'is_enabled': !currentlyEnabled,
        });
        await _loadData();
      } catch (e) {
        _showSnack('Update failed: $e', isError: true);
      }
    }
  }

  Future<void> _showConfigDialog(Map<String, dynamic> provider,
      {bool isNew = false}) async {
    final code = provider['provider_code'] as String;
    final existing = _configFor(code);
    final apiKeyCtrl =
        TextEditingController(text: existing?['config']?['api_key'] as String? ?? '');
    bool autoEnrich = existing?['auto_enrich'] as bool? ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.cardSurface,
          title: Text(
              '${isNew ? 'Enable' : 'Configure'} ${provider['display_name']}',
              style: AppTextStyles.titleMedium),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (provider['description'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(provider['description'] as String,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
              TextField(
                controller: apiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'Enter your ${provider['display_name']} API key',
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider)),
                ),
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text('Auto-enrich new entities',
                      style: AppTextStyles.bodyMedium),
                ),
                Switch(
                  value: autoEnrich,
                  onChanged: (v) => setLocal(() => autoEnrich = v),
                  activeThumbColor: AppColors.primary,
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: Text(isNew ? 'Enable' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.put<Map<String, dynamic>>('/enrichment-configs/$code', data: {
        'is_enabled': true,
        'auto_enrich': autoEnrich,
        'config': apiKeyCtrl.text.trim().isNotEmpty
            ? {'api_key': apiKeyCtrl.text.trim()}
            : <String, dynamic>{},
      });
      await _loadData();
      _showSnack('${provider['display_name']} configured');
    } catch (e) {
      _showSnack('Save failed: $e', isError: true);
    }
  }

  Future<void> _disableProvider(String code, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Disable $name', style: AppTextStyles.titleMedium),
        content: Text('Enrichment requests for this provider will stop.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.put<Map<String, dynamic>>('/enrichment-configs/$code',
          data: {'is_enabled': false});
      await _loadData();
    } catch (e) {
      _showSnack('Disable failed: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

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
            Tab(text: 'Providers (${_providers.length})'),
            Tab(text: 'Request Log (${_requests.length})'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? _buildError()
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [_buildProviders(), _buildRequestLog()],
                    ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final enabledCount = _configs.where((c) => c['is_enabled'] == true).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Third-Party Enrichment', style: AppTextStyles.titleMedium),
              Text('Enrich entity records with external data sources',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ]),
          ),
          _chip('$enabledCount active',
              AppColors.success.withValues(alpha: 0.12), AppColors.success),
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

  Widget _buildProviders() {
    if (_providers.isEmpty) {
      return const Center(child: Text('No enrichment providers available.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _providers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _providerCard(_providers[i]),
    );
  }

  Widget _providerCard(Map<String, dynamic> provider) {
    final code = provider['provider_code'] as String? ?? '';
    final category = provider['category'] as String? ?? '';
    final config = _configFor(code);
    final isEnabled = config?['is_enabled'] as bool? ?? false;
    final autoEnrich = config?['auto_enrich'] as bool? ?? false;
    final quotaUsed = config?['quota_used_today'] as int? ?? 0;
    final quotaLimit = config?['daily_quota'] as int?;
    final catColor = _categoryColors[category] ?? AppColors.primary;
    final catIcon = _categoryIcons[category] ?? Icons.data_object_outlined;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isEnabled
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(catIcon, color: catColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(provider['display_name'] as String? ?? '',
                    style: AppTextStyles.titleSmall),
                Text(provider['category'] as String? ?? '',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText)),
              ]),
            ),
            if (isEnabled && config != null)
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: AppColors.secondaryText, size: 18),
                tooltip: 'Configure',
                onPressed: () => _showConfigDialog(provider),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            const SizedBox(width: 4),
            Switch(
              value: isEnabled,
              onChanged: (_) => isEnabled
                  ? _disableProvider(code, provider['display_name'] as String? ?? '')
                  : _toggleProvider(provider),
              activeThumbColor: AppColors.success,
            ),
          ]),
          if (provider['description'] != null) ...[
            const SizedBox(height: 10),
            Text(provider['description'] as String,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (isEnabled) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(children: [
              _infoChip(
                  Icons.auto_fix_high_outlined,
                  autoEnrich ? 'Auto-enrich on' : 'Auto-enrich off',
                  autoEnrich ? AppColors.primary : AppColors.secondaryText),
              const SizedBox(width: 8),
              if (quotaLimit != null)
                _infoChip(
                    Icons.bar_chart_outlined,
                    '$quotaUsed / $quotaLimit today',
                    quotaUsed >= quotaLimit
                        ? AppColors.error
                        : AppColors.success),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _buildRequestLog() {
    if (_requests.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.history_outlined, size: 64, color: AppColors.secondaryText),
          const SizedBox(height: 16),
          Text('No enrichment requests yet', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text('Enable a provider and trigger enrichment to see results here.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _requestCard(_requests[i]),
    );
  }

  Widget _requestCard(Map<String, dynamic> req) {
    final status = req['status'] as String? ?? 'pending';
    final provider = req['provider_code'] as String? ?? '';
    final entityId = req['entity_id'] as String? ?? '';
    final createdAt = req['created_at'] as String? ?? '';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_outline;
      case 'failed':
        statusColor = AppColors.error;
        statusIcon = Icons.error_outline;
      case 'processing':
        statusColor = AppColors.warning;
        statusIcon = Icons.sync;
      default:
        statusColor = AppColors.secondaryText;
        statusIcon = Icons.pending_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Icon(statusIcon, color: statusColor, size: 22),
        title: Row(children: [
          Expanded(
              child: Text(provider,
                  style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis)),
          _chip(status, statusColor.withValues(alpha: 0.12), statusColor),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Entity: ${entityId.length > 20 ? '…${entityId.substring(entityId.length - 12)}' : entityId}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText)),
          if (createdAt.isNotEmpty)
            Text(_fmtDate(createdAt),
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText)),
          if (req['error_message'] != null)
            Text(req['error_message'] as String,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: color)),
    ]);
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
