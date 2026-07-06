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
import '../../../../core/validation/validators.dart';
import '../../../../shared/widgets/nexus_dialog.dart';
import '../../../../features/admin/data/governance_repository.dart';
import '../../../../features/admin/data/source_systems_repository.dart';
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

enum _Origin { mdmAuthoritative, sourceSystem }

// ──────────────────────────────────────────────
// Attribute row model
// ──────────────────────────────────────────────

class _AttributeRow {
  String key;
  String value;
  String type;
  // Predefined attributes from defaultAttributes have isCustom=false;
  // rows added by the user via "Add Field" have isCustom=true.
  final bool isCustom;
  final TextEditingController keyController;
  final TextEditingController valueController;

  _AttributeRow({
    required this.key,
    required this.value,
    required this.type,
    this.isCustom = false,
  })  : keyController = TextEditingController(text: key),
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
  late final GovernanceRepository _governanceRepo;

  static final SourceSystemModel _manualEntry = SourceSystemModel(
    id: '', tenantId: '', name: 'Manual Entry', code: 'nexus-mdm',
    connectorType: 'manual', description: 'Manually entered data',
    icon: '', trustWeight: 1.0, priority: 0, entityTypes: const [],
    syncMode: 'manual', isActive: true, isConnected: true,
    lastSyncStatus: 'active',
  );

  _EntityType _selectedType = _EntityType.customer;
  List<SourceSystemModel> _sourceSystems = [];
  SourceSystemModel _selectedSourceModel = _manualEntry;
  bool _loadingSources = false;
  _Origin _selectedOrigin = _Origin.mdmAuthoritative;

  List<SourceSystemModel> get _sourceOptions => [_manualEntry, ..._sourceSystems];
  bool _distribute = true;
  bool _isPublishing = false;
  bool _isSavingDraft = false;
  bool _isSteward = false;

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
    final api = ApiClient();
    _repository = EntityRepository(api);
    _governanceRepo = GovernanceRepository(api);
    _attributes = List.from(_selectedType.defaultAttributes);
    _loadRole();
    _loadSourceSystems();
  }

  Future<void> _loadRole() async {
    final role = await AuthManager.getUserRole() ?? '';
    if (mounted) setState(() => _isSteward = role == 'steward');
  }

  Future<void> _loadSourceSystems() async {
    setState(() => _loadingSources = true);
    final tenantId = await AuthManager.getTenantId() ?? '';
    final result = await SourceSystemsRepository(ApiClient()).listSourceSystems(tenantId);
    if (!mounted) return;
    setState(() {
      _loadingSources = false;
      if (result is Success<List<SourceSystemModel>>) {
        _sourceSystems = result.data.where((s) => s.isActive).toList();
      }
    });
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
      _attributes.add(_AttributeRow(key: key, value: '', type: type, isCustom: true));
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

    // Build a query from the first name-like or any non-empty field
    final nameAttr = _attributes
        .where((a) => a.key.toLowerCase().contains('name'))
        .firstOrNull;
    final query = nameAttr?.valueController.text.trim() ??
        _attributes.map((a) => a.valueController.text.trim()).firstWhere(
              (v) => v.isNotEmpty,
              orElse: () => '',
            );

    if (query.isEmpty) {
      if (mounted) {
        setState(() { _isDupChecking = false; _dupCheckDone = true; });
      }
      return;
    }

    try {
      final api = ApiClient();
      final resp = await api.get<Map<String, dynamic>>(
        '/v1/search',
        queryParameters: {'q': query, 'page_size': '5'},
      );
      if (generation != _dupCheckGeneration || !mounted) return;
      final items = resp.data?['items'] as List<dynamic>? ?? [];
      setState(() {
        _isDupChecking = false;
        _dupCheckDone = true;
        _dupHits = items.map((e) {
          final m = e as Map<String, dynamic>;
          return _DuplicateHit(
            entityId: m['id'] as String? ?? m['entity_id'] as String? ?? '—',
            entityName: m['display_name'] as String? ?? m['name'] as String? ?? 'Unknown',
            score: (m['score'] as num?)?.toDouble() ?? 0.8,
            sourceSystem: (m['source_systems'] as List<dynamic>?)?.firstOrNull as String? ?? '—',
          );
        }).toList();
      });
    } catch (_) {
      if (generation != _dupCheckGeneration || !mounted) return;
      setState(() { _isDupChecking = false; _dupCheckDone = true; });
    }
  }

  Future<void> _publish() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
            SizedBox(width: 10),
            Text('Fix the highlighted field errors before publishing.'),
          ]),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isPublishing = true);

    try {
      final tenantId = await AuthManager.getTenantId() ?? '';

      final attributes = _attributes
          .where((a) => a.keyController.text.trim().isNotEmpty)
          .map((a) => {
                'key': a.keyController.text.trim(),
                'value': a.valueController.text.trim(),
                'data_type': a.type,
              })
          .toList();

      final isIngested = _selectedOrigin == _Origin.sourceSystem;
      final recordOrigin = isIngested ? 'ingested' : 'mdm_authoritative';
      final entityId = _generateUuid();

      // Stewards create as Draft; Admins publish directly as Active.
      final status = _isSteward ? 'Draft' : 'Active';

      final entityBody = <String, dynamic>{
        'entity_id': entityId,
        'tenant_id': tenantId,
        'entity_type': _selectedType.label,
        'status': status,
        'attributes': attributes,
      };

      // Include source snapshot when user selected a real (non-manual) source system.
      if (isIngested && _selectedSourceModel.code != 'nexus-mdm') {
        entityBody['source_snapshots'] = [
          {
            'source_system': _selectedSourceModel.code,
            'source_entity_id': entityId,
          }
        ];
      }

      final payload = {
        'entity': entityBody,
        'record_origin': recordOrigin,
        'distribute': _isSteward ? false : _distribute,
        'distribution_targets': <Map<String, dynamic>>[],
      };

      final result = await _repository.createEntity(payload);
      if (!mounted) return;

      switch (result) {
        case Success<CreateEntityResponse>(:final data):
          if (_isSteward) {
            // Auto-submit the new draft for Data Owner review.
            final reviewResult = await _governanceRepo.submitForReview(
              data.entityId,
              changeSummary: 'New ${_selectedType.label} record submitted for review.',
            );
            if (!mounted) return;
            setState(() => _isPublishing = false);
            final msg = reviewResult is Success<bool>
                ? 'Record submitted for Data Owner review.'
                : 'Record saved as draft (submit-for-review failed — try from the entity detail page).';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const Icon(Icons.pending_actions_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(msg,
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white))),
              ]),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ));
          } else {
            setState(() => _isPublishing = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text('Entity published successfully.',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
              ]),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ));
          }
          context.pop(true);
        case Failure<CreateEntityResponse>(:final exception):
          setState(() => _isPublishing = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Failed to create entity: ${exception.message}',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
              ),
            ]),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Error: $e',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
          ),
        ]),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _isSavingDraft = true);
    try {
      final tenantId = await AuthManager.getTenantId() ?? '';
      final attributes = _attributes
          .where((a) => a.keyController.text.trim().isNotEmpty)
          .map((a) => {
                'key': a.keyController.text.trim(),
                'value': a.valueController.text.trim(),
                'data_type': a.type,
              })
          .toList();
      final payload = {
        'entity': {
          'entity_id': _generateUuid(),
          'tenant_id': tenantId,
          'entity_type': _selectedType.label,
          'status': 'Draft',
          'attributes': attributes,
        },
        'record_origin': 'mdm_authoritative',
        'distribute': false,
        'distribution_targets': <Map<String, dynamic>>[],
      };
      final result = await _repository.createEntity(payload);
      if (!mounted) return;
      setState(() => _isSavingDraft = false);
      switch (result) {
        case Success<CreateEntityResponse>():
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Draft saved.',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ));
        case Failure<CreateEntityResponse>(:final exception):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to save draft: ${exception.message}',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingDraft = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error saving draft: $e',
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
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
            backgroundColor: _isSteward ? AppColors.warning : AppColors.primary,
            foregroundColor: _isSteward ? AppColors.navyBackground : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            textStyle: AppTextStyles.buttonMedium,
          ),
          child: _isPublishing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isSteward ? 'Submit for Review' : 'Publish'),
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
                    if (_loadingSources)
                      const SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      _StyledDropdown<SourceSystemModel>(
                        value: _selectedSourceModel,
                        items: _sourceOptions,
                        labelOf: (s) => s.name,
                        onChanged: (v) { if (v != null) setState(() => _selectedSourceModel = v); },
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
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_attributes.length} fields',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _showAddAttributeDialog,
            icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
            label: Text('Add Field',
                style: AppTextStyles.buttonSmall.copyWith(color: AppColors.primary)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('FIELD', style: AppTextStyles.tableHeader)),
                Expanded(flex: 3, child: Text('VALUE', style: AppTextStyles.tableHeader)),
                SizedBox(width: 72, child: Text('TYPE', style: AppTextStyles.tableHeader)),
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

  /// Converts a snake_case key to a human-readable label.
  static String _labelFor(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Widget _buildAttributeInputRow(_AttributeRow attr, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Key — read-only label for predefined, editable field for custom
          Expanded(
            flex: 2,
            child: attr.isCustom
                ? TextFormField(
                    controller: attr.keyController,
                    onChanged: (v) => attr.key = v,
                    decoration: _inputDecoration(hintText: 'field_key'),
                    style: AppTextStyles.inputText
                        .copyWith(fontFamily: 'monospace', fontSize: 13),
                    validator: Validators.required('Field key'),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _labelFor(attr.key),
                      style: AppTextStyles.labelMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: attr.valueController,
              onChanged: (v) {
                attr.value = v;
                if (v.length >= 2) _triggerDupCheck();
              },
              validator: attr.type == 'email' ? Validators.emailOptional : null,
              decoration: _inputDecoration(hintText: 'Enter value…'),
              style: AppTextStyles.inputText,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
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
          // Custom attributes can be removed; predefined ones cannot
          SizedBox(
            width: 32,
            child: attr.isCustom
                ? IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    onPressed: () => _removeAttribute(index),
                    color: AppColors.mutedText,
                    hoverColor: AppColors.error.withValues(alpha: 0.1),
                    tooltip: 'Remove field',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  )
                : const SizedBox.shrink(),
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
            onPressed: () => context.go('/dashboard/entities/${hit.entityId}'),
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
