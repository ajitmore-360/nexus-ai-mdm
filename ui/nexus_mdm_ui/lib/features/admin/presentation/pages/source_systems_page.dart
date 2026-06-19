import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/source_systems_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class SourceSystemsPage extends StatefulWidget {
  const SourceSystemsPage({super.key});

  @override
  State<SourceSystemsPage> createState() => _SourceSystemsPageState();
}

class _SourceSystemsPageState extends State<SourceSystemsPage> {
  final _repo = GetIt.instance<SourceSystemsRepository>();
  List<SourceSystemModel> _sources = [];
  bool _loading = true;
  String? _error;
  final Set<String> _testingIds = {};

  static const _tenantId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await _repo.listSourceSystems(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<SourceSystemModel>>(:final data):
        setState(() { _sources = data; _loading = false; });
      case Failure<List<SourceSystemModel>>(:final exception):
        setState(() { _error = exception.message; _loading = false; });
    }
  }

  Future<void> _testConnection(String id) async {
    setState(() => _testingIds.add(id));
    final result = await _repo.testConnection(id);
    if (!mounted) return;
    setState(() => _testingIds.remove(id));
    final ok = result is Success<bool> && result.data;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.cardSurface,
      content: Text(
        ok ? 'Connection successful!' : 'Connection failed.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: ok ? AppColors.success : AppColors.error,
        ),
      ),
    ));
    if (ok) _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _ConfirmDeleteDialog(),
    );
    if (confirm != true) {
      return;
    }
    await _repo.deleteSourceSystem(id);
    if (!mounted) {
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _buildGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Source Systems', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('${_sources.length} connectors configured',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Add Source',
            onTap: () => _showAddDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _AddSourceDialog(
        tenantId: _tenantId,
        onCreated: _load,
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_sources.isEmpty) {
      return Center(
        child: Text('No source systems configured yet.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 3 : 2;
        final itemWidth =
            (constraints.maxWidth - (crossCount - 1) * 16) / crossCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _sources
              .map((s) => SizedBox(
                    width: itemWidth,
                    child: _SourceCard(
                      source: s,
                      testing: _testingIds.contains(s.id),
                      onTest: () => _testConnection(s.id),
                      onDelete: () => _delete(s.id),
                    ),
                  ))
              .toList(),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source card
// ─────────────────────────────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final SourceSystemModel source;
  final bool testing;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _SourceCard({
    required this.source,
    required this.testing,
    required this.onTest,
    required this.onDelete,
  });

  String get _statusLabel {
    if (!source.isActive) { return 'Inactive'; }
    if (source.isConnected) { return 'Connected'; }
    if (source.lastSyncStatus.isNotEmpty &&
        source.lastSyncStatus != 'success') { return 'Error'; }
    return 'Config needed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: source.isConnected
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Center(
                  child: Text(source.icon,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.name,
                        style: AppTextStyles.titleSmall,
                        overflow: TextOverflow.ellipsis),
                    Text(source.connectorType,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.secondaryText)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.error),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Status + trust weight
          Row(
            children: [
              AdminStatusChip(status: _statusLabel),
              const Spacer(),
              _TrustBadge(weight: source.trustWeight),
            ],
          ),
          const SizedBox(height: 12),

          // Sync mode + last sync
          if (source.lastSyncAt != null)
            Text(
              'Last sync: ${_formatAgo(source.lastSyncAt!)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText),
            ),
          const SizedBox(height: 12),

          // Entity types chips
          if (source.entityTypes.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: source.entityTypes
                  .map((e) => _EntityTypeTag(label: e))
                  .toList(),
            ),
          const SizedBox(height: 16),

          // Test connection button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: testing ? null : onTest,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: source.isConnected
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.primary.withValues(alpha: 0.5),
                ),
                foregroundColor:
                    source.isConnected ? AppColors.success : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  : const Text('Test Connection'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _TrustBadge extends StatelessWidget {
  final double weight;
  const _TrustBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    final pct = (weight * 100).round();
    final color = weight >= 0.7
        ? AppColors.success
        : weight >= 0.4
            ? AppColors.warning
            : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Trust ',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.mutedText)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text('$pct%',
              style: AppTextStyles.badgeLabel.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _EntityTypeTag extends StatelessWidget {
  final String label;
  const _EntityTypeTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(label,
          style: AppTextStyles.badgeLabel.copyWith(
              color: AppColors.secondaryText, fontSize: 10)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add source dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddSourceDialog extends StatefulWidget {
  final String tenantId;
  final VoidCallback onCreated;
  const _AddSourceDialog(
      {required this.tenantId, required this.onCreated});

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _repo = GetIt.instance<SourceSystemsRepository>();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _connectorType = 'REST_API';
  String _syncMode = 'pull';
  double _trustWeight = 0.7;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final result = await _repo.createSourceSystem(
      tenantId: widget.tenantId,
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      connectorType: _connectorType,
      description: _descCtrl.text.trim(),
      icon: _connectorIcon(_connectorType),
      trustWeight: _trustWeight,
      priority: 1,
      entityTypes: const [],
      syncMode: _syncMode,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success():
        widget.onCreated();
        Navigator.of(context).pop();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.error)),
        ));
    }
  }

  String _connectorIcon(String type) {
    switch (type) {
      case 'SALESFORCE': return '☁️';
      case 'SAP': return '🏭';
      case 'ORACLE': return '🔶';
      case 'HUBSPOT': return '🔶';
      case 'JDBC': return '🗄️';
      case 'S3': return '🪣';
      case 'KAFKA': return '📨';
      default: return '🔌';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Add Source System',
                      style: AppTextStyles.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.secondaryText),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AdminFormField(
                            label: 'NAME',
                            controller: _nameCtrl,
                            hint: 'Salesforce CRM',
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: AdminFormField(
                            label: 'CODE',
                            controller: _codeCtrl,
                            hint: 'salesforce_crm',
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (!RegExp(r'^[a-z_][a-z0-9_]*$')
                                  .hasMatch(v)) {
                                return 'snake_case only';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AdminDropdownField<String>(
                      label: 'CONNECTOR TYPE',
                      value: _connectorType,
                      items: const [
                        'REST_API',
                        'SALESFORCE',
                        'SAP',
                        'ORACLE',
                        'HUBSPOT',
                        'JDBC',
                        'S3',
                        'KAFKA',
                        'MANUAL',
                      ],
                      onChanged: (v) =>
                          setState(() => _connectorType = v!),
                    ),
                    const SizedBox(height: 14),
                    AdminFormField(
                      label: 'DESCRIPTION',
                      controller: _descCtrl,
                      hint: 'Primary CRM source',
                    ),
                    const SizedBox(height: 14),
                    AdminDropdownField<String>(
                      label: 'SYNC MODE',
                      value: _syncMode,
                      items: const ['pull', 'push', 'realtime', 'manual'],
                      onChanged: (v) => setState(() => _syncMode = v!),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AdminSectionHeader(label: 'TRUST WEIGHT'),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.elevatedCard,
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: AppColors.divider),
                              ),
                              child: Text(
                                '${(_trustWeight * 100).round()}%',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor:
                                AppColors.primary.withValues(alpha: 0.2),
                            thumbColor: AppColors.primary,
                            overlayColor:
                                AppColors.primary.withValues(alpha: 0.1),
                          ),
                          child: Slider(
                            value: _trustWeight,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            onChanged: (v) =>
                                setState(() => _trustWeight = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: AppTextStyles.buttonMedium
                            .copyWith(color: AppColors.secondaryText)),
                  ),
                  const SizedBox(width: 12),
                  AdminGradientButton(
                    label: 'Add Source',
                    loading: _submitting,
                    onTap: _submit,
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

// ─────────────────────────────────────────────────────────────────────────────
// Confirm delete dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 40),
            const SizedBox(height: 12),
            Text('Remove Source System?',
                style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This will remove the connector configuration. '
              'Existing synced data will not be deleted.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel',
                      style: AppTextStyles.buttonMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.4)),
                    ),
                    child: Text('Remove',
                        style: AppTextStyles.buttonMedium
                            .copyWith(color: AppColors.error)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
