import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/entity_type_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class AttributeSchemaPage extends StatefulWidget {
  const AttributeSchemaPage({super.key});

  @override
  State<AttributeSchemaPage> createState() => _AttributeSchemaPageState();
}

class _AttributeSchemaPageState extends State<AttributeSchemaPage> {
  final _repo = GetIt.instance<EntityTypeRepository>();

  String _tenantId = '';

  List<EntityTypeModel> _entityTypes = [];
  String? _selectedCode;
  List<AttributeSchemaModel> _attributes = [];
  bool _loadingTypes = true;
  bool _loadingAttrs = false;
  String? _error;

  // Add attribute form
  bool _showAddRow = false;
  final _addFormKey = GlobalKey<FormState>();
  final _keyCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  String _dataType = 'string';
  bool _isRequired = false;
  bool _isPii = false;
  bool _addSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initTenantAndLoad();
  }

  Future<void> _initTenantAndLoad() async {
    _tenantId = await AuthManager.getTenantId() ?? '';
    _loadEntityTypes();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntityTypes() async {
    setState(() => _loadingTypes = true);
    final result = await _repo.listEntityTypes(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<EntityTypeModel>>(:final data):
        setState(() {
          _entityTypes = data;
          _loadingTypes = false;
          if (data.isNotEmpty) {
            _selectedCode = data.first.code;
            _loadAttributes();
          }
        });
      case Failure<List<EntityTypeModel>>(:final exception):
        setState(() {
          _error = exception.message;
          _loadingTypes = false;
        });
    }
  }

  Future<void> _loadAttributes() async {
    if (_selectedCode == null) return;
    setState(() {
      _loadingAttrs = true;
      _attributes = [];
    });
    final result =
        await _repo.listAttributes(_tenantId, _selectedCode!);
    if (!mounted) return;
    switch (result) {
      case Success<List<AttributeSchemaModel>>(:final data):
        setState(() {
          _attributes = data;
          _loadingAttrs = false;
        });
      case Failure<List<AttributeSchemaModel>>(:final exception):
        setState(() {
          _error = exception.message;
          _loadingAttrs = false;
        });
    }
  }

  Future<void> _deleteAttribute(String attrId) async {
    if (_selectedCode == null) return;
    final result =
        await _repo.deleteAttribute(_selectedCode!, attrId);
    if (!mounted) return;
    switch (result) {
      case Success():
        _loadAttributes();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        ));
    }
  }

  Future<void> _submitAddAttribute() async {
    if (!_addFormKey.currentState!.validate()) return;
    if (_selectedCode == null) return;
    setState(() => _addSubmitting = true);

    final result = await _repo.createAttribute(
      _selectedCode!,
      tenantId: _tenantId,
      attributeKey: _keyCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
      dataType: _dataType,
      isRequired: _isRequired,
      isPii: _isPii,
      displayOrder: _attributes.length + 1,
    );
    if (!mounted) return;
    setState(() => _addSubmitting = false);
    switch (result) {
      case Success():
        setState(() {
          _showAddRow = false;
          _keyCtrl.clear();
          _displayNameCtrl.clear();
          _isRequired = false;
          _isPii = false;
        });
        _loadAttributes();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        ));
    }
  }

  List<AttributeSchemaModel> get _systemAttrs =>
      _attributes.where((a) => a.isSystem).toList();
  List<AttributeSchemaModel> get _customAttrs =>
      _attributes.where((a) => !a.isSystem).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loadingTypes
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Text('Attribute Schema', style: AppTextStyles.headlineSmall),
          const SizedBox(width: 24),
          if (_entityTypes.isNotEmpty)
            AdminDropdownField<String>(
              label: '',
              value: _selectedCode ?? _entityTypes.first.code,
              items: _entityTypes.map((e) => e.code).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCode = v);
                _loadAttributes();
              },
            ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Add Attribute',
            onTap: () => setState(() => _showAddRow = !_showAddRow),
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
          TextButton(onPressed: _loadEntityTypes, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_entityTypes.isEmpty) {
      return Center(
        child: Text('No entity types found. Create one first.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText)),
      );
    }

    return _loadingAttrs
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildSystemColumn()),
                    const SizedBox(width: 20),
                    Expanded(child: _buildCustomColumn()),
                  ],
                ),
                if (_showAddRow) ...[
                  const SizedBox(height: 20),
                  _buildAddRow(),
                ],
              ],
            ),
          );
  }

  Widget _buildSystemColumn() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _colHeader('System Attributes', locked: true),
          if (_systemAttrs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No system attributes.',
                  style: AppTextStyles.bodySmall),
            )
          else
            ...List.generate(_systemAttrs.length, (i) {
              final a = _systemAttrs[i];
              return _AttrRow(
                attr: a,
                isSystem: true,
                isLast: i == _systemAttrs.length - 1,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCustomColumn() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _colHeader('Custom Attributes', locked: false),
          if (_customAttrs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No custom attributes yet. Add one below.',
                  style: AppTextStyles.bodySmall),
            )
          else
            ...List.generate(_customAttrs.length, (i) {
              final a = _customAttrs[i];
              return _AttrRow(
                attr: a,
                isSystem: false,
                isLast: i == _customAttrs.length - 1,
                onDelete: () => _deleteAttribute(a.id),
              );
            }),
        ],
      ),
    );
  }

  Widget _colHeader(String label, {required bool locked}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          if (locked)
            const Icon(Icons.lock_outline,
                size: 14, color: AppColors.mutedText),
          if (locked) const SizedBox(width: 6),
          Text(label,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11,
                letterSpacing: 1.0,
                color: AppColors.mutedText,
              )),
        ],
      ),
    );
  }

  Widget _buildAddRow() {
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
            Text('New Attribute', style: AppTextStyles.titleSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AdminFormField(
                    label: 'DISPLAY NAME',
                    controller: _displayNameCtrl,
                    hint: 'Customer ID',
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminFormField(
                    label: 'ATTRIBUTE KEY',
                    controller: _keyCtrl,
                    hint: 'customer_id',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(v)) {
                        return 'snake_case only';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminDropdownField<String>(
                    label: 'DATA TYPE',
                    value: _dataType,
                    items: const [
                      'string',
                      'number',
                      'boolean',
                      'date',
                      'datetime',
                      'enum',
                      'json',
                    ],
                    onChanged: (v) => setState(() => _dataType = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ToggleChip(
                  label: 'Required',
                  value: _isRequired,
                  onChanged: (v) => setState(() => _isRequired = v),
                ),
                const SizedBox(width: 12),
                _ToggleChip(
                  label: 'PII',
                  value: _isPii,
                  onChanged: (v) => setState(() => _isPii = v),
                  activeColor: AppColors.warning,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _showAddRow = false),
                  child: Text('Cancel',
                      style: AppTextStyles.buttonMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
                const SizedBox(width: 12),
                AdminGradientButton(
                  label: 'Add Attribute',
                  loading: _addSubmitting,
                  onTap: _submitAddAttribute,
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
// Attribute row
// ─────────────────────────────────────────────────────────────────────────────

class _AttrRow extends StatelessWidget {
  final AttributeSchemaModel attr;
  final bool isSystem;
  final bool isLast;
  final VoidCallback? onDelete;

  const _AttrRow({
    required this.attr,
    required this.isSystem,
    required this.isLast,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSystem
            ? AppColors.mutedText.withValues(alpha: 0.03)
            : Colors.transparent,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          if (isSystem)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.lock_outline,
                  size: 12, color: AppColors.mutedText),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attr.displayName,
                    style: AppTextStyles.tableCell.copyWith(
                      color: isSystem
                          ? AppColors.secondaryText
                          : AppColors.primaryText,
                    )),
                Text(attr.attributeKey,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          _TypeChip(type: attr.dataType),
          const SizedBox(width: 8),
          if (attr.isRequired)
            const _BadgePill(label: 'req', color: AppColors.error),
          if (attr.isPii) ...[
            const SizedBox(width: 4),
            const _BadgePill(label: 'PII', color: AppColors.warning),
          ],
          if (!isSystem && onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.error),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Delete attribute',
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
      ),
      child: Text(type,
          style: AppTextStyles.badgeLabel.copyWith(
            color: AppColors.cyan,
            fontSize: 10,
            fontFamily: 'monospace',
          )),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: AppTextStyles.badgeLabel.copyWith(color: color, fontSize: 9)),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;
  final Color? activeColor;

  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.15) : AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? color : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: value ? color : AppColors.mutedText,
            ),
            const SizedBox(width: 6),
            Text(label,
                style: AppTextStyles.buttonSmall.copyWith(
                  color: value ? color : AppColors.secondaryText,
                )),
          ],
        ),
      ),
    );
  }
}
