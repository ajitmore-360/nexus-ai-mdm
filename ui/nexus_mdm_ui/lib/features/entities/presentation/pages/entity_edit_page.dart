import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/models/entity.dart';
import '../../data/entity_repository.dart';
import '../../../../shared/widgets/azile_dialog.dart';
import '../../../../features/admin/data/entity_type_repository.dart';
import '../../../../features/admin/data/submaster_repository.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Local enums â€“ mirrors entity_create_page
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

enum _EditEntityType {
  customer,
  vendor,
  material,
  product,
  account,
  employee,
  location,
}

extension _EditEntityTypeExt on _EditEntityType {
  String get backendLabel {
    switch (this) {
      case _EditEntityType.customer:  return 'Customer';
      case _EditEntityType.vendor:    return 'Vendor';
      case _EditEntityType.material:  return 'Material';
      case _EditEntityType.product:   return 'Product';
      case _EditEntityType.account:   return 'Account';
      case _EditEntityType.employee:  return 'Employee';
      case _EditEntityType.location:  return 'Location';
    }
  }

  String get displayLabel {
    switch (this) {
      case _EditEntityType.customer:  return 'Customer';
      case _EditEntityType.vendor:    return 'Vendor';
      case _EditEntityType.material:  return 'Material';
      case _EditEntityType.product:   return 'Product';
      case _EditEntityType.account:   return 'Account';
      case _EditEntityType.employee:  return 'Employee';
      case _EditEntityType.location:  return 'Location';
    }
  }

  static _EditEntityType fromFlutterType(EntityType type) {
    switch (type) {
      case EntityType.person:       return _EditEntityType.customer;
      case EntityType.organization: return _EditEntityType.vendor;
      case EntityType.product:      return _EditEntityType.product;
      case EntityType.location:     return _EditEntityType.location;
      case EntityType.asset:        return _EditEntityType.account;
    }
  }
}

enum _EditStatus { active, pendingReview, draft, inactive }

extension _EditStatusExt on _EditStatus {
  String get displayLabel {
    switch (this) {
      case _EditStatus.active:        return 'Active';
      case _EditStatus.pendingReview: return 'Pending Review';
      case _EditStatus.draft:         return 'Draft';
      case _EditStatus.inactive:      return 'Inactive';
    }
  }

  String get backendLabel {
    switch (this) {
      case _EditStatus.active:        return 'Active';
      case _EditStatus.pendingReview: return 'PendingReview';
      case _EditStatus.draft:         return 'Draft';
      case _EditStatus.inactive:      return 'Inactive';
    }
  }

  static _EditStatus fromFlutterStatus(EntityStatus status) {
    switch (status) {
      case EntityStatus.active:
      case EntityStatus.golden:
        return _EditStatus.active;
      case EntityStatus.review:
        return _EditStatus.pendingReview;
      case EntityStatus.pending:
        return _EditStatus.draft;
      case EntityStatus.inactive:
      case EntityStatus.merged:
        return _EditStatus.inactive;
    }
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Submaster dropdown option
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SubmasterOption {
  final String code;
  final String label;
  const _SubmasterOption({required this.code, required this.label});
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Attribute row
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AttrRow {
  String key;
  String type;
  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;
  // When non-null this attribute is backed by a submaster â€” render as dropdown.
  List<_SubmasterOption>? dropdownOptions;

  _AttrRow({
    required this.key,
    required String value,
    required this.type,
  })  : keyCtrl   = TextEditingController(text: key),
        valueCtrl = TextEditingController(text: value);

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Page widget
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class EntityEditPage extends StatefulWidget {
  final String entityId;
  final CanonicalEntity? entity;

  const EntityEditPage({
    super.key,
    required this.entityId,
    this.entity,
  });

  @override
  State<EntityEditPage> createState() => _EntityEditPageState();
}

class _EntityEditPageState extends State<EntityEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final EntityRepository    _repository;
  late final EntityTypeRepository _entityTypeRepo;
  late final SubmasterRepository  _submasterRepo;

  _EditEntityType _selectedType   = _EditEntityType.customer;
  _EditStatus     _selectedStatus = _EditStatus.active;
  List<_AttrRow>  _attributes     = [];

  bool _isSaving        = false;
  bool _loadingSchemas  = false;

  @override
  void initState() {
    super.initState();
    final api       = ApiClient();
    _repository     = EntityRepository(api);
    _entityTypeRepo = EntityTypeRepository(api);
    _submasterRepo  = SubmasterRepository(api);
    _prefillFromEntity(widget.entity);
    _loadAttributeSchemas();
  }

  void _prefillFromEntity(CanonicalEntity? entity) {
    if (entity == null) return;
    _selectedType   = _EditEntityTypeExt.fromFlutterType(entity.type);
    _selectedStatus = _EditStatusExt.fromFlutterStatus(entity.status);
    _attributes     = entity.attributes.entries.map((e) {
      final attr  = e.value;
      final value = attr.value?.toString() ?? '';
      return _AttrRow(key: e.key, value: value, type: 'string');
    }).toList();
  }

  /// Fetches attribute schemas for the current entity type and overlays
  /// submaster dropdown options onto matching _AttrRow entries.
  Future<void> _loadAttributeSchemas() async {
    if (!mounted) return;
    setState(() => _loadingSchemas = true);
    try {
      final tenantId = await AuthManager.getTenantId() ?? '';
      final typeCode = _selectedType.name;

      final schemasResult =
          await _entityTypeRepo.listAttributes(tenantId, typeCode);
      if (!mounted) return;
      if (schemasResult is! Success<List<AttributeSchemaModel>>) {
        setState(() => _loadingSchemas = false);
        return;
      }

      final schemas = schemasResult.data;
      final submasterCodes = schemas
          .where((s) => s.submasterCode != null)
          .map((s) => s.submasterCode!)
          .toSet();

      final Map<String, List<_SubmasterOption>> optionsByCode = {};
      await Future.wait(submasterCodes.map((smCode) async {
        final result = await _submasterRepo.listValues(tenantId, smCode);
        if (result is Success<List<SubmasterValueModel>>) {
          optionsByCode[smCode] = result.data
              .map((v) => _SubmasterOption(code: v.code, label: v.label))
              .toList();
        }
      }));

      if (!mounted) return;

      // Build attribute_key â†’ options lookup
      final Map<String, List<_SubmasterOption>> attrOptions = {};
      for (final schema in schemas) {
        if (schema.submasterCode != null &&
            optionsByCode.containsKey(schema.submasterCode)) {
          attrOptions[schema.attributeKey] =
              optionsByCode[schema.submasterCode!]!;
        }
      }

      setState(() {
        for (final attr in _attributes) {
          if (attrOptions.containsKey(attr.key)) {
            attr.dropdownOptions = attrOptions[attr.key];
            // If the current value is not a valid code, keep it as-is so
            // existing free-text data is not silently discarded.
          }
        }
        _loadingSchemas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSchemas = false);
    }
  }

  @override
  void dispose() {
    for (final a in _attributes) {
      a.dispose();
    }
    super.dispose();
  }

  void _addAttribute(String key, String type) {
    setState(() => _attributes.add(_AttrRow(key: key, value: '', type: type)));
  }

  void _removeAttribute(int index) {
    _attributes[index].dispose();
    setState(() => _attributes.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final attributes = _attributes
        .where((a) => a.keyCtrl.text.trim().isNotEmpty)
        .map((a) => {
              'key':         a.keyCtrl.text.trim(),
              'value':       a.valueCtrl.text.trim(),
              'data_type':   a.type,
            })
        .toList();

    final payload = <String, dynamic>{
      'entity_type': _selectedType.backendLabel,
      'status':      _selectedStatus.backendLabel,
      if (attributes.isNotEmpty) 'attributes': attributes,
    };

    final result = await _repository.updateEntity(widget.entityId, payload);
    if (!mounted) return;
    setState(() => _isSaving = false);

    switch (result) {
      case Success<String>():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Text('Entity updated successfully.'),
              ],
            ),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Pop back to detail page; detail page will reload.
        context.pop();
      case Failure<String>(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Update failed: ${exception.message}'),
                ),
              ],
            ),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIdentitySection(),
                const SizedBox(height: 24),
                _buildAttributesSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.secondaryText),
        onPressed: () => context.pop(),
      ),
      title: Text(
        widget.entity != null
            ? 'Edit â€” ${widget.entity!.displayName}'
            : 'Edit Entity',
        style: AppTextStyles.titleMedium,
      ),
      actions: [
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            textStyle: AppTextStyles.buttonMedium,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Changes'),
        ),
        const SizedBox(width: 16),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  Widget _buildIdentitySection() {
    return _SectionCard(
      title: 'Entity Identity',
      icon: Icons.fingerprint_rounded,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Entity Type', style: AppTextStyles.labelMedium),
                const SizedBox(height: 8),
                _StyledDropdown<_EditEntityType>(
                  value: _selectedType,
                  items: _EditEntityType.values,
                  labelOf: (t) => t.displayLabel,
                  onChanged: (v) =>
                      v != null ? setState(() => _selectedType = v) : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status', style: AppTextStyles.labelMedium),
                const SizedBox(height: 8),
                _StyledDropdown<_EditStatus>(
                  value: _selectedStatus,
                  items: _EditStatus.values,
                  labelOf: (s) => s.displayLabel,
                  onChanged: (v) =>
                      v != null ? setState(() => _selectedStatus = v) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildAttributesSection() {
    return _SectionCard(
      title: 'Attributes',
      icon: Icons.table_rows_rounded,
      action: TextButton.icon(
        onPressed: _showAddAttributeDialog,
        icon: const Icon(Icons.add_rounded,
            size: 16, color: AppColors.primary),
        label: Text(
          'Add Field',
          style: AppTextStyles.buttonSmall
              .copyWith(color: AppColors.primary),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('FIELD KEY',
                        style: AppTextStyles.tableHeader)),
                Expanded(
                    flex: 3,
                    child:
                        Text('VALUE', style: AppTextStyles.tableHeader)),
                SizedBox(
                    width: 80,
                    child: Text('TYPE',
                        style: AppTextStyles.tableHeader)),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          if (_attributes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No attributes. Tap "Add Field" to add one.',
                style: AppTextStyles.bodySmall,
              ),
            )
          else
            ..._attributes.asMap().entries.map((e) =>
                _buildAttrRow(e.value, e.key)),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildAttrRow(_AttrRow attr, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: attr.keyCtrl,
              onChanged: (v) => attr.key = v,
              decoration: _inputDecoration(hintText: 'field_key'),
              style: AppTextStyles.inputText
                  .copyWith(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: attr.dropdownOptions != null
                ? DropdownButtonFormField<String>(
                    initialValue: attr.dropdownOptions!
                            .any((o) => o.code == attr.valueCtrl.text)
                        ? attr.valueCtrl.text
                        : null,
                    decoration: _inputDecoration(hintText: 'Selectâ€¦'),
                    style: AppTextStyles.inputText,
                    isExpanded: true,
                    items: attr.dropdownOptions!
                        .map((opt) => DropdownMenuItem<String>(
                              value: opt.code,
                              child: Text(opt.label,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => attr.valueCtrl.text = v);
                    },
                  )
                : TextFormField(
                    controller: attr.valueCtrl,
                    decoration: _inputDecoration(hintText: 'Enter valueâ€¦'),
                    style: AppTextStyles.inputText,
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                attr.type,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.aiPurple,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              onPressed: () => _removeAttribute(index),
              color: AppColors.mutedText,
              hoverColor: AppColors.error.withValues(alpha: 0.1),
              tooltip: 'Remove field',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.inputHint,
      filled: true,
      fillColor: AppColors.inputFill,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide:
            const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide:
            const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  void _showAddAttributeDialog() {
    final keyCtrl = TextEditingController();
    String selectedType = 'string';
    const types = ['string', 'email', 'phone', 'number', 'boolean', 'date'];

    showAzileDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDs) => AzileDialog(
          title: 'Add Attribute',
          titleIcon: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.add_rounded,
                size: 15, color: AppColors.primary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Field Key', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: keyCtrl,
                decoration: _inputDecoration(hintText: 'e.g. tax_id'),
                style: AppTextStyles.inputText,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text('Field Type', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: types.map((t) {
                  final isSelected = t == selectedType;
                  return GestureDetector(
                    onTap: () => setDs(() => selectedType = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.elevatedCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        t,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.secondaryText,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (keyCtrl.text.trim().isNotEmpty) {
                  _addAttribute(keyCtrl.text.trim(), selectedType);
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Field'),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Shared widgets (duplicated from create page
// to keep files self-contained)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.titleSmall),
              const Spacer(),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.elevatedCard,
          style: AppTextStyles.inputText,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.secondaryText, size: 18),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelOf(item),
                        style: AppTextStyles.inputText),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
