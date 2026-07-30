import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/blocking_rules_repository.dart';
import '../../data/entity_type_repository.dart';
import '../../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// Strategy helpers
// ---------------------------------------------------------------------------

enum _Strategy { exact, phonetic, canopy, vector }

extension _StrategyExt on _Strategy {
  String get label {
    switch (this) {
      case _Strategy.exact:
        return 'exact';
      case _Strategy.phonetic:
        return 'phonetic';
      case _Strategy.canopy:
        return 'canopy';
      case _Strategy.vector:
        return 'vector';
    }
  }

  bool get requiresField => this != _Strategy.vector;

  IconData get icon {
    switch (this) {
      case _Strategy.exact:
        return Icons.fingerprint_outlined;
      case _Strategy.phonetic:
        return Icons.record_voice_over_outlined;
      case _Strategy.canopy:
        return Icons.hub_outlined;
      case _Strategy.vector:
        return Icons.auto_awesome_outlined;
    }
  }
}

_Strategy? _parseStrategy(String s) {
  switch (s) {
    case 'exact':
      return _Strategy.exact;
    case 'phonetic':
      return _Strategy.phonetic;
    case 'canopy':
      return _Strategy.canopy;
    case 'vector':
      return _Strategy.vector;
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class BlockingRulesPage extends StatefulWidget {
  const BlockingRulesPage({super.key});

  @override
  State<BlockingRulesPage> createState() => _BlockingRulesPageState();
}

class _BlockingRulesPageState extends State<BlockingRulesPage> {
  final _entityTypeRepo = GetIt.instance<EntityTypeRepository>();
  final _rulesRepo = GetIt.instance<BlockingRulesRepository>();

  String _tenantId = '';

  // Entity type list state
  List<EntityTypeModel> _entityTypes = [];
  bool _loadingTypes = true;
  String? _typesError;

  // Selected entity type + its rules state
  EntityTypeModel? _selected;
  List<String> _rules = [];
  bool _isDefault = false;
  bool _loadingRules = false;
  bool _savingRules = false;
  String? _rulesError;

  @override
  void initState() {
    super.initState();
    _initTenantAndLoad();
  }

  Future<void> _initTenantAndLoad() async {
    _tenantId = await AuthManager.getTenantId() ?? '';
    _loadEntityTypes();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadEntityTypes() async {
    setState(() {
      _loadingTypes = true;
      _typesError = null;
    });
    final result = await _entityTypeRepo.listEntityTypes(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<EntityTypeModel>>(:final data):
        setState(() {
          _entityTypes = data;
          _loadingTypes = false;
        });
      case Failure<List<EntityTypeModel>>(:final exception):
        setState(() {
          _typesError = exception.message;
          _loadingTypes = false;
        });
    }
  }

  Future<void> _selectEntityType(EntityTypeModel et) async {
    if (_selected?.id == et.id) return;
    setState(() {
      _selected = et;
      _rules = [];
      _isDefault = false;
      _loadingRules = true;
      _rulesError = null;
    });
    final result = await _rulesRepo.getRules(_tenantId, et.code);
    if (!mounted) return;
    switch (result) {
      case Success<BlockingRulesModel>(:final data):
        setState(() {
          _rules = List<String>.from(data.rules);
          _isDefault = data.isDefault;
          _loadingRules = false;
        });
      case Failure<BlockingRulesModel>(:final exception):
        setState(() {
          _rulesError = exception.message;
          _loadingRules = false;
        });
    }
  }

  // ---------------------------------------------------------------------------
  // Rule mutations
  // ---------------------------------------------------------------------------

  void _removeRule(String rule) {
    setState(() => _rules.remove(rule));
  }

  void _showAddRuleDialog() {
    showDialog<String>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _AddRuleDialog(existingRules: _rules),
    ).then((rule) {
      if (rule != null && mounted) {
        setState(() => _rules.add(rule));
      }
    });
  }

  Future<void> _saveRules() async {
    if (_selected == null) return;
    setState(() => _savingRules = true);
    final result =
        await _rulesRepo.saveRules(_tenantId, _selected!.code, _rules);
    if (!mounted) return;
    setState(() => _savingRules = false);
    switch (result) {
      case Success<BlockingRulesModel>(:final data):
        setState(() {
          _rules = List<String>.from(data.rules);
          _isDefault = data.isDefault;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.successLight,
          content: Text(
            'Blocking rules saved.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success),
          ),
          behavior: SnackBarBehavior.floating,
        ));
      case Failure<BlockingRulesModel>(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.errorLight,
          content: Text(
            exception.message,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 700) {
                  return _buildWideLayout();
                }
                return _buildNarrowLayout();
              },
            ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Blocking Rules', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Configure deduplication blocking rules per entity type',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Two-column layout for wide screens
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 268,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.divider)),
            ),
            child: _buildEntityTypePanel(scrollable: true),
          ),
        ),
        Expanded(child: _buildRulesPanel(padded: true)),
      ],
    );
  }

  // Single-column layout for narrow screens
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Entity Types', style: AppTextStyles.titleSmall),
          const SizedBox(height: 12),
          _buildEntityTypePanel(scrollable: false),
          if (_selected != null) ...[
            const SizedBox(height: 24),
            _buildRulesPanel(padded: false),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Entity type panel
  // ---------------------------------------------------------------------------

  Widget _buildEntityTypePanel({required bool scrollable}) {
    if (_loadingTypes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_typesError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 36),
            const SizedBox(height: 10),
            Text(
              _typesError!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loadEntityTypes,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_entityTypes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No entity types defined.',
          style: AppTextStyles.bodySmall,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: !scrollable,
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _entityTypes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final et = _entityTypes[i];
        return _EntityTypeCard(
          entityType: et,
          selected: _selected?.id == et.id,
          onTap: () => _selectEntityType(et),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Rules panel
  // ---------------------------------------------------------------------------

  Widget _buildRulesPanel({required bool padded}) {
    if (_selected == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.tune_outlined,
                color: AppColors.mutedText, size: 48),
            const SizedBox(height: 14),
            Text(
              'Select an entity type to configure\nits blocking rules.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected entity type title
        Row(
          children: [
            Text(
              _selected!.icon.isNotEmpty ? _selected!.icon : '📄',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 10),
            Text(
              _selected!.name.isNotEmpty ? _selected!.name : _selected!.code,
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                _selected!.code,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.secondaryText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_loadingRules)
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        else if (_rulesError != null)
          _ErrorBanner(message: _rulesError!)
        else ...[
          // "Using defaults" amber banner
          if (_isDefault)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Using defaults — no custom rules saved for this entity type.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Rules card
          Container(
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
                    Text('Rules', style: AppTextStyles.titleSmall),
                    const Spacer(),
                    _AddRuleButton(onTap: _showAddRuleDialog),
                  ],
                ),
                const SizedBox(height: 14),
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No rules configured. Press "Add Rule" to begin.',
                      style: AppTextStyles.bodySmall,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _rules
                        .map((r) => _RuleChip(
                              rule: r,
                              onRemove: () => _removeRule(r),
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            child: _SaveButton(saving: _savingRules, onTap: _saveRules),
          ),
        ],
      ],
    );

    return SingleChildScrollView(
      padding: padded
          ? const EdgeInsets.all(24)
          : const EdgeInsets.only(top: 8),
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Entity type selectable card
// ---------------------------------------------------------------------------

class _EntityTypeCard extends StatelessWidget {
  final EntityTypeModel entityType;
  final bool selected;
  final VoidCallback onTap;

  const _EntityTypeCard({
    required this.entityType,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.sidebarSelected : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(
              entityType.icon.isNotEmpty ? entityType.icon : '📄',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entityType.name.isNotEmpty
                        ? entityType.name
                        : entityType.code,
                    style: AppTextStyles.labelMedium.copyWith(
                      color:
                          selected ? AppColors.primary : AppColors.primaryText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    entityType.code,
                    style: AppTextStyles.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.chevron_right,
                  color: AppColors.primary, size: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rule chip
// ---------------------------------------------------------------------------

class _RuleChip extends StatelessWidget {
  final String rule;
  final VoidCallback onRemove;

  const _RuleChip({required this.rule, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final parts = rule.split(':');
    final strategyStr = parts[0];
    final field = parts.length > 1 ? parts[1] : null;
    final strategy = _parseStrategy(strategyStr);
    final icon = strategy?.icon ?? Icons.rule_outlined;
    final label =
        field != null && field.isNotEmpty ? '$strategyStr: $field' : strategyStr;

    return Container(
      padding:
          const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.chipLabel
                .copyWith(color: AppColors.primaryText),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.divider,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close,
                  size: 12, color: AppColors.secondaryText),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Rule button (outline style)
// ---------------------------------------------------------------------------

class _AddRuleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddRuleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              'Add Rule',
              style: AppTextStyles.buttonSmall
                  .copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save button (gradient)
// ---------------------------------------------------------------------------

class _SaveButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool saving;

  const _SaveButton({required this.onTap, required this.saving});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: saving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: saving ? null : AppColors.primaryGradient,
          color: saving ? AppColors.cardSurface : null,
          borderRadius: BorderRadius.circular(8),
          border: saving
              ? Border.all(color: AppColors.divider)
              : null,
        ),
        alignment: Alignment.center,
        child: saving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Text(
                'Save Rules',
                style: AppTextStyles.buttonMedium
                    .copyWith(color: Colors.white),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Rule dialog
// ---------------------------------------------------------------------------

class _AddRuleDialog extends StatefulWidget {
  final List<String> existingRules;

  const _AddRuleDialog({required this.existingRules});

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fieldCtrl = TextEditingController();
  _Strategy? _strategy;
  String? _dialogError;

  @override
  void dispose() {
    _fieldCtrl.dispose();
    super.dispose();
  }

  String _buildRule() {
    if (_strategy == _Strategy.vector) return 'vector';
    return '${_strategy!.label}:${_fieldCtrl.text.trim()}';
  }

  void _submit() {
    setState(() => _dialogError = null);
    if (!_formKey.currentState!.validate()) return;
    final rule = _buildRule();
    if (widget.existingRules.contains(rule)) {
      setState(() => _dialogError = 'This rule already exists.');
      return;
    }
    Navigator.of(context).pop(rule);
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.inputHint,
      filled: true,
      fillColor: AppColors.inputFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        borderSide:
            const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsField =
        _strategy != null && _strategy!.requiresField;

    return Dialog(
      backgroundColor: AppColors.modalBackground,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dialog title
                Text('Add Blocking Rule',
                    style: AppTextStyles.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Define how candidate record pairs are grouped for matching.',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 20),

                // Strategy dropdown
                Text(
                  'STRATEGY',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.mutedText, letterSpacing: 0.8),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<_Strategy>(
                  initialValue: _strategy,
                  dropdownColor: AppColors.elevatedCard,
                  style: AppTextStyles.inputText,
                  decoration: _fieldDecoration('Select a strategy'),
                  validator: (v) =>
                      v == null ? 'Strategy is required' : null,
                  onChanged: (v) => setState(() {
                    _strategy = v;
                    if (v == _Strategy.vector) _fieldCtrl.clear();
                  }),
                  items: _Strategy.values.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Icon(s.icon,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(s.label,
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                // Field input — animated in/out
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      SizeTransition(sizeFactor: anim, child: child),
                  child: needsField
                      ? Padding(
                          key: const ValueKey('field-visible'),
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FIELD',
                                style: AppTextStyles.labelSmall
                                    .copyWith(
                                        color: AppColors.mutedText,
                                        letterSpacing: 0.8),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _fieldCtrl,
                                style: AppTextStyles.inputText,
                                decoration: _fieldDecoration(
                                    'e.g. email, legal_name'),
                                validator: (v) {
                                  if (!needsField) return null;
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Field is required';
                                  }
                                  if (!RegExp(r'^[a-z_]+$')
                                      .hasMatch(v.trim())) {
                                    return 'Only lowercase letters and underscores allowed';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('field-hidden')),
                ),

                // Duplicate error
                if (_dialogError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dialogError!,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Cancel / Add buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.buttonMedium.copyWith(
                              color: AppColors.secondaryText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _submit,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Add',
                            style: AppTextStyles.buttonMedium
                                .copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
