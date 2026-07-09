import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/entity_type_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class EntityTypesPage extends StatefulWidget {
  const EntityTypesPage({super.key});

  @override
  State<EntityTypesPage> createState() => _EntityTypesPageState();
}

class _EntityTypesPageState extends State<EntityTypesPage> {
  final _repo = GetIt.instance<EntityTypeRepository>();
  List<EntityTypeModel> _types = [];
  bool _loading = true;
  String? _error;
  bool _showAddForm = false;

  String _tenantId = '';

  // Add form state
  final _addFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  String _icon = '📄';
  // ignore: prefer_final_fields — mutated in setState when user picks a color
  String _color = '#599B81';
  bool _addSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initTenantAndLoad();
  }

  Future<void> _initTenantAndLoad() async {
    _tenantId = await AuthManager.getTenantId() ?? '';
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.listEntityTypes(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<EntityTypeModel>>(:final data):
        setState(() {
          _types = data;
          _loading = false;
        });
      case Failure<List<EntityTypeModel>>(:final exception):
        setState(() {
          _error = exception.message;
          _loading = false;
        });
    }
  }

  Future<void> _submitAdd() async {
    if (!_addFormKey.currentState!.validate()) return;
    setState(() => _addSubmitting = true);
    final result = await _repo.createEntityType(
      tenantId: _tenantId,
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      icon: _icon,
      color: _color,
      seqPrefix: _prefixCtrl.text.trim(),
      seqFormat: '${_prefixCtrl.text.trim().toUpperCase()}-{YYYYMM}-{SEQ:6}',
    );
    if (!mounted) return;
    setState(() => _addSubmitting = false);
    switch (result) {
      case Success():
        setState(() => _showAddForm = false);
        _nameCtrl.clear();
        _codeCtrl.clear();
        _descCtrl.clear();
        _prefixCtrl.clear();
        _load();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        ));
    }
  }

  void _showSeqConfigDialog(EntityTypeModel et) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _SeqConfigDialog(entityType: et, tenantId: _tenantId),
    );
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
                    : _buildContent(),
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
              Text('Entity Types', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('${_types.length} types defined',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Add Entity Type',
            onTap: () => setState(() => _showAddForm = !_showAddForm),
          ),
        ],
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
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_types.isEmpty && !_showAddForm)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text('No entity types defined yet.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.secondaryText)),
              ),
            ),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _types.map((et) => _EntityTypeCard(
              entityType: et,
              onSettingsTap: () => _showSeqConfigDialog(et),
            )).toList(),
          ),
          if (_showAddForm) ...[
            const SizedBox(height: 24),
            _buildAddForm(),
          ],
        ],
      ),
    );
  }

  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Form(
        key: _addFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Entity Type', style: AppTextStyles.titleSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AdminFormField(
                    label: 'NAME',
                    controller: _nameCtrl,
                    hint: 'Customer',
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminFormField(
                    label: 'CODE',
                    controller: _codeCtrl,
                    hint: 'customer',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!RegExp(r'^[a-z_]+$').hasMatch(v)) {
                        return 'Lowercase + underscores only';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminFormField(
                    label: 'SEQ PREFIX',
                    controller: _prefixCtrl,
                    hint: 'CUST',
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminFormField(
              label: 'DESCRIPTION',
              controller: _descCtrl,
              hint: 'Represents a customer entity',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Icon picker (simplified)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminSectionHeader(label: 'ICON'),
                    Wrap(
                      spacing: 8,
                      children: ['📄', '👤', '🏢', '📦', '💼', '📍', '🔧']
                          .map((e) => GestureDetector(
                                onTap: () => setState(() => _icon = e),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _icon == e
                                        ? AppColors.primary
                                            .withValues(alpha: 0.2)
                                        : AppColors.elevatedCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _icon == e
                                          ? AppColors.primary
                                          : AppColors.divider,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 18)),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _showAddForm = false),
                  child: Text('Cancel',
                      style: AppTextStyles.buttonMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
                const SizedBox(width: 12),
                AdminGradientButton(
                  label: 'Create Entity Type',
                  loading: _addSubmitting,
                  onTap: _submitAdd,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entity type card
// ─────────────────────────────────────────────────────────────────────────────

class _EntityTypeCard extends StatelessWidget {
  final EntityTypeModel entityType;
  final VoidCallback onSettingsTap;
  const _EntityTypeCard(
      {required this.entityType, required this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final et = entityType;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(et.icon,
                      style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(et.name,
                    style: AppTextStyles.titleSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    size: 16, color: AppColors.secondaryText),
                onPressed: onSettingsTap,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Sequence config',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SeqChip(label: et.seqFormat),
              const Spacer(),
              AdminStatusChip(status: et.isActive ? 'Active' : 'Inactive'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Next: ${et.seqPrefix}-${(et.seqCurrent + 1).toString().padLeft(6, '0')}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.cyan,
              fontFamily: 'monospace',
            ),
          ),
          if (et.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(et.description,
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class _SeqChip extends StatelessWidget {
  final String label;
  const _SeqChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTextStyles.chipLabel.copyWith(
          color: AppColors.cyan,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sequence config dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SeqConfigDialog extends StatefulWidget {
  final EntityTypeModel entityType;
  final String tenantId;
  const _SeqConfigDialog(
      {required this.entityType, required this.tenantId});

  @override
  State<_SeqConfigDialog> createState() => _SeqConfigDialogState();
}

class _SeqConfigDialogState extends State<_SeqConfigDialog> {
  final _repo = GetIt.instance<EntityTypeRepository>();
  String? _nextSeq;
  bool _loading = false;

  Future<void> _previewNext() async {
    setState(() => _loading = true);
    final result = await _repo.nextSequence(
        widget.tenantId, widget.entityType.code);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Success<String>) _nextSeq = result.data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final et = widget.entityType;
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Sequence Config', style: AppTextStyles.titleMedium),
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
              const SizedBox(height: 4),
              Text(et.name,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
              const SizedBox(height: 20),
              _row('Prefix', et.seqPrefix),
              _row('Format', et.seqFormat),
              _row('Current #', et.seqCurrent.toString()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(
                        _nextSeq ?? '—',
                        style: AppTextStyles.codeStyle.copyWith(
                          color: _nextSeq != null
                              ? AppColors.cyan
                              : AppColors.mutedText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _loading
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))
                      : OutlinedButton(
                          onPressed: _previewNext,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text('Preview Next'),
                        ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close',
                      style: AppTextStyles.buttonMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.mutedText)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.tableCell
                    .copyWith(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
