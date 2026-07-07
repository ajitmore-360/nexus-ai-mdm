import 'package:flutter/material.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../data/submaster_repository.dart';

class SubmastersPage extends StatefulWidget {
  const SubmastersPage({super.key});

  @override
  State<SubmastersPage> createState() => _SubmastersPageState();
}

class _SubmastersPageState extends State<SubmastersPage> {
  late final SubmasterRepository _repo;

  bool _loading = true;
  String? _error;
  String _tenantId = '';

  List<SubmasterTypeModel> _types = [];
  SubmasterTypeModel? _selectedType;
  List<SubmasterValueModel> _values = [];
  bool _loadingValues = false;

  @override
  void initState() {
    super.initState();
    _repo = SubmasterRepository(ApiClient());
    _init();
  }

  Future<void> _init() async {
    _tenantId = await AuthManager.getTenantId() ?? '';
    await _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() { _loading = true; _error = null; });
    final result = await _repo.listTypes(_tenantId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Success<List<SubmasterTypeModel>>) {
        _types = result.data;
      } else {
        _error = 'Failed to load reference data types';
      }
    });
    if (_selectedType != null) {
      final refreshed = _types.where((t) => t.code == _selectedType!.code).firstOrNull;
      if (refreshed != null) await _selectType(refreshed);
    }
  }

  Future<void> _selectType(SubmasterTypeModel type) async {
    setState(() { _selectedType = type; _loadingValues = true; _values = []; });
    final result = await _repo.listValues(_tenantId, type.code);
    if (!mounted) return;
    setState(() {
      _loadingValues = false;
      if (result is Success<List<SubmasterValueModel>>) {
        _values = result.data;
      }
    });
  }

  // ── Create type dialog ──────────────────────────────────────────────────────

  void _showCreateTypeDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey  = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('New Reference Data Type', style: AppTextStyles.titleMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(codeCtrl, 'Code', hint: 'e.g. risk_category',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              _field(nameCtrl, 'Display Name', hint: 'e.g. Risk Category',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              _field(descCtrl, 'Description (optional)', hint: 'Short description'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              final result = await _repo.createType(
                tenantId: _tenantId,
                code: codeCtrl.text.trim().toLowerCase(),
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              );
              if (!mounted) return;
              if (result is Success<SubmasterTypeModel>) {
                await _loadTypes();
                final created = _types.where((t) => t.code == result.data.code).firstOrNull;
                if (created != null) await _selectType(created);
                _showSnack('Reference data type created');
              } else {
                _showSnack('Failed to create type', isError: true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // ── Add value dialog ────────────────────────────────────────────────────────

  void _showAddValueDialog() {
    if (_selectedType == null) return;
    final codeCtrl  = TextEditingController();
    final labelCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    final formKey   = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Value to "${_selectedType!.name}"',
            style: AppTextStyles.titleMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(codeCtrl, 'Code', hint: 'e.g. HIGH',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              _field(labelCtrl, 'Label', hint: 'e.g. High Risk',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              _field(descCtrl, 'Description (optional)', hint: 'Short description'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              final result = await _repo.createValue(
                tenantId:   _tenantId,
                typeCode:   _selectedType!.code,
                code:       codeCtrl.text.trim().toUpperCase(),
                label:      labelCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                sortOrder:  _values.length,
              );
              if (!mounted) return;
              if (result is Success<SubmasterValueModel>) {
                await _selectType(_selectedType!);
                _showSnack('Value added');
              } else {
                _showSnack('Failed to add value', isError: true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ── Deactivate value ────────────────────────────────────────────────────────

  Future<void> _deactivateValue(SubmasterValueModel v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Deactivate Value'),
        content: Text('Remove "${v.label}" from the dropdown? This will not delete existing records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _repo.deleteValue(
        tenantId: _tenantId, typeCode: _selectedType!.code, valueId: v.id);
    if (!mounted) return;
    if (result is Success<bool>) {
      await _selectType(_selectedType!);
      _showSnack('Value deactivated');
    } else {
      _showSnack('Failed to deactivate value', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTypesPanel(),
                    const VerticalDivider(width: 1, color: AppColors.divider),
                    Expanded(child: _buildValuesPanel()),
                  ],
                ),
    );
  }

  // ── Types panel (left) ──────────────────────────────────────────────────────

  Widget _buildTypesPanel() {
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reference Data Types',
                      style: AppTextStyles.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  tooltip: 'New type',
                  color: AppColors.primary,
                  onPressed: _showCreateTypeDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _types.length,
              itemBuilder: (ctx, i) {
                final t = _types[i];
                final selected = _selectedType?.code == t.code;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                  leading: Icon(Icons.list_alt_outlined,
                      size: 18,
                      color: selected ? AppColors.primary : AppColors.mutedText),
                  title: Text(t.name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? AppColors.primary : null,
                      )),
                  subtitle: Text(t.code,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.mutedText, fontFamily: 'monospace')),
                  trailing: t.isSystem
                      ? Tooltip(
                          message: 'System type — cannot be deleted',
                          child: Icon(Icons.lock_outline, size: 14,
                              color: AppColors.mutedText))
                      : null,
                  onTap: () => _selectType(t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Values panel (right) ────────────────────────────────────────────────────

  Widget _buildValuesPanel() {
    if (_selectedType == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 48, color: AppColors.mutedText),
            const SizedBox(height: 12),
            Text('Select a reference data type to manage its values',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.mutedText)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedType!.name, style: AppTextStyles.titleMedium),
                    if (_selectedType!.description != null)
                      Text(_selectedType!.description!,
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.mutedText)),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Value'),
                onPressed: _showAddValueDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        if (_loadingValues)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_values.isEmpty)
          Expanded(
            child: Center(
              child: Text('No values yet — add the first one.',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.mutedText)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _values.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (ctx, i) {
                final v = _values[i];
                return ListTile(
                  dense: true,
                  leading: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(v.code,
                        style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary, fontFamily: 'monospace')),
                  ),
                  title: Text(v.label, style: AppTextStyles.bodyMedium),
                  subtitle: v.description != null
                      ? Text(v.description!,
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.mutedText))
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.block_outlined, size: 16),
                    tooltip: 'Deactivate',
                    color: AppColors.mutedText,
                    hoverColor: AppColors.error.withValues(alpha: 0.1),
                    onPressed: () => _deactivateValue(v),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
