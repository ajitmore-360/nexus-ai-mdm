import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../data/entity_repository.dart';
import '../../../../shared/widgets/nexus_dialog.dart';

// ──────────────────────────────────────────────
// Domain enums / models
// ──────────────────────────────────────────────

enum _EntityType {
  customer,
  vendor,
  material,
  product,
  account,
  employee,
  location,
  organization,
  asset,
}

extension _EntityTypeLabel on _EntityType {
  String get label {
    switch (this) {
      case _EntityType.customer:     return 'Customer';
      case _EntityType.vendor:       return 'Vendor';
      case _EntityType.material:     return 'Material';
      case _EntityType.product:      return 'Product';
      case _EntityType.account:      return 'Account';
      case _EntityType.employee:     return 'Employee';
      case _EntityType.location:     return 'Location';
      case _EntityType.organization: return 'Organization';
      case _EntityType.asset:        return 'Asset';
    }
  }

  // MDG-style default attribute templates for each domain object.
  // Mirrors SAP MDG / Informatica MDM standard field sets so that records
  // created via the UI are immediately compatible with downstream systems.
  List<_AttributeRow> get defaultAttributes {
    switch (this) {
      case _EntityType.customer:
        return [
          // General
          _AttributeRow(key: 'customer_group',       value: '',    type: 'string'),
          _AttributeRow(key: 'name',                 value: '',    type: 'string'),
          _AttributeRow(key: 'title',                value: '',    type: 'string'),
          _AttributeRow(key: 'first_name',           value: '',    type: 'string'),
          _AttributeRow(key: 'last_name',            value: '',    type: 'string'),
          _AttributeRow(key: 'industry',             value: '',    type: 'string'),
          _AttributeRow(key: 'language',             value: 'EN',  type: 'string'),
          // Address
          _AttributeRow(key: 'street_address',       value: '',    type: 'string'),
          _AttributeRow(key: 'street_address_2',     value: '',    type: 'string'),
          _AttributeRow(key: 'city',                 value: '',    type: 'string'),
          _AttributeRow(key: 'postal_code',          value: '',    type: 'string'),
          _AttributeRow(key: 'region',               value: '',    type: 'string'),
          _AttributeRow(key: 'country',              value: '',    type: 'string'),
          // Communication
          _AttributeRow(key: 'phone',                value: '',    type: 'phone'),
          _AttributeRow(key: 'mobile',               value: '',    type: 'phone'),
          _AttributeRow(key: 'email',                value: '',    type: 'email'),
          _AttributeRow(key: 'website',              value: '',    type: 'string'),
          // Tax & Legal
          _AttributeRow(key: 'tax_number',           value: '',    type: 'string'),
          _AttributeRow(key: 'vat_registration',     value: '',    type: 'string'),
          _AttributeRow(key: 'tax_classification',   value: '',    type: 'string'),
          // Financial
          _AttributeRow(key: 'currency',             value: 'USD', type: 'string'),
          _AttributeRow(key: 'payment_terms',        value: 'Net30', type: 'string'),
          _AttributeRow(key: 'credit_limit',         value: '',    type: 'number'),
          _AttributeRow(key: 'account_manager',      value: '',    type: 'string'),
          _AttributeRow(key: 'sales_district',       value: '',    type: 'string'),
        ];

      case _EntityType.vendor:
        return [
          _AttributeRow(key: 'company_name',         value: '',    type: 'string'),
          _AttributeRow(key: 'vendor_group',         value: '',    type: 'string'),
          _AttributeRow(key: 'vendor_type',          value: '',    type: 'string'),
          _AttributeRow(key: 'street_address',       value: '',    type: 'string'),
          _AttributeRow(key: 'city',                 value: '',    type: 'string'),
          _AttributeRow(key: 'postal_code',          value: '',    type: 'string'),
          _AttributeRow(key: 'country',              value: '',    type: 'string'),
          _AttributeRow(key: 'phone',                value: '',    type: 'phone'),
          _AttributeRow(key: 'contact_email',        value: '',    type: 'email'),
          _AttributeRow(key: 'tax_number',           value: '',    type: 'string'),
          _AttributeRow(key: 'vat_registration',     value: '',    type: 'string'),
          _AttributeRow(key: 'payment_terms',        value: 'Net30', type: 'string'),
          _AttributeRow(key: 'currency',             value: 'USD', type: 'string'),
          _AttributeRow(key: 'iban',                 value: '',    type: 'string'),
          _AttributeRow(key: 'swift_code',           value: '',    type: 'string'),
          _AttributeRow(key: 'purchasing_org',       value: '',    type: 'string'),
        ];

      case _EntityType.material:
        return [
          _AttributeRow(key: 'material_type',        value: '',    type: 'string'),
          _AttributeRow(key: 'description',          value: '',    type: 'string'),
          _AttributeRow(key: 'material_group',       value: '',    type: 'string'),
          _AttributeRow(key: 'base_unit',            value: 'EA',  type: 'string'),
          _AttributeRow(key: 'weight',               value: '',    type: 'number'),
          _AttributeRow(key: 'weight_unit',          value: 'KG',  type: 'string'),
          _AttributeRow(key: 'volume',               value: '',    type: 'number'),
          _AttributeRow(key: 'volume_unit',          value: 'L',   type: 'string'),
          _AttributeRow(key: 'ean_upc',              value: '',    type: 'string'),
          _AttributeRow(key: 'manufacturer',         value: '',    type: 'string'),
          _AttributeRow(key: 'manufacturer_part_no', value: '',    type: 'string'),
          _AttributeRow(key: 'country_of_origin',    value: '',    type: 'string'),
          _AttributeRow(key: 'hazmat_class',         value: '',    type: 'string'),
          _AttributeRow(key: 'shelf_life_days',      value: '',    type: 'number'),
        ];

      case _EntityType.product:
        return [
          _AttributeRow(key: 'product_name',         value: '',    type: 'string'),
          _AttributeRow(key: 'product_category',     value: '',    type: 'string'),
          _AttributeRow(key: 'sku',                  value: '',    type: 'string'),
          _AttributeRow(key: 'gtin',                 value: '',    type: 'string'),
          _AttributeRow(key: 'brand',                value: '',    type: 'string'),
          _AttributeRow(key: 'list_price',           value: '',    type: 'number'),
          _AttributeRow(key: 'currency',             value: 'USD', type: 'string'),
          _AttributeRow(key: 'description',          value: '',    type: 'string'),
          _AttributeRow(key: 'is_active',            value: 'true', type: 'boolean'),
        ];

      case _EntityType.employee:
        return [
          _AttributeRow(key: 'first_name',           value: '',    type: 'string'),
          _AttributeRow(key: 'last_name',            value: '',    type: 'string'),
          _AttributeRow(key: 'title',                value: '',    type: 'string'),
          _AttributeRow(key: 'work_email',           value: '',    type: 'email'),
          _AttributeRow(key: 'work_phone',           value: '',    type: 'phone'),
          _AttributeRow(key: 'department',           value: '',    type: 'string'),
          _AttributeRow(key: 'cost_center',          value: '',    type: 'string'),
          _AttributeRow(key: 'company_code',         value: '',    type: 'string'),
          _AttributeRow(key: 'hire_date',            value: '',    type: 'date'),
          _AttributeRow(key: 'contract_type',        value: '',    type: 'string'),
          _AttributeRow(key: 'manager_id',           value: '',    type: 'string'),
        ];

      case _EntityType.location:
        return [
          _AttributeRow(key: 'location_name',        value: '',    type: 'string'),
          _AttributeRow(key: 'location_type',        value: '',    type: 'string'),
          _AttributeRow(key: 'street_address',       value: '',    type: 'string'),
          _AttributeRow(key: 'city',                 value: '',    type: 'string'),
          _AttributeRow(key: 'postal_code',          value: '',    type: 'string'),
          _AttributeRow(key: 'country',              value: '',    type: 'string'),
          _AttributeRow(key: 'latitude',             value: '',    type: 'number'),
          _AttributeRow(key: 'longitude',            value: '',    type: 'number'),
          _AttributeRow(key: 'timezone',             value: '',    type: 'string'),
        ];

      case _EntityType.organization:
        return [
          _AttributeRow(key: 'org_name',             value: '',    type: 'string'),
          _AttributeRow(key: 'legal_name',           value: '',    type: 'string'),
          _AttributeRow(key: 'org_type',             value: '',    type: 'string'),
          _AttributeRow(key: 'registration_number',  value: '',    type: 'string'),
          _AttributeRow(key: 'country_of_incorporation', value: '', type: 'string'),
          _AttributeRow(key: 'parent_org_id',        value: '',    type: 'string'),
          _AttributeRow(key: 'website',              value: '',    type: 'string'),
          _AttributeRow(key: 'industry',             value: '',    type: 'string'),
        ];

      case _EntityType.account:
        return [
          _AttributeRow(key: 'account_name',         value: '',    type: 'string'),
          _AttributeRow(key: 'account_type',         value: '',    type: 'string'),
          _AttributeRow(key: 'account_number',       value: '',    type: 'string'),
          _AttributeRow(key: 'currency',             value: 'USD', type: 'string'),
          _AttributeRow(key: 'owner_id',             value: '',    type: 'string'),
          _AttributeRow(key: 'is_active',            value: 'true', type: 'boolean'),
        ];

      case _EntityType.asset:
        return [
          _AttributeRow(key: 'asset_name',           value: '',    type: 'string'),
          _AttributeRow(key: 'asset_class',          value: '',    type: 'string'),
          _AttributeRow(key: 'serial_number',        value: '',    type: 'string'),
          _AttributeRow(key: 'acquisition_date',     value: '',    type: 'date'),
          _AttributeRow(key: 'acquisition_value',    value: '',    type: 'number'),
          _AttributeRow(key: 'currency',             value: 'USD', type: 'string'),
          _AttributeRow(key: 'depreciation_key',     value: '',    type: 'string'),
          _AttributeRow(key: 'useful_life_years',    value: '',    type: 'number'),
          _AttributeRow(key: 'location_id',          value: '',    type: 'string'),
          _AttributeRow(key: 'custodian_id',         value: '',    type: 'string'),
        ];
    }
  }
}

enum _SourceSystem { manual, salesforce, sap, oracle }

extension _SourceSystemLabel on _SourceSystem {
  String get label {
    switch (this) {
      case _SourceSystem.manual:
        return 'Manual Entry';
      case _SourceSystem.salesforce:
        return 'Salesforce';
      case _SourceSystem.sap:
        return 'SAP';
      case _SourceSystem.oracle:
        return 'Oracle';
    }
  }
}

enum _Origin { mdmAuthoritative, sourceSystem }

// ──────────────────────────────────────────────
// Attribute row model
// ──────────────────────────────────────────────

class _AttributeRow {
  String key;
  String value;
  String type;
  final TextEditingController keyController;
  final TextEditingController valueController;

  _AttributeRow({required this.key, required this.value, required this.type})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

// ──────────────────────────────────────────────
// Duplicate check model
// ──────────────────────────────────────────────

class _DuplicateHit {
  final String entityId;
  final String entityName;
  final double score;
  final String sourceSystem;

  const _DuplicateHit({
    required this.entityId,
    required this.entityName,
    required this.score,
    required this.sourceSystem,
  });
}

// ──────────────────────────────────────────────
// Page
// ──────────────────────────────────────────────

class EntityCreatePage extends StatefulWidget {
  const EntityCreatePage({super.key});

  @override
  State<EntityCreatePage> createState() => _EntityCreatePageState();
}

class _EntityCreatePageState extends State<EntityCreatePage> {
  final _formKey = GlobalKey<FormState>();

  late final EntityRepository _repository;

  _EntityType _selectedType = _EntityType.customer;
  _SourceSystem _selectedSource = _SourceSystem.manual;
  _Origin _selectedOrigin = _Origin.mdmAuthoritative;
  bool _distribute = true;
  bool _isPublishing = false;
  bool _isSavingDraft = false;

  // AI duplicate check state
  bool _isDupChecking = false;
  bool _dupCheckDone = false;
  List<_DuplicateHit> _dupHits = [];

  late List<_AttributeRow> _attributes;

  // Debounce timer reference
  int _dupCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = EntityRepository(ApiClient());
    _attributes = List.from(_selectedType.defaultAttributes);
  }

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  @override
  void dispose() {
    for (final a in _attributes) {
      a.dispose();
    }
    super.dispose();
  }

  void _onTypeChanged(_EntityType? type) {
    if (type == null) return;
    for (final a in _attributes) {
      a.dispose();
    }
    setState(() {
      _selectedType = type;
      _attributes = List.from(type.defaultAttributes);
      _dupCheckDone = false;
      _dupHits = [];
    });
  }

  void _addAttribute(String key, String type) {
    setState(() {
      _attributes.add(_AttributeRow(key: key, value: '', type: type));
    });
  }

  void _removeAttribute(int index) {
    _attributes[index].dispose();
    setState(() => _attributes.removeAt(index));
  }

  Future<void> _triggerDupCheck() async {
    final generation = ++_dupCheckGeneration;
    setState(() {
      _isDupChecking = true;
      _dupCheckDone = false;
      _dupHits = [];
    });
    await Future.delayed(const Duration(seconds: 2));
    if (generation != _dupCheckGeneration || !mounted) return;
    // Simulate response — show duplicate only if "name" field is non-empty
    final nameAttr = _attributes.firstWhere(
      (a) => a.key.toLowerCase().contains('name'),
      orElse: () => _AttributeRow(key: '', value: '', type: 'string'),
    );
    final hasDup = nameAttr.valueController.text.trim().isNotEmpty;
    setState(() {
      _isDupChecking = false;
      _dupCheckDone = true;
      _dupHits = hasDup
          ? const [
              _DuplicateHit(
                entityId: 'ENT-003',
                entityName: 'Michael A. Rodriguez',
                score: 0.87,
                sourceSystem: 'Salesforce CRM',
              ),
              _DuplicateHit(
                entityId: 'ENT-007',
                entityName: 'M. Rodriguez Jr.',
                score: 0.72,
                sourceSystem: 'SAP ERP',
              ),
            ]
          : [];
    });
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isPublishing = true);

    final tenantId = await AuthManager.getTenantId()
        ?? '00000000-0000-0000-0000-000000000001';

    final attributes = _attributes
        .where((a) => a.keyController.text.trim().isNotEmpty)
        .map((a) => {
              'key': a.keyController.text.trim(),
              'value': a.valueController.text.trim(),
              'data_type': a.type,
              'source_system': _selectedSource.label,
            })
        .toList();

    final recordOrigin = _selectedOrigin == _Origin.mdmAuthoritative
        ? 'mdm_authoritative'
        : 'ingested';

    final payload = {
      'entity': {
        'entity_id': _generateUuid(),
        'tenant_id': tenantId,
        'entity_type': _selectedType.label,
        'status': 'Active',
        'attributes': attributes,
      },
      'record_origin': recordOrigin,
      'distribute': _distribute,
      'distribution_targets': <Map<String, dynamic>>[],
    };

    final result = await _repository.createEntity(payload);
    if (!mounted) return;
    setState(() => _isPublishing = false);

    switch (result) {
      case Success<CreateEntityResponse>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Text('Entity published successfully.',
                    style: AppTextStyles.bodyMedium),
              ],
            ),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      case Failure<CreateEntityResponse>(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Failed to create entity: ${exception.message}',
                      style: AppTextStyles.bodyMedium),
                ),
              ],
            ),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _isSavingDraft = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isSavingDraft = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Draft saved.', style: AppTextStyles.bodyMedium),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                const SizedBox(height: 24),
                _buildDupCheckSection(),
                const SizedBox(height: 24),
                _buildDistributionToggle(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── App Bar ──────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.secondaryText),
        onPressed: () => context.pop(),
      ),
      title: Text('Create New Entity', style: AppTextStyles.titleMedium),
      actions: [
        TextButton(
          onPressed: (_isSavingDraft || _isPublishing) ? null : _saveDraft,
          child: _isSavingDraft
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryText),
                )
              : Text('Save Draft', style: AppTextStyles.buttonMedium.copyWith(color: AppColors.secondaryText)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_isPublishing || _isSavingDraft) ? null : _publish,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            textStyle: AppTextStyles.buttonMedium,
          ),
          child: _isPublishing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Publish'),
        ),
        const SizedBox(width: 16),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  // ── Entity Identity ──────────────────────────
  Widget _buildIdentitySection() {
    return _SectionCard(
      title: 'Entity Identity',
      icon: Icons.fingerprint_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Entity Type', style: AppTextStyles.labelMedium),
                    const SizedBox(height: 8),
                    _StyledDropdown<_EntityType>(
                      value: _selectedType,
                      items: _EntityType.values,
                      labelOf: (t) => t.label,
                      onChanged: _onTypeChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Source System', style: AppTextStyles.labelMedium),
                    const SizedBox(height: 8),
                    _StyledDropdown<_SourceSystem>(
                      value: _selectedSource,
                      items: _SourceSystem.values,
                      labelOf: (s) => s.label,
                      onChanged: (v) => v != null ? setState(() => _selectedSource = v) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Origin', style: AppTextStyles.labelMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              _OriginRadio(
                label: 'MDM Authoritative',
                description: 'MDM is the system of record',
                selected: _selectedOrigin == _Origin.mdmAuthoritative,
                onTap: () => setState(() => _selectedOrigin = _Origin.mdmAuthoritative),
              ),
              const SizedBox(width: 12),
              _OriginRadio(
                label: 'Source System',
                description: 'Source system is the authority',
                selected: _selectedOrigin == _Origin.sourceSystem,
                onTap: () => setState(() => _selectedOrigin = _Origin.sourceSystem),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0);
  }

  // ── Attributes Section ───────────────────────
  Widget _buildAttributesSection() {
    return _SectionCard(
      title: 'Attributes',
      icon: Icons.table_rows_rounded,
      action: TextButton.icon(
        onPressed: _showAddAttributeDialog,
        icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
        label: Text('Add Field', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.primary)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('FIELD KEY', style: AppTextStyles.tableHeader)),
                Expanded(flex: 3, child: Text('VALUE', style: AppTextStyles.tableHeader)),
                SizedBox(width: 80, child: Text('TYPE', style: AppTextStyles.tableHeader)),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          ..._attributes.asMap().entries.map((e) {
            final i = e.key;
            final attr = e.value;
            return _buildAttributeInputRow(attr, i);
          }),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildAttributeInputRow(_AttributeRow attr, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: attr.keyController,
              onChanged: (v) => attr.key = v,
              decoration: _inputDecoration(hintText: 'field_key'),
              style: AppTextStyles.inputText.copyWith(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: attr.valueController,
              onChanged: (v) {
                attr.value = v;
                if (v.length >= 2) {
                  _triggerDupCheck();
                }
              },
              validator: attr.key == 'email' || attr.key == 'work_email' || attr.key == 'contact_email'
                  ? (v) {
                      if (v != null && v.isNotEmpty && !v.contains('@')) {
                        return 'Invalid email';
                      }
                      return null;
                    }
                  : null,
              decoration: _inputDecoration(hintText: 'Enter value...'),
              style: AppTextStyles.inputText,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  void _showAddAttributeDialog() {
    final keyCtrl = TextEditingController();
    String selectedType = 'string';
    final types = ['string', 'email', 'phone', 'number', 'boolean', 'date'];

    showNexusDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDs) => NexusDialog(
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

  // ── AI Dup Check ─────────────────────────────
  Widget _buildDupCheckSection() {
    return _SectionCard(
      title: 'AI Duplicate Check',
      icon: Icons.manage_search_rounded,
      iconColor: AppColors.aiPurple,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _isDupChecking
            ? _buildDupCheckLoading()
            : !_dupCheckDone
                ? _buildDupCheckIdle()
                : _dupHits.isEmpty
                    ? _buildDupCheckClear()
                    : _buildDupCheckWarning(),
      ),
    ).animate(delay: 200.ms).fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildDupCheckIdle() {
    return Padding(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.mutedText),
          const SizedBox(width: 8),
          Text(
            'Start entering attribute values to trigger real-time duplicate detection.',
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDupCheckLoading() {
    return Column(
      key: const ValueKey('loading'),
      children: List.generate(
        2,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LoadingShimmer(
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.elevatedCard,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDupCheckClear() {
    return Container(
      key: const ValueKey('clear'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Text(
            'No duplicates found — this appears to be a new entity.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildDupCheckWarning() {
    return Column(
      key: const ValueKey('warning'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                '${_dupHits.length} potential duplicate${_dupHits.length > 1 ? 's' : ''} found — review before publishing.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ..._dupHits.map((hit) => _buildDupHitCard(hit)),
      ],
    );
  }

  Widget _buildDupHitCard(_DuplicateHit hit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(hit.entityId, style: AppTextStyles.badgeLabel.copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hit.entityName, style: AppTextStyles.labelMedium),
                Text(hit.sourceSystem, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(hit.score * 100).round()}% match',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: hit.score >= 0.8 ? AppColors.error : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(height: 3, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                    FractionallySizedBox(
                      widthFactor: hit.score,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: hit.score >= 0.8 ? AppColors.error : AppColors.warning,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: AppTextStyles.buttonSmall,
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  // ── Distribution ─────────────────────────────
  Widget _buildDistributionToggle() {
    return _SectionCard(
      title: 'Distribution',
      icon: Icons.broadcast_on_personal_outlined,
      child: SwitchListTile(
        value: _distribute,
        onChanged: (v) => setState(() => _distribute = v),
        title: Text('Distribute to downstream systems', style: AppTextStyles.titleSmall),
        subtitle: Text(
          'When enabled, this entity will be propagated to connected source systems automatically.',
          style: AppTextStyles.bodySmall,
        ),
        activeThumbColor: AppColors.primary,
        contentPadding: EdgeInsets.zero,
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 350.ms);
  }
}

// ──────────────────────────────────────────────
// Reusable widgets
// ──────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? action;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.iconColor = AppColors.primary,
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
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 16, color: iconColor),
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
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.secondaryText, size: 18),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelOf(item), style: AppTextStyles.inputText),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _OriginRadio extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _OriginRadio({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.elevatedCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.secondaryText,
                    width: 2,
                  ),
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: selected ? AppColors.primary : AppColors.primaryText,
                      ),
                    ),
                    Text(description, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
