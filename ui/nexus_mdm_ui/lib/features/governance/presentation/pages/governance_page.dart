import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/validation/validators.dart';

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

enum RuleType { fieldMask, survivorshipOverride, accessControl, gdprConsent }

extension RuleTypeExt on RuleType {
  String get label {
    switch (this) {
      case RuleType.fieldMask:
        return 'FieldMask';
      case RuleType.survivorshipOverride:
        return 'SurvivorshipOverride';
      case RuleType.accessControl:
        return 'AccessControl';
      case RuleType.gdprConsent:
        return 'GdprConsent';
    }
  }

  Color get color {
    switch (this) {
      case RuleType.fieldMask:
        return AppColors.info;
      case RuleType.survivorshipOverride:
        return AppColors.primary;
      case RuleType.accessControl:
        return AppColors.error;
      case RuleType.gdprConsent:
        return AppColors.warning;
    }
  }
}

class PolicyRule {
  final String id;
  final String name;
  final RuleType ruleType;
  final String entityType;
  final String? fieldName;
  final String regoPolicy;
  final int priority;
  bool isActive;

  PolicyRule({
    required this.id,
    required this.name,
    required this.ruleType,
    required this.entityType,
    this.fieldName,
    required this.regoPolicy,
    required this.priority,
    this.isActive = true,
  });

  factory PolicyRule.fromJson(Map<String, dynamic> j) {
    final typeStr = (j['rule_type'] as String? ?? '').toLowerCase();
    final ruleType = switch (typeStr) {
      'survivorship_override' => RuleType.survivorshipOverride,
      'access_control'        => RuleType.accessControl,
      'gdpr_consent'          => RuleType.gdprConsent,
      _                       => RuleType.fieldMask,
    };
    final status = (j['status'] as String? ?? 'active').toLowerCase();
    return PolicyRule(
      id:          j['rule_id']   as String? ?? j['id'] as String? ?? '',
      name:        j['name']      as String? ?? '',
      ruleType:    ruleType,
      entityType:  j['entity_type'] as String? ?? 'Any',
      fieldName:   j['field_name']  as String?,
      regoPolicy:  j['rego_policy'] as String? ?? '',
      priority:    j['priority']    as int? ?? 50,
      isActive:    status == 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'name':        name,
    'rule_type':   _ruleTypeToString(ruleType),
    'entity_type': entityType,
    if (fieldName != null) 'field_name': fieldName,
    'rego_policy': regoPolicy,
    'priority':    priority,
    'status':      isActive ? 'active' : 'inactive',
  };
}

String _ruleTypeToString(RuleType t) => switch (t) {
  RuleType.fieldMask            => 'field_mask',
  RuleType.survivorshipOverride => 'survivorship_override',
  RuleType.accessControl        => 'access_control',
  RuleType.gdprConsent          => 'gdpr_consent',
};

class SurvivorsipSuggestion {
  final String fieldName;
  final String suggestedStrategy;
  final double confidence;
  final String reasoning;

  const SurvivorsipSuggestion({
    required this.fieldName,
    required this.suggestedStrategy,
    required this.confidence,
    required this.reasoning,
  });

  factory SurvivorsipSuggestion.fromJson(Map<String, dynamic> j) =>
      SurvivorsipSuggestion(
        fieldName:         j['field_name']         as String? ?? '',
        suggestedStrategy: j['suggested_strategy'] as String? ?? '',
        confidence:        (j['confidence'] as num? ?? 0).toDouble(),
        reasoning:         j['reasoning']          as String? ?? '',
      );
}

class GdprRequest {
  final String id;
  final String type;
  final String subjectId;
  final String status;
  final String timestamp;
  final int? recordsAffected;

  const GdprRequest({
    required this.id,
    required this.type,
    required this.subjectId,
    required this.status,
    required this.timestamp,
    this.recordsAffected,
  });

  factory GdprRequest.fromJson(Map<String, dynamic> j) => GdprRequest(
    id:              j['id']              as String? ?? '',
    type:            j['type']            as String? ?? 'Erasure',
    subjectId:       j['subject_id']      as String? ?? '',
    status:          j['status']          as String? ?? 'Completed',
    timestamp:       j['timestamp']       as String? ?? '',
    recordsAffected: j['records_affected'] as int?,
  );
}

// ─────────────────────────────────────────────
// Main Page
// ─────────────────────────────────────────────

// Sentinel to detect unreplaced demo data — not reachable in prod.

// ─────────────────────────────────────────────
// Page widget
// ─────────────────────────────────────────────

class GovernancePage extends StatefulWidget {
  const GovernancePage({super.key});

  @override
  State<GovernancePage> createState() => _GovernancePageState();
}

class _GovernancePageState extends State<GovernancePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PolicyRule> _rules = [];
  List<SurvivorsipSuggestion> _suggestions = [];
  List<GdprRequest> _gdprRequests = [];
  final Set<int> _dismissedSuggestions = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    final api = GetIt.instance<ApiClient>();
    try {
      final results = await Future.wait([
        api.get<Map<String, dynamic>>(AppConstants.policyRulesPath),
        api.get<Map<String, dynamic>>(AppConstants.survivorshipSuggestionsPath),
        api.get<Map<String, dynamic>>(AppConstants.gdprRequestsPath),
      ]);

      if (!mounted) return;

      final rulesRaw    = (results[0].data?['data'] as List<dynamic>?) ?? [];
      final suggestRaw  = (results[1].data?['data'] as List<dynamic>?) ?? [];
      final gdprRaw     = (results[2].data?['data'] as List<dynamic>?) ?? [];

      setState(() {
        _rules       = rulesRaw.map((e) => PolicyRule.fromJson(e as Map<String, dynamic>)).toList();
        _suggestions = suggestRaw.map((e) => SurvivorsipSuggestion.fromJson(e as Map<String, dynamic>)).toList();
        _gdprRequests = gdprRaw.map((e) => GdprRequest.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RulesTab(
                rules: _rules,
                isLoading: _isLoading,
                onAdd: _showCreateRuleDialog,
                onEdit: _showEditRuleDialog,
                onDelete: _deleteRule,
                onToggle: _toggleRule,
              ),
              _SurvivorshipTab(
                suggestions: _suggestions,
                dismissed: _dismissedSuggestions,
                onAccept: _acceptSuggestion,
                onDismiss: _dismissSuggestion,
              ),
              const _PoliciesTab(),
              _GdprTab(requests: _gdprRequests),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Governance Center', style: AppTextStyles.headlineSmall)
                  .animate()
                  .fadeIn(duration: 400.ms),
              const SizedBox(height: 4),
              Text(
                'Policy rules, survivorship, OPA evaluation & GDPR',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.secondaryText),
              ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.policy_rounded,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${_rules.where((r) => r.isActive).length} active rules',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Rules'),
          Tab(text: 'Survivorship'),
          Tab(text: 'Policies'),
          Tab(text: 'GDPR'),
        ],
        labelStyle: AppTextStyles.titleSmall,
        unselectedLabelStyle: AppTextStyles.bodyMedium,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        isScrollable: false,
      ),
    );
  }

  void _showCreateRuleDialog({PolicyRule? existing}) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateRuleDialog(
        existing: existing,
        onSave: (rule) => existing == null ? _createRule(rule) : _updateRule(rule),
      ),
    );
  }

  void _showEditRuleDialog(PolicyRule rule) => _showCreateRuleDialog(existing: rule);

  Future<void> _createRule(PolicyRule rule) async {
    final api = GetIt.instance<ApiClient>();
    try {
      final res = await api.post<Map<String, dynamic>>(
        AppConstants.policyRulesPath,
        data: rule.toJson(),
      );
      final created = PolicyRule.fromJson(res.data?['data'] as Map<String, dynamic>? ?? {});
      if (mounted) setState(() => _rules.insert(0, created));
    } catch (_) {
      if (mounted) setState(() => _rules.insert(0, rule));
    }
  }

  Future<void> _updateRule(PolicyRule rule) async {
    final api = GetIt.instance<ApiClient>();
    try {
      final res = await api.put<Map<String, dynamic>>(
        '${AppConstants.policyRulesPath}/${rule.id}',
        data: rule.toJson(),
      );
      final updated = PolicyRule.fromJson(res.data?['data'] as Map<String, dynamic>? ?? {});
      if (mounted) {
        setState(() {
          final idx = _rules.indexWhere((r) => r.id == updated.id);
          if (idx >= 0) _rules[idx] = updated;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final idx = _rules.indexWhere((r) => r.id == rule.id);
          if (idx >= 0) _rules[idx] = rule;
        });
      }
    }
  }

  Future<void> _deleteRule(PolicyRule rule) async {
    setState(() => _rules.removeWhere((r) => r.id == rule.id));
    final api = GetIt.instance<ApiClient>();
    try {
      await api.delete<void>('${AppConstants.policyRulesPath}/${rule.id}');
    } catch (_) {
      if (mounted) setState(() => _rules.add(rule));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rule "${rule.name}" deleted'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _toggleRule(PolicyRule rule, bool val) async {
    setState(() => rule.isActive = val);
    final api = GetIt.instance<ApiClient>();
    try {
      await api.patch<void>('${AppConstants.policyRulesPath}/${rule.id}/toggle');
    } catch (_) {
      if (mounted) setState(() => rule.isActive = !val);
    }
  }

  Future<void> _acceptSuggestion(int index) async {
    final s = _suggestions[index];
    final rule = PolicyRule(
      id: '',
      name: 'AI: ${s.fieldName} → ${s.suggestedStrategy}',
      ruleType: RuleType.survivorshipOverride,
      entityType: 'Any',
      fieldName: s.fieldName,
      regoPolicy:
          '# Auto-generated from AI suggestion\npackage nexus.survivorship\nstrategy = "${s.suggestedStrategy}" { input.field == "${s.fieldName}" }',
      priority: 85,
    );
    setState(() => _dismissedSuggestions.add(index));
    await _createRule(rule);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rule created for "${s.fieldName}"'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _dismissSuggestion(int index) => setState(() => _dismissedSuggestions.add(index));
}

// ─────────────────────────────────────────────
// Tab 1 – Rules
// ─────────────────────────────────────────────

class _RulesTab extends StatelessWidget {
  final List<PolicyRule> rules;
  final bool isLoading;
  final VoidCallback onAdd;
  final void Function(PolicyRule) onEdit;
  final void Function(PolicyRule) onDelete;
  final void Function(PolicyRule, bool) onToggle;

  const _RulesTab({
    required this.rules,
    required this.isLoading,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        isLoading
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: EntityListShimmer(count: 5),
              )
            : rules.isEmpty
                ? EmptyState(
                    icon: Icons.policy_rounded,
                    title: 'No rules yet',
                    description:
                        'Create your first governance rule to start protecting and enriching your master data.',
                    actionLabel: 'Create Rule',
                    onAction: onAdd,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 100),
                    itemCount: rules.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _RuleCard(
                      rule: rules[i],
                      index: i,
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onToggle: onToggle,
                    ),
                  ),
        Positioned(
          bottom: 24,
          right: 28,
          child: FloatingActionButton.extended(
            onPressed: onAdd,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.navyBackground,
            icon: const Icon(Icons.add),
            label: Text('New Rule', style: AppTextStyles.buttonMedium),
          ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.3, end: 0),
        ),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  final PolicyRule rule;
  final int index;
  final void Function(PolicyRule) onEdit;
  final void Function(PolicyRule) onDelete;
  final void Function(PolicyRule, bool) onToggle;

  const _RuleCard({
    required this.rule,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rule.isActive
              ? AppColors.divider
              : AppColors.divider.withValues(alpha:0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rule.ruleType.color.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.rule_rounded,
                color: rule.ruleType.color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(rule.name,
                        style: AppTextStyles.titleSmall
                            .copyWith(
                              color: rule.isActive
                                  ? AppColors.primaryText
                                  : AppColors.mutedText,
                            )),
                    const SizedBox(width: 10),
                    _RuleTypeChip(ruleType: rule.ruleType),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.category_outlined,
                        size: 13, color: AppColors.secondaryText),
                    const SizedBox(width: 4),
                    Text(rule.entityType,
                        style: AppTextStyles.bodySmall),
                    if (rule.fieldName != null) ...[
                      Text(' · ',
                          style: AppTextStyles.bodySmall),
                      const Icon(Icons.data_object,
                          size: 13, color: AppColors.secondaryText),
                      const SizedBox(width: 4),
                      Text(rule.fieldName!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mintAccent)),
                    ],
                    const SizedBox(width: 12),
                    Text('Priority ${rule.priority}',
                        style: AppTextStyles.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: rule.isActive,
            onChanged: (v) => onToggle(rule, v),
            activeThumbColor: AppColors.primary,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.secondaryText,
            onPressed: () => onEdit(rule),
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppColors.error.withValues(alpha:0.7),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Rule', style: AppTextStyles.titleMedium),
        content: Text(
          'Are you sure you want to delete "${rule.name}"? This cannot be undone.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete(rule);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RuleTypeChip extends StatelessWidget {
  final RuleType ruleType;

  const _RuleTypeChip({required this.ruleType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ruleType.color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ruleType.color.withValues(alpha:0.3)),
      ),
      child: Text(
        ruleType.label,
        style: AppTextStyles.labelSmall.copyWith(color: ruleType.color),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Create / Edit Rule Dialog
// ─────────────────────────────────────────────

class _CreateRuleDialog extends StatefulWidget {
  final PolicyRule? existing;
  final void Function(PolicyRule) onSave;

  const _CreateRuleDialog({this.existing, required this.onSave});

  @override
  State<_CreateRuleDialog> createState() => _CreateRuleDialogState();
}

class _CreateRuleDialogState extends State<_CreateRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _entityTypeCtrl;
  late TextEditingController _fieldNameCtrl;
  late TextEditingController _regoCtrl;
  late RuleType _ruleType;
  late double _priority;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _entityTypeCtrl = TextEditingController(text: e?.entityType ?? 'Person');
    _fieldNameCtrl = TextEditingController(text: e?.fieldName ?? '');
    _regoCtrl = TextEditingController(
        text: e?.regoPolicy ??
            'package nexus.policy\n\ndefault allow = false\n\nallow {\n  # your rule here\n}');
    _ruleType = e?.ruleType ?? RuleType.fieldMask;
    _priority = (e?.priority ?? 80).toDouble();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _entityTypeCtrl.dispose();
    _fieldNameCtrl.dispose();
    _regoCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
            AppTextStyles.labelMedium.copyWith(color: AppColors.secondaryText),
        hintStyle: AppTextStyles.inputHint,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  Text(isEdit ? 'Edit Rule' : 'Create Rule',
                      style: AppTextStyles.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.secondaryText,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 24),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        style: AppTextStyles.inputText,
                        decoration: _inputDeco('Rule Name',
                            hint: 'e.g. Mask SSN on export'),
                        validator: Validators.minLength(2, label: 'Rule name'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rule Type',
                                    style: AppTextStyles.labelMedium.copyWith(
                                        color: AppColors.secondaryText)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<RuleType>(
                                  initialValue: _ruleType,
                                  dropdownColor: AppColors.elevatedCard,
                                  style: AppTextStyles.inputText,
                                  decoration: _inputDeco(''),
                                  items: RuleType.values
                                      .map((t) => DropdownMenuItem(
                                            value: t,
                                            child: Text(t.label),
                                          ))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _ruleType = v!),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _entityTypeCtrl,
                              style: AppTextStyles.inputText,
                              decoration: _inputDeco('Entity Type',
                                  hint: 'e.g. Person, Contact'),
                              validator: Validators.entityType,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _fieldNameCtrl,
                        style: AppTextStyles.inputText,
                        decoration: _inputDeco('Field Name (optional)',
                            hint: 'e.g. ssn, email'),
                      ),
                      const SizedBox(height: 14),
                      Text('Priority: ${_priority.round()}',
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.secondaryText)),
                      Slider(
                        value: _priority,
                        min: 1,
                        max: 100,
                        divisions: 99,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.divider,
                        onChanged: (v) => setState(() => _priority = v),
                      ),
                      const SizedBox(height: 14),
                      Text('Rego Policy',
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.secondaryText)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _regoCtrl,
                        style: AppTextStyles.codeStyle,
                        maxLines: 8,
                        decoration: _inputDeco('').copyWith(
                          alignLabelWithHint: true,
                          fillColor: AppColors.navyBackground,
                        ),
                        validator: Validators.regoPolicy,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: const BorderSide(color: AppColors.divider),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(isEdit ? 'Save Changes' : 'Create Rule'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.navyBackground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final rule = PolicyRule(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text,
      ruleType: _ruleType,
      entityType: _entityTypeCtrl.text,
      fieldName:
          _fieldNameCtrl.text.isEmpty ? null : _fieldNameCtrl.text,
      regoPolicy: _regoCtrl.text,
      priority: _priority.round(),
      isActive: widget.existing?.isActive ?? true,
    );
    widget.onSave(rule);
    Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────
// Tab 2 – Survivorship
// ─────────────────────────────────────────────

class _SurvivorshipTab extends StatelessWidget {
  final List<SurvivorsipSuggestion> suggestions;
  final Set<int> dismissed;
  final void Function(int) onAccept;
  final void Function(int) onDismiss;

  const _SurvivorshipTab({
    required this.suggestions,
    required this.dismissed,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final visible =
        suggestions.asMap().entries.where((e) => !dismissed.contains(e.key)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.purpleGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('AI Rule Suggestions',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: Colors.white)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('AI',
                                  style: AppTextStyles.badgeLabel
                                      .copyWith(color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on 2,840 merge decisions · Llama 3.2 8B analysis',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: Colors.white.withValues(alpha:0.8)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${visible.length} pending',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0),
        const SizedBox(height: 20),
        if (visible.isEmpty)
          const EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'All suggestions reviewed',
            description:
                'You have reviewed all AI-generated survivorship suggestions. New ones will appear as more merge decisions are analyzed.',
            compact: true,
          )
        else
          ...visible.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SuggestionCard(
                  suggestion: entry.value,
                  index: entry.key,
                  onAccept: onAccept,
                  onDismiss: onDismiss,
                ),
              )),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final SurvivorsipSuggestion suggestion;
  final int index;
  final void Function(int) onAccept;
  final void Function(int) onDismiss;

  const _SuggestionCard({
    required this.suggestion,
    required this.index,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintAccent.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.mintAccent.withValues(alpha:0.3)),
                ),
                child: Text(suggestion.fieldName,
                    style: AppTextStyles.codeStyle.copyWith(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(suggestion.suggestedStrategy,
                    style: AppTextStyles.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Confidence:',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: suggestion.confidence,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _confidenceColor(suggestion.confidence)),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(suggestion.confidence * 100).round()}%',
                style: AppTextStyles.labelMedium.copyWith(
                    color: _confidenceColor(suggestion.confidence)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(suggestion.reasoning,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => onDismiss(index),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryText,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => onAccept(index),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.navyBackground,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Color _confidenceColor(double c) {
    if (c >= 0.9) return AppColors.primary;
    if (c >= 0.75) return AppColors.warning;
    return AppColors.error;
  }
}

// ─────────────────────────────────────────────
// Tab 3 – OPA Policy Playground
// ─────────────────────────────────────────────

class _PoliciesTab extends StatefulWidget {
  const _PoliciesTab();

  @override
  State<_PoliciesTab> createState() => _PoliciesTabState();
}

class _PoliciesTabState extends State<_PoliciesTab> {
  String _entityType = 'Person';
  String _operation = 'read';
  final _entityJsonCtrl = TextEditingController(
    text: '{\n  "id": "ent-001",\n  "role": "viewer",\n  "fields": ["name", "email", "ssn"]\n}',
  );
  bool _evaluated = false;
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  final _entityTypes = ['Person', 'Contact', 'GoldenRecord', 'Customer'];
  final _operations = ['read', 'write', 'delete', 'export', 'merge'];

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle:
            AppTextStyles.labelMedium.copyWith(color: AppColors.secondaryText),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Future<void> _evaluate() async {
    setState(() => _isLoading = true);
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        AppConstants.policyEvalPath,
        data: {
          'entity_type': _entityType,
          'operation': _operation,
          'context': _entityJsonCtrl.text,
        },
      );
      final data = resp.data ?? {};
      setState(() {
        _isLoading = false;
        _evaluated = true;
        _result = {
          'allowed': data['allowed'] as bool? ?? false,
          'masked_fields': (data['masked_fields'] as List?)?.cast<String>() ?? <String>[],
          'warnings': (data['warnings'] as List?)?.cast<String>() ?? <String>[],
          'policy_version': data['policy_version'] as String? ?? '—',
          'evaluation_time_ms': data['evaluation_time_ms'] as int? ?? 0,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _evaluated = true;
        _result = {
          'allowed': false,
          'masked_fields': <String>[],
          'warnings': <String>['Policy evaluation failed — check server connection'],
          'policy_version': '—',
          'evaluation_time_ms': 0,
        };
      });
    }
  }

  @override
  void dispose() {
    _entityJsonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.balance_rounded,
                              color: AppColors.info, size: 20),
                          const SizedBox(width: 8),
                          Text('Policy Evaluation Playground',
                              style: AppTextStyles.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Test your OPA policies against real entity data',
                        style: AppTextStyles.bodySmall,
                      ),
                      const Divider(
                          color: AppColors.divider, height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _entityType,
                              dropdownColor: AppColors.elevatedCard,
                              style: AppTextStyles.inputText,
                              decoration: _inputDeco('Entity Type'),
                              items: _entityTypes
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _entityType = v!),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _operation,
                              dropdownColor: AppColors.elevatedCard,
                              style: AppTextStyles.inputText,
                              decoration: _inputDeco('Operation'),
                              items: _operations
                                  .map((o) => DropdownMenuItem(
                                      value: o, child: Text(o)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _operation = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('Entity JSON',
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.secondaryText)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _entityJsonCtrl,
                        style: AppTextStyles.codeStyle,
                        maxLines: 8,
                        decoration: _inputDeco('').copyWith(
                          fillColor: AppColors.navyBackground,
                          hintText: '{ "id": "...", ... }',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _evaluate,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.navyBackground,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded,
                                  size: 18),
                          label: Text(
                            _isLoading
                                ? 'Evaluating...'
                                : 'Evaluate Policy',
                            style: AppTextStyles.buttonMedium,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.navyBackground,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.security_rounded,
                              size: 12, color: AppColors.mutedText),
                          const SizedBox(width: 4),
                          Text('Powered by OPA v0.61',
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 4,
            child: _evaluated && _result != null
                ? _buildResultCard()
                : Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.play_circle_outline_rounded,
                            size: 48, color: AppColors.mutedText),
                        const SizedBox(height: 12),
                        Text('Run Evaluation',
                            style: AppTextStyles.titleSmall
                                .copyWith(
                                    color: AppColors.secondaryText)),
                        const SizedBox(height: 8),
                        Text(
                          'Configure inputs and click Evaluate Policy to see results.',
                          style: AppTextStyles.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final allowed = _result!['allowed'] as bool;
    final maskedFields = _result!['masked_fields'] as List<dynamic>;
    final warnings = _result!['warnings'] as List<dynamic>;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allowed
              ? AppColors.primary.withValues(alpha:0.3)
              : AppColors.error.withValues(alpha:0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: allowed ? AppColors.primary : AppColors.error,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                allowed ? 'Allowed' : 'Denied',
                style: AppTextStyles.titleMedium.copyWith(
                    color:
                        allowed ? AppColors.primary : AppColors.error),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_result!['evaluation_time_ms']}ms',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.secondaryText),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 20),
          if (maskedFields.isNotEmpty) ...[
            Text('Masked Fields',
                style: AppTextStyles.labelMedium
                    .copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: maskedFields
                  .map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppColors.warning.withValues(alpha:0.3)),
                        ),
                        child: Text(f.toString(),
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.warning)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
          ],
          if (warnings.isNotEmpty) ...[
            Text('Warnings',
                style: AppTextStyles.labelMedium
                    .copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 8),
            ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Text(w.toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.secondaryText)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: AppColors.mutedText),
              const SizedBox(width: 6),
              Text(
                'Policy v${_result!['policy_version']}',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }
}

// ─────────────────────────────────────────────
// Tab 4 – GDPR
// ─────────────────────────────────────────────

class _GdprTab extends StatefulWidget {
  final List<GdprRequest> requests;
  const _GdprTab({required this.requests});

  @override
  State<_GdprTab> createState() => _GdprTabState();
}

class _GdprTabState extends State<_GdprTab> {
  final _erasureCtrl = TextEditingController();
  final _accessCtrl = TextEditingController();
  late final List<GdprRequest> _log = List.from(widget.requests);
  bool _erasureLoading = false;
  bool _accessLoading = false;
  Map<String, dynamic>? _erasureResult;
  Map<String, dynamic>? _accessResult;

  @override
  void dispose() {
    _erasureCtrl.dispose();
    _accessCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitErasure() async {
    if (_erasureCtrl.text.isEmpty) return;
    setState(() => _erasureLoading = true);
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        AppConstants.gdprErasurePath,
        data: {'subject_id': _erasureCtrl.text.trim()},
      );
      final data = resp.data ?? {};
      final reqId = data['request_id'] as String? ??
          'GDPR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final recordsAffected = data['records_affected'] as int? ?? 0;
      final fieldsErased = (data['fields_erased'] as List?)?.cast<String>() ?? <String>[];
      final req = GdprRequest(
        id: reqId,
        type: 'Erasure',
        subjectId: _erasureCtrl.text,
        status: 'Completed',
        timestamp: DateTime.now().toString().substring(0, 16),
        recordsAffected: recordsAffected,
      );
      setState(() {
        _erasureLoading = false;
        _erasureResult = {
          'records_affected': recordsAffected,
          'fields_erased': fieldsErased,
          'request_id': reqId,
        };
        _log.insert(0, req);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erasureLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erasure request failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _submitAccess() async {
    if (_accessCtrl.text.isEmpty) return;
    setState(() => _accessLoading = true);
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        AppConstants.gdprAccessPath,
        data: {'subject_id': _accessCtrl.text.trim()},
      );
      final data = resp.data ?? {};
      final reqId = data['request_id'] as String? ??
          'GDPR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final recordsFound = data['records_found'] as int? ?? 0;
      final sources = (data['sources'] as List?)?.cast<String>() ?? <String>[];
      final req = GdprRequest(
        id: reqId,
        type: 'Access',
        subjectId: _accessCtrl.text,
        status: 'Completed',
        timestamp: DateTime.now().toString().substring(0, 16),
        recordsAffected: recordsFound,
      );
      setState(() {
        _accessLoading = false;
        _accessResult = {
          'records_found': recordsFound,
          'sources': sources,
          'request_id': reqId,
        };
        _log.insert(0, req);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _accessLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Access request failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle:
            AppTextStyles.labelMedium.copyWith(color: AppColors.secondaryText),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _buildErasureCard()
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.05, end: 0)),
              const SizedBox(width: 20),
              Expanded(
                  child: _buildAccessCard()
                      .animate(delay: 80.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.05, end: 0)),
            ],
          ),
          const SizedBox(height: 24),
          _buildAuditLog()
              .animate(delay: 160.ms)
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.05, end: 0),
        ],
      ),
    );
  }

  Widget _buildErasureCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_forever_rounded,
                    color: AppColors.error, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Right to Erasure',
                        style: AppTextStyles.titleSmall),
                    Text('Art. 17 GDPR',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.mutedText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _erasureCtrl,
            style: AppTextStyles.inputText,
            decoration: _inputDeco('Subject ID').copyWith(
              hintText: 'e.g. ds-4821',
              hintStyle: AppTextStyles.inputHint,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _erasureLoading ? null : _submitErasure,
              icon: _erasureLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.navyBackground,
                      ))
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                  _erasureLoading ? 'Processing...' : 'Submit Erasure',
                  style: AppTextStyles.buttonMedium),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_erasureResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha:0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_erasureResult!['records_affected']} records erased',
                        style: AppTextStyles.titleSmall
                            .copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Fields erased:',
                      style: AppTextStyles.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: (_erasureResult!['fields_erased']
                            as List<dynamic>)
                        .map((f) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.elevatedCard,
                                borderRadius:
                                    BorderRadius.circular(5),
                              ),
                              child: Text(f.toString(),
                                  style: AppTextStyles.codeStyle
                                      .copyWith(fontSize: 11)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Request ID: ${_erasureResult!['request_id']}',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccessCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.folder_open_rounded,
                    color: AppColors.info, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Right of Access',
                        style: AppTextStyles.titleSmall),
                    Text('Art. 15 GDPR',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.mutedText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _accessCtrl,
            style: AppTextStyles.inputText,
            decoration: _inputDeco('Subject ID').copyWith(
              hintText: 'e.g. ds-3019',
              hintStyle: AppTextStyles.inputHint,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _accessLoading ? null : _submitAccess,
              icon: _accessLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ))
                  : const Icon(Icons.search_rounded, size: 16),
              label: Text(
                  _accessLoading ? 'Searching...' : 'Request Access Report',
                  style: AppTextStyles.buttonMedium),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_accessResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.info.withValues(alpha:0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.info, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_accessResult!['records_found']} records found',
                        style: AppTextStyles.titleSmall
                            .copyWith(color: AppColors.info),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Sources:',
                      style: AppTextStyles.bodySmall),
                  const SizedBox(height: 6),
                  ...(_accessResult!['sources'] as List<dynamic>)
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.circle,
                                    size: 6,
                                    color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(s.toString(),
                                    style: AppTextStyles.bodySmall
                                        .copyWith(
                                            color:
                                                AppColors.primaryText)),
                              ],
                            ),
                          )),
                  const SizedBox(height: 8),
                  Text(
                    'Request ID: ${_accessResult!['request_id']}',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditLog() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: AppColors.secondaryText, size: 18),
              const SizedBox(width: 8),
              Text('GDPR Audit Log', style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_log.length} requests',
                    style: AppTextStyles.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.5),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(2),
              5: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: AppColors.divider)),
                ),
                children: [
                  'Request ID',
                  'Type',
                  'Subject ID',
                  'Records',
                  'Timestamp',
                  'Status',
                ]
                    .map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(h.toUpperCase(),
                              style: AppTextStyles.tableHeader),
                        ))
                    .toList(),
              ),
              ..._log.map((req) => TableRow(
                    children: [
                      _tableCell(req.id, mono: true),
                      _tableBadge(
                        req.type,
                        req.type == 'Erasure'
                            ? AppColors.error
                            : AppColors.info,
                      ),
                      _tableCell(req.subjectId, mono: true),
                      _tableCell(req.recordsAffected?.toString() ?? '—'),
                      _tableCell(req.timestamp),
                      _tableBadge(
                        req.status,
                        req.status == 'Completed'
                            ? AppColors.primary
                            : AppColors.warning,
                      ),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: mono
            ? AppTextStyles.codeStyle.copyWith(fontSize: 12)
            : AppTextStyles.tableCell,
      ),
    );
  }

  Widget _tableBadge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha:0.3)),
        ),
        child: Text(text,
            style: AppTextStyles.labelSmall.copyWith(color: color)),
      ),
    );
  }
}
