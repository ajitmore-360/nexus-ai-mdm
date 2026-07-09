import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/license/licensed_module.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/license_gate.dart';
import '../../../../shared/widgets/azile_dialog.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Domain models
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

enum _RuleSeverity { critical, high, medium, low }

extension _RuleSeverityX on _RuleSeverity {
  String get label =>
      name[0].toUpperCase() + name.substring(1);
  Color get color {
    switch (this) {
      case _RuleSeverity.critical: return AppColors.error;
      case _RuleSeverity.high:     return AppColors.warning;
      case _RuleSeverity.medium:   return const Color(0xFF3B82F6);
      case _RuleSeverity.low:      return AppColors.mutedText;
    }
  }
}

enum _RuleAction { flag, reject, quarantine, enrich }

extension _RuleActionX on _RuleAction {
  String get label =>
      name[0].toUpperCase() + name.substring(1);
}

enum _ConditionOperator {
  isNotEmpty, isEmpty, equals, notEquals,
  contains, startsWith, matches, greaterThan, lessThan,
  ibanValid, postalFormatValid, postalCityMatch,
}

extension _ConditionOperatorX on _ConditionOperator {
  String get label {
    switch (this) {
      case _ConditionOperator.isNotEmpty:       return 'is not empty';
      case _ConditionOperator.isEmpty:          return 'is empty';
      case _ConditionOperator.equals:           return 'equals';
      case _ConditionOperator.notEquals:        return 'not equals';
      case _ConditionOperator.contains:         return 'contains';
      case _ConditionOperator.startsWith:       return 'starts with';
      case _ConditionOperator.matches:          return 'matches regex';
      case _ConditionOperator.greaterThan:      return '> greater than';
      case _ConditionOperator.lessThan:         return '< less than';
      case _ConditionOperator.ibanValid:        return 'IBAN valid (MOD-97)';
      case _ConditionOperator.postalFormatValid: return 'postal format valid';
      case _ConditionOperator.postalCityMatch:  return 'postal matches city';
    }
  }
  bool get needsValue =>
      this != _ConditionOperator.isNotEmpty &&
      this != _ConditionOperator.isEmpty &&
      this != _ConditionOperator.ibanValid;
}

class _Condition {
  String field;
  _ConditionOperator operator;
  String value;
  String? referenceField;
  _Condition({required this.field, required this.operator, this.value = '', this.referenceField});
  _Condition copy() => _Condition(field: field, operator: operator, value: value, referenceField: referenceField);
}

class _QualityRule {
  String id;
  String name;
  String entityType;
  String dimension;
  List<_Condition> conditions;
  String logicalOp; // AND / OR
  _RuleAction action;
  _RuleSeverity severity;
  bool isActive;
  int violations;

  _QualityRule({
    required this.id,
    required this.name,
    required this.entityType,
    required this.dimension,
    required this.conditions,
    this.logicalOp = 'AND',
    required this.action,
    required this.severity,
    this.isActive = true,
    this.violations = 0,
  });

  _QualityRule copy() => _QualityRule(
    id: id, name: name, entityType: entityType, dimension: dimension,
    conditions: conditions.map((c) => c.copy()).toList(),
    logicalOp: logicalOp, action: action, severity: severity,
    isActive: isActive, violations: violations,
  );
}

class _Violation {
  final String id;
  final String entityId;
  final String entityType;
  final String ruleName;
  final _RuleSeverity severity;
  final String field;
  final String message;
  final String when;
  bool resolved;
  _Violation({
    this.id = '',
    required this.entityId,
    required this.entityType,
    required this.ruleName,
    required this.severity,
    required this.field,
    required this.message,
    required this.when,
    this.resolved = false,
  });
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Visual builder domain models
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

enum _VisualBlockType { fieldCheck, formatCheck, rangeCheck, logicAnd, logicOr }

extension _VisualBlockTypeX on _VisualBlockType {
  String get label {
    switch (this) {
      case _VisualBlockType.fieldCheck:  return 'Field Check';
      case _VisualBlockType.formatCheck: return 'Format Check';
      case _VisualBlockType.rangeCheck:  return 'Range Check';
      case _VisualBlockType.logicAnd:    return 'AND';
      case _VisualBlockType.logicOr:     return 'OR';
    }
  }
  IconData get icon {
    switch (this) {
      case _VisualBlockType.fieldCheck:  return Icons.text_fields_rounded;
      case _VisualBlockType.formatCheck: return Icons.format_align_left_rounded;
      case _VisualBlockType.rangeCheck:  return Icons.tune_rounded;
      case _VisualBlockType.logicAnd:    return Icons.join_inner_rounded;
      case _VisualBlockType.logicOr:     return Icons.call_split_rounded;
    }
  }
  Color get color {
    switch (this) {
      case _VisualBlockType.fieldCheck:  return const Color(0xFF3B82F6);
      case _VisualBlockType.formatCheck: return const Color(0xFF8B5CF6);
      case _VisualBlockType.rangeCheck:  return const Color(0xFFFF6B35);
      case _VisualBlockType.logicAnd:    return const Color(0xFF00C896);
      case _VisualBlockType.logicOr:     return const Color(0xFFFFD700);
    }
  }
  bool get isLogic =>
      this == _VisualBlockType.logicAnd || this == _VisualBlockType.logicOr;
}

class _VisualBlock {
  final String id;
  final _VisualBlockType type;
  String field = '';
  String value = '';
  _VisualBlock({required this.id, required this.type});
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Page
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class DataQualityPage extends StatefulWidget {
  const DataQualityPage({super.key});

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _builderTab = 0; // 0=Visual, 1=Manual, 2=AI

  // Visual builder
  final List<_VisualBlock> _canvasBlocks = [];
  int _vbCounter = 0;

  // Rules
  final List<_QualityRule> _rules = [];

  // AI builder
  final _aiCtrl = TextEditingController();
  bool _aiGenerating = false;
  _QualityRule? _aiPreview;

  // Violations
  List<_Violation> _violations = [];

  // Quality dimensions â€” loaded from API, fall back to defaults
  List<(String, double, Color)> _dimensions = [
    ('Completeness', 0.82, const Color(0xFF00C896)),
    ('Accuracy',     0.77, const Color(0xFF3B82F6)),
    ('Consistency',  0.91, const Color(0xFF8B5CF6)),
    ('Uniqueness',   0.96, const Color(0xFFFF6B35)),
    ('Timeliness',   0.88, const Color(0xFFFFD700)),
    ('Validity',     0.74, const Color(0xFFFF4D6D)),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadLiveData();
  }

  Future<void> _loadLiveData() async {
    final client = GetIt.instance<ApiClient>();
    final tenantId = await AuthManager.getTenantId() ?? '';
    final opts = tenantId.isNotEmpty
        ? Options(headers: {AppConstants.tenantHeaderKey: tenantId})
        : null;
    // Load quality dimensions
    try {
      final dimResp = await client.get<Map<String, dynamic>>(
        AppConstants.qualityDimensionsPath,
        options: opts,
      );
      final dims = (dimResp.data?['dimensions'] as Map<String, dynamic>?) ?? {};
      if (dims.isNotEmpty && mounted) {
        setState(() {
          _dimensions = [
            ('Completeness', (dims['completeness'] as num?)?.toDouble() ?? 0.82, const Color(0xFF00C896)),
            ('Accuracy',     (dims['accuracy']     as num?)?.toDouble() ?? 0.77, const Color(0xFF3B82F6)),
            ('Consistency',  (dims['consistency']  as num?)?.toDouble() ?? 0.91, const Color(0xFF8B5CF6)),
            ('Uniqueness',   (dims['uniqueness']   as num?)?.toDouble() ?? 0.96, const Color(0xFFFF6B35)),
            ('Timeliness',   (dims['timeliness']   as num?)?.toDouble() ?? 0.88, const Color(0xFFFFD700)),
            ('Validity',     (dims['validity']     as num?)?.toDouble() ?? 0.74, const Color(0xFFFF4D6D)),
          ];
        });
      }
    } catch (_) {}

    // Load quality rules from API
    try {
      final rulesResp = await client.get<Map<String, dynamic>>(
        AppConstants.qualityRulesPath,
        options: opts,
      );
      final items = (rulesResp.data?['data'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _rules.clear();
          _rules.addAll(items.map((j) => _ruleFromJson(j as Map<String, dynamic>)));
        });
      }
    } catch (_) {}

    // Load quality violations from API (falls back to empty if endpoint not yet seeded)
    try {
      final vResp = await client.get<Map<String, dynamic>>(
        AppConstants.qualityViolationsPath,
        options: opts,
      );
      final vitems = (vResp.data?['data'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _violations = vitems
              .map((j) => _violationFromJson(j as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {}
  }

  static String _relativeTime(String? iso) {
    if (iso == null) return 'recently';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1)  return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours   < 24) return '${diff.inHours} hr ago';
      return '${diff.inDays}d ago';
    } catch (_) { return 'recently'; }
  }

  // â”€â”€ Condition â†” API string mapping â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static String _opToString(_ConditionOperator op) {
    switch (op) {
      case _ConditionOperator.isNotEmpty:        return 'is_not_empty';
      case _ConditionOperator.isEmpty:           return 'is_empty';
      case _ConditionOperator.equals:            return 'equals';
      case _ConditionOperator.notEquals:         return 'not_equals';
      case _ConditionOperator.contains:          return 'contains';
      case _ConditionOperator.startsWith:        return 'starts_with';
      case _ConditionOperator.matches:           return 'matches';
      case _ConditionOperator.greaterThan:       return 'greater_than';
      case _ConditionOperator.lessThan:          return 'less_than';
      case _ConditionOperator.ibanValid:         return 'iban_valid';
      case _ConditionOperator.postalFormatValid: return 'postal_format_valid';
      case _ConditionOperator.postalCityMatch:   return 'postal_city_match';
    }
  }

  static _ConditionOperator _opFromString(String s) {
    switch (s) {
      case 'is_empty':            return _ConditionOperator.isEmpty;
      case 'equals':              return _ConditionOperator.equals;
      case 'not_equals':          return _ConditionOperator.notEquals;
      case 'contains':            return _ConditionOperator.contains;
      case 'starts_with':         return _ConditionOperator.startsWith;
      case 'matches':             return _ConditionOperator.matches;
      case 'greater_than':        return _ConditionOperator.greaterThan;
      case 'less_than':           return _ConditionOperator.lessThan;
      case 'iban_valid':          return _ConditionOperator.ibanValid;
      case 'postal_format_valid': return _ConditionOperator.postalFormatValid;
      case 'postal_city_match':   return _ConditionOperator.postalCityMatch;
      default:                    return _ConditionOperator.isNotEmpty;
    }
  }

  static List<Map<String, dynamic>> _conditionsToJson(List<_Condition> conds) =>
      conds.map((c) => {
        'field':    c.field,
        'operator': _opToString(c.operator),
        if (c.value.isNotEmpty)          'value':           c.value,
        if (c.referenceField != null &&
            c.referenceField!.isNotEmpty) 'reference_field': c.referenceField,
      }).toList();

  static List<_Condition> _conditionsFromJson(dynamic json) {
    final list = json as List<dynamic>? ?? [];
    return list.map((c) {
      final m = c as Map<String, dynamic>;
      return _Condition(
        field:          (m['field']           as String?) ?? '',
        operator:       _opFromString((m['operator'] as String?) ?? 'is_not_empty'),
        value:          (m['value']           as String?) ?? '',
        referenceField: m['reference_field']  as String?,
      );
    }).toList();
  }

  static _QualityRule _ruleFromJson(Map<String, dynamic> m) {
    final action = switch ((m['action'] as String?) ?? 'flag') {
      'reject'     => _RuleAction.reject,
      'quarantine' => _RuleAction.quarantine,
      'enrich'     => _RuleAction.enrich,
      _            => _RuleAction.flag,
    };
    final severity = switch ((m['severity'] as String?) ?? 'medium') {
      'critical' => _RuleSeverity.critical,
      'high'     => _RuleSeverity.high,
      'low'      => _RuleSeverity.low,
      _          => _RuleSeverity.medium,
    };
    return _QualityRule(
      id:         (m['id']          as String?) ?? '',
      name:       (m['name']        as String?) ?? '',
      entityType: (m['entity_type'] as String?) ?? 'all',
      dimension:  (m['dimension']   as String?) ?? 'validity',
      conditions: _conditionsFromJson(m['conditions']),
      logicalOp:  (m['logical_op']  as String?) ?? 'AND',
      action:     action,
      severity:   severity,
      isActive:   (m['is_active']   as bool?)   ?? true,
    );
  }

  static _Violation _violationFromJson(Map<String, dynamic> m) {
    final sev = switch ((m['severity'] as String?) ?? 'medium') {
      'critical' => _RuleSeverity.critical,
      'high'     => _RuleSeverity.high,
      'low'      => _RuleSeverity.low,
      _          => _RuleSeverity.medium,
    };
    final snap = m['rule_snapshot'];
    final ruleName = (snap is Map<String, dynamic>)
        ? (snap['name'] as String?) ?? 'Rule'
        : 'Rule';
    final fields = m['violated_fields'] as List<dynamic>? ?? [];
    String fieldStr = 'multiple';
    if (fields.isNotEmpty) {
      final first = fields.first as Map<String, dynamic>?;
      fieldStr = (first?['field'] as String?) ?? 'multiple';
    }
    return _Violation(
      id:         (m['id']          as String?) ?? '',
      entityId:   (m['entity_id']   as String?) ?? 'â€”',
      entityType: (m['entity_type'] as String?) ?? 'All',
      ruleName:   ruleName,
      severity:   sev,
      field:      fieldStr,
      message:    (m['action_taken'] as String?) ?? '',
      when:       _relativeTime(m['detected_at'] as String?),
      resolved:   (m['is_resolved']  as bool?)   ?? false,
    );
  }

  // â”€â”€ API actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Options?> _authOpts() async {
    final tenantId = await AuthManager.getTenantId() ?? '';
    return tenantId.isNotEmpty
        ? Options(headers: {AppConstants.tenantHeaderKey: tenantId})
        : null;
  }

  Future<void> _createRuleApi(_QualityRule rule) async {
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      final resp   = await client.post<Map<String, dynamic>>(
        AppConstants.qualityRulesPath,
        data: {
          'name':        rule.name,
          'entity_type': rule.entityType.toLowerCase(),
          'dimension':   rule.dimension.toLowerCase(),
          'conditions':  _conditionsToJson(rule.conditions),
          'logical_op':  rule.logicalOp,
          'action':      rule.action.name,
          'severity':    rule.severity.name,
          'priority':    rule.violations, // reuse field as priority placeholder
        },
        options: opts,
      );
      final created = resp.data?['data'] as Map<String, dynamic>?;
      if (created != null && mounted) {
        final serverRule = _ruleFromJson(created);
        setState(() {
          final idx = _rules.indexWhere((r) => r.id == rule.id);
          if (idx >= 0) _rules[idx] = serverRule;
        });
      }
    } catch (_) {}
  }

  Future<void> _updateRuleApi(_QualityRule rule) async {
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      await client.patch<void>(
        '${AppConstants.qualityRulesPath}/${rule.id}',
        data: {
          'name':        rule.name,
          'entity_type': rule.entityType.toLowerCase(),
          'dimension':   rule.dimension.toLowerCase(),
          'conditions':  _conditionsToJson(rule.conditions),
          'logical_op':  rule.logicalOp,
          'action':      rule.action.name,
          'severity':    rule.severity.name,
          'is_active':   rule.isActive,
        },
        options: opts,
      );
    } catch (_) {}
  }

  Future<void> _toggleRuleActive(_QualityRule rule, bool active) async {
    if (!mounted) return;
    setState(() => rule.isActive = active);
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      await client.patch<void>(
        '${AppConstants.qualityRulesPath}/${rule.id}',
        data: {'is_active': active},
        options: opts,
      );
    } catch (_) {
      // revert optimistic update on failure
      if (mounted) setState(() => rule.isActive = !active);
    }
  }

  Future<void> _deleteRuleConfirmed(_QualityRule rule) async {
    if (!mounted) return;
    setState(() => _rules.removeWhere((r) => r.id == rule.id));
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      await client.delete<void>(
        '${AppConstants.qualityRulesPath}/${rule.id}',
        options: opts,
      );
    } catch (_) {
      // revert on failure
      if (mounted) setState(() => _rules.add(rule));
    }
  }

  Future<void> _resolveViolationApi(_Violation v) async {
    if (!mounted) return;
    setState(() => v.resolved = true);
    if (v.id.isEmpty) return;
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      await client.patch<void>(
        '${AppConstants.qualityViolationsPath}/${v.id}/resolve',
        options: opts,
      );
    } catch (_) {
      if (mounted) setState(() => v.resolved = false);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _aiCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Scores â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double get _overallScore =>
      _dimensions.fold(0.0, (s, d) => s + d.$2) / _dimensions.length;

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return LicenseGuard(
      module: LicensedModule.dataQuality,
      child: _buildMain(),
    );
  }

  // â”€â”€ Main dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildMain() {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildPageHeader(),
          Expanded(
            child: Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildOverviewTab(),
                      _buildRuleBuilderTab(),
                      _buildViolationsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    final activeRules = _rules.where((r) => r.isActive).length;
    final openViolations = _violations.where((v) => !v.resolved).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.auroraGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.health_and_safety_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data Quality Engine', style: AppTextStyles.titleMedium),
              Text(
                '$activeRules active rules  Â·  $openViolations open violations  Â·  '
                'Overall ${(_overallScore * 100).round()}%',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _runAllRules,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Run All Rules'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.cardSurface,
      child: TabBar(
        controller: _tab,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          const Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.dashboard_outlined, size: 16),
              SizedBox(width: 6),
              Text('Overview'),
            ]),
          ),
          const Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.rule_outlined, size: 16),
              SizedBox(width: 6),
              Text('Rule Builder'),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.report_problem_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                'Violations (${_violations.where((v) => !v.resolved).length})',
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Overview tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overall score gauge
              _buildOverallGauge(),
              const SizedBox(width: 20),
              // Dimension scores grid
              Expanded(child: _buildDimensionGrid()),
            ],
          ),
          const SizedBox(height: 24),
          _buildRuleSummaryCards(),
        ],
      ),
    );
  }

  Widget _buildOverallGauge() {
    final score = _overallScore;
    final color = score >= 0.9
        ? const Color(0xFF00C896)
        : score >= 0.75
            ? AppColors.warning
            : AppColors.error;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Text('Overall Score', style: AppTextStyles.titleSmall),
          const SizedBox(height: 16),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _GaugePainter(score, color),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(score * 100).round()}%',
                      style: AppTextStyles.statValue.copyWith(color: color),
                    ),
                    Text(
                      score >= 0.9
                          ? 'Excellent'
                          : score >= 0.75
                              ? 'Good'
                              : 'Needs Work',
                      style: AppTextStyles.labelSmall.copyWith(color: color),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_rules.where((r) => r.isActive).length} active rules across '
            '${_violations.where((v) => !v.resolved).length} violations',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: AppAnimations.slow)
        .scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1, 1),
            curve: AppAnimations.spring);
  }

  Widget _buildDimensionGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _dimensions.asMap().entries.map((e) {
        final i = e.key;
        final d = e.value;
        return SizedBox(
          width: 150,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.$3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(d.$1,
                      style: AppTextStyles.labelSmall
                          .copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Text(
                  '${(d.$2 * 100).round()}%',
                  style: AppTextStyles.statValue
                      .copyWith(fontSize: 22, color: d.$3),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: d.$2,
                    backgroundColor: d.$3.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(d.$3),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ).animate(delay: AppAnimations.stagger(i)).fadeIn().slideY(begin: 0.05, end: 0),
        );
      }).toList(),
    );
  }

  Widget _buildRuleSummaryCards() {
    final criticalViolations = _violations
        .where((v) => !v.resolved && v.severity == _RuleSeverity.critical)
        .length;
    final topRule = _rules
        .where((r) => r.isActive)
        .fold<_QualityRule?>(
            null,
            (prev, curr) =>
                prev == null || curr.violations > prev.violations ? curr : prev);

    return Row(
      children: [
        _summaryCard(
          'Critical Violations',
          '$criticalViolations',
          Icons.error_outline_rounded,
          AppColors.error,
          'Require immediate attention',
        ),
        const SizedBox(width: 12),
        _summaryCard(
          'Most Triggered Rule',
          topRule?.name ?? 'â€”',
          Icons.warning_amber_rounded,
          AppColors.warning,
          topRule != null ? '${topRule.violations} violations' : '',
        ),
        const SizedBox(width: 12),
        _summaryCard(
          'Total Active Rules',
          '${_rules.where((r) => r.isActive).length}',
          Icons.rule_rounded,
          AppColors.primary,
          '${_rules.where((r) => !r.isActive).length} paused',
        ),
        const SizedBox(width: 12),
        _summaryCard(
          'Auto-Resolved Today',
          '34',
          Icons.check_circle_outline_rounded,
          const Color(0xFF00C896),
          'Via enrichment rules',
        ),
      ],
    );
  }

  Widget _summaryCard(
      String title, String value, IconData icon, Color color, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: AppTextStyles.labelMedium
                          .copyWith(fontWeight: FontWeight.w700, color: color),
                      overflow: TextOverflow.ellipsis),
                  Text(title, style: AppTextStyles.labelSmall, overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.mutedText),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Rule builder tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildRuleBuilderTab() {
    return Column(
      children: [
        // Sub-tab toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: AppColors.navyBackground,
          child: Row(
            children: [
              _subTabBtn(0, Icons.account_tree_outlined, 'Visual Builder'),
              const SizedBox(width: 8),
              _subTabBtn(1, Icons.drag_indicator_rounded, 'Manual Builder'),
              const SizedBox(width: 8),
              _subTabBtn(2, Icons.auto_awesome_rounded, 'AI Generator'),
              const Spacer(),
              if (_builderTab == 1)
                ElevatedButton.icon(
                  onPressed: _showNewRuleDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New Rule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              if (_builderTab == 0 && _canvasBlocks.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => setState(() => _canvasBlocks.clear()),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondaryText,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _buildRuleFromCanvas,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Save Rule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _builderTab == 0
              ? _buildVisualBuilder()
              : _builderTab == 1
                  ? _buildManualBuilder()
                  : _buildAiBuilder(),
        ),
      ],
    );
  }

  Widget _subTabBtn(int idx, IconData icon, String label) {
    final selected = _builderTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _builderTab = idx),
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: selected ? AppColors.primary : AppColors.secondaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: selected ? AppColors.primary : AppColors.secondaryText,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),
    );
  }

  // â”€â”€ Visual drag-and-drop builder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildVisualBuilder() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Palette panel
        Container(
          width: 200,
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            border: Border(right: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Block Palette',
                    style: AppTextStyles.labelMedium
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Drag to canvas â†’',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.mutedText)),
              ),
              const Divider(color: AppColors.divider, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children:
                      _VisualBlockType.values.map(_buildPaletteBlock).toList(),
                ),
              ),
            ],
          ),
        ),
        // Canvas panel
        Expanded(
          child: DragTarget<_VisualBlockType>(
            onAcceptWithDetails: (details) {
              setState(() {
                _canvasBlocks.add(_VisualBlock(
                  id: 'vb_${_vbCounter++}',
                  type: details.data,
                ));
              });
            },
            builder: (ctx, candidateData, _) {
              final hovering = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: AppAnimations.fast,
                decoration: BoxDecoration(
                  color: hovering
                      ? AppColors.primary.withValues(alpha: 0.04)
                      : AppColors.navyBackground,
                ),
                child: _canvasBlocks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.account_tree_outlined,
                              size: 56,
                              color: hovering
                                  ? AppColors.primary
                                  : AppColors.mutedText,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              hovering
                                  ? 'Release to drop'
                                  : 'Drag blocks from the palette',
                              style: AppTextStyles.titleSmall.copyWith(
                                color: hovering
                                    ? AppColors.primary
                                    : AppColors.mutedText,
                              ),
                            ),
                            if (!hovering) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Combine Field Check, Format Check, Range Check\n'
                                'and AND / OR logic blocks to build a quality rule',
                                style: AppTextStyles.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._canvasBlocks.asMap().entries.map((e) =>
                                _CanvasBlockTile(
                                  key: ValueKey(e.value.id),
                                  block: e.value,
                                  index: e.key,
                                  onDelete: () => setState(
                                      () => _canvasBlocks.removeAt(e.key)),
                                )),
                            // Drop zone at bottom of existing blocks
                            DragTarget<_VisualBlockType>(
                              onAcceptWithDetails: (details) {
                                setState(() {
                                  _canvasBlocks.add(_VisualBlock(
                                    id: 'vb_${_vbCounter++}',
                                    type: details.data,
                                  ));
                                });
                              },
                              builder: (ctx2, cd, _) => AnimatedContainer(
                                duration: AppAnimations.fast,
                                height: 48,
                                margin: const EdgeInsets.only(top: 8),
                                decoration: BoxDecoration(
                                  color: cd.isNotEmpty
                                      ? AppColors.primary.withValues(alpha: 0.08)
                                      : AppColors.elevatedCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: cd.isNotEmpty
                                        ? AppColors.primary
                                        : AppColors.divider,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    cd.isNotEmpty
                                        ? 'Release to drop'
                                        : '+ Drop another block here',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: cd.isNotEmpty
                                          ? AppColors.primary
                                          : AppColors.mutedText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaletteBlock(_VisualBlockType type) {
    final widget = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: type.color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(type.icon, size: 15, color: type.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(type.label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: type.color, fontWeight: FontWeight.w600)),
        ),
        Icon(Icons.drag_handle_rounded,
            size: 13, color: type.color.withValues(alpha: 0.5)),
      ]),
    );

    return Draggable<_VisualBlockType>(
      data: type,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 176,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: type.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: type.color.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                  color: type.color.withValues(alpha: 0.3), blurRadius: 10),
            ],
          ),
          child: Row(children: [
            Icon(type.icon, size: 15, color: type.color),
            const SizedBox(width: 8),
            Text(type.label,
                style: AppTextStyles.labelSmall.copyWith(
                    color: type.color, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: widget),
      child: widget,
    );
  }

  void _buildRuleFromCanvas() {
    final conditions = _canvasBlocks
        .where((b) => !b.type.isLogic && b.field.trim().isNotEmpty)
        .map((b) {
          _ConditionOperator op;
          if (b.type == _VisualBlockType.formatCheck) {
            op = _ConditionOperator.matches;
          } else if (b.type == _VisualBlockType.rangeCheck) {
            op = _ConditionOperator.greaterThan;
          } else {
            op = _ConditionOperator.isNotEmpty;
          }
          return _Condition(
              field: b.field.trim(), operator: op, value: b.value.trim());
        })
        .toList();

    if (conditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Add at least one Field / Format / Range block with a field name'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final hasOr = _canvasBlocks.any((b) => b.type == _VisualBlockType.logicOr);
    final rule = _QualityRule(
      id: 'vis_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Visual Rule ${_rules.length + 1}',
      entityType: 'All',
      dimension: 'Validity',
      conditions: conditions,
      logicalOp: hasOr ? 'OR' : 'AND',
      action: _RuleAction.flag,
      severity: _RuleSeverity.medium,
    );

    setState(() {
      _rules.insert(0, rule);
      _canvasBlocks.clear();
      _builderTab = 1; // jump to Manual Builder to show the new rule
    });
    _createRuleApi(rule);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Text('Rule created â€” edit it in Manual Builder to refine.',
              style: AppTextStyles.bodyMedium),
        ]),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // â”€â”€ Manual drag-and-drop builder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildManualBuilder() {
    return _rules.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.rule_folder_outlined,
                    size: 48, color: AppColors.mutedText),
                const SizedBox(height: 12),
                Text('No rules yet', style: AppTextStyles.titleSmall),
                const SizedBox(height: 6),
                Text('Click "New Rule" to create your first quality rule',
                    style: AppTextStyles.bodySmall),
              ],
            ),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: _rules.length,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx--;
                final rule = _rules.removeAt(oldIdx);
                _rules.insert(newIdx, rule);
              });
            },
            itemBuilder: (ctx, i) {
              final rule = _rules[i];
              return _buildRuleCard(rule, i);
            },
          );
  }

  Widget _buildRuleCard(_QualityRule rule, int index) {
    return Container(
      key: ValueKey(rule.id),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rule.isActive
              ? rule.severity.color.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 10),
            child: Row(
              children: [
                // Drag handle (ReorderableListView injects its own)
                const Icon(Icons.drag_indicator_rounded,
                    size: 18, color: AppColors.mutedText),
                const SizedBox(width: 6),
                // Severity dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rule.isActive
                        ? rule.severity.color
                        : AppColors.mutedText,
                  ),
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(rule.name,
                      style: AppTextStyles.labelMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                // Entity type chip
                _chip(rule.entityType, AppColors.primary),
                const SizedBox(width: 6),
                // Dimension chip
                _chip(rule.dimension, const Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                // Action chip
                _chip(rule.action.label, const Color(0xFF3B82F6)),
                const SizedBox(width: 10),
                // Violations badge
                if (rule.violations > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: rule.severity.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${rule.violations} violations',
                        style: AppTextStyles.badgeLabel
                            .copyWith(color: rule.severity.color)),
                  ),
                const SizedBox(width: 10),
                // Toggle
                Switch(
                  value: rule.isActive,
                  onChanged: (v) => _toggleRuleActive(rule, v),
                  activeThumbColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _showEditRuleDialog(rule),
                  color: AppColors.secondaryText,
                  tooltip: 'Edit rule',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  onPressed: () => _deleteRuleConfirmed(rule),
                  color: AppColors.error,
                  tooltip: 'Delete rule',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          // Conditions preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(36, 0, 12, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: rule.conditions.asMap().entries.map((e) {
                final i = e.key;
                final c = e.value;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(rule.logicalOp,
                          style: AppTextStyles.badgeLabel
                              .copyWith(color: AppColors.aiPurple)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.elevatedCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '${c.field} ${c.operator.label}'
                      '${c.operator.needsValue ? ' "${c.value}"' : ''}',
                      style: AppTextStyles.labelSmall
                          .copyWith(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label,
          style: AppTextStyles.badgeLabel.copyWith(color: color, fontSize: 10)),
    );
  }

  // â”€â”€ AI rule builder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildAiBuilder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.auroraPurple.withValues(alpha: 0.08),
                  AppColors.auroraBlue.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.auroraPurple.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  ShaderMask(
                    shaderCallback: (b) => AppColors.auroraGradient.createShader(b),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text('AI Rule Generator',
                      style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.auroraPurple)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Describe a data quality rule in plain language. '
                  'The AI will convert it into structured conditions automatically.',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _aiCtrl,
                  maxLines: 3,
                  style: AppTextStyles.inputText,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. "Customer email must be in valid format and not empty"\n'
                        '"Vendor tax ID must start with DE or US followed by 9 digits"',
                    hintStyle: AppTextStyles.inputHint,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.auroraPurple, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 8, children: [
                      _aiSuggestion(
                          '"Customer email must not be empty and must be valid"'),
                      _aiSuggestion('"Vendor must have tax number or VAT registration"'),
                      _aiSuggestion('"Material code must match MAT-XXXXXX pattern"'),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _aiGenerating ? null : _generateAiRule,
                    icon: _aiGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 16),
                    label:
                        Text(_aiGenerating ? 'Generatingâ€¦' : 'Generate Rule'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.auroraPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          if (_aiPreview != null) ...[
            const SizedBox(height: 20),
            _buildAiPreview(_aiPreview!),
          ],
        ],
      ),
    );
  }

  Widget _aiSuggestion(String text) {
    return GestureDetector(
      onTap: () => setState(() => _aiCtrl.text = text.replaceAll('"', '')),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(text,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.secondaryText)),
      ),
    );
  }

  Widget _buildAiPreview(_QualityRule rule) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('AI-Generated Rule Preview',
                style: AppTextStyles.titleSmall
                    .copyWith(color: AppColors.primary)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _aiPreview = null),
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _rules.insert(0, _aiPreview!);
                  _aiPreview = null;
                  _aiCtrl.clear();
                  _builderTab = 1; // show Manual Builder with new rule
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add to Rules'),
            ),
          ]),
          const SizedBox(height: 14),
          _buildRuleCard(rule, 0),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: AppAnimations.normal)
        .slideY(begin: 0.06, end: 0, curve: AppAnimations.spring);
  }

  Future<void> _generateAiRule() async {
    final prompt = _aiCtrl.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _aiGenerating = true;
      _aiPreview = null;
    });
    // Parse structure locally â€” always succeeds
    final generated = _parseAiRule(prompt);
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        '/v1/prism',
        data: {
          'message': 'Generate a concise data quality rule name (max 5 words) '
              'for this requirement: "$prompt". '
              'Reply with ONLY the rule name, nothing else.',
        },
      );
      if (!mounted) return;
      final aiName = (resp.data?['answer'] as String? ?? '').trim();
      final rule = aiName.isNotEmpty && aiName.length <= 60
          ? _QualityRule(
              id: generated.id,
              name: aiName,
              entityType: generated.entityType,
              dimension: generated.dimension,
              conditions: generated.conditions,
              logicalOp: generated.logicalOp,
              action: generated.action,
              severity: generated.severity,
              isActive: generated.isActive,
              violations: generated.violations,
            )
          : generated;
      setState(() {
        _aiGenerating = false;
        _aiPreview = rule;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiGenerating = false;
        _aiPreview = generated;
      });
    }
  }

  _QualityRule _parseAiRule(String prompt) {
    final lp = prompt.toLowerCase();
    String entityType = 'All';
    if (lp.contains('customer')) entityType = 'Customer';
    if (lp.contains('vendor'))   entityType = 'Vendor';
    if (lp.contains('material')) entityType = 'Material';

    String dimension = 'Validity';
    if (lp.contains('empty') || lp.contains('missing') || lp.contains('required')) {
      dimension = 'Completeness';
    }
    if (lp.contains('unique') || lp.contains('duplicat')) dimension = 'Uniqueness';
    if (lp.contains('format') || lp.contains('pattern') || lp.contains('match')) {
      dimension = 'Validity';
    }

    final conditions = <_Condition>[];

    if (lp.contains('email')) {
      if (lp.contains('not empty') || lp.contains('required') || lp.contains('must have')) {
        conditions.add(_Condition(field: 'email', operator: _ConditionOperator.isNotEmpty));
      }
      if (lp.contains('valid') || lp.contains('format')) {
        conditions.add(_Condition(
          field: 'email',
          operator: _ConditionOperator.matches,
          value: r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$',
        ));
      }
    }
    if (lp.contains('tax') || lp.contains('tax_number') || lp.contains('tax id')) {
      conditions.add(_Condition(field: 'tax_number', operator: _ConditionOperator.isNotEmpty));
    }
    if (lp.contains('mat') && lp.contains('pattern')) {
      conditions.add(_Condition(
        field: 'material_number',
        operator: _ConditionOperator.matches,
        value: r'^MAT-\d{6}$',
      ));
    }
    if (conditions.isEmpty) {
      final words = prompt.split(' ');
      final fieldWord = words.firstWhere(
          (w) => w.length > 3 && !['must', 'should', 'have', 'not', 'empty', 'valid'].contains(w.toLowerCase()),
          orElse: () => 'field');
      conditions.add(_Condition(
        field: fieldWord.toLowerCase().replaceAll(RegExp(r'[^\w]'), '_'),
        operator: _ConditionOperator.isNotEmpty,
      ));
    }

    final id = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final name = prompt.length > 48 ? '${prompt.substring(0, 45)}â€¦' : prompt;

    return _QualityRule(
      id: id,
      name: name[0].toUpperCase() + name.substring(1),
      entityType: entityType,
      dimension: dimension,
      conditions: conditions,
      logicalOp: 'AND',
      action: _RuleAction.flag,
      severity: _RuleSeverity.medium,
      violations: 0,
    );
  }

  // â”€â”€ Violations tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildViolationsTab() {
    final open = _violations.where((v) => !v.resolved).toList();
    final resolved = _violations.where((v) => v.resolved).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (open.isNotEmpty) ...[
            _violationsHeader('Open Violations', open.length, AppColors.error),
            const SizedBox(height: 10),
            ...open.asMap().entries.map((e) => _buildViolationRow(e.value, e.key)),
            const SizedBox(height: 24),
          ],
          if (resolved.isNotEmpty) ...[
            _violationsHeader('Resolved', resolved.length, AppColors.primary),
            const SizedBox(height: 10),
            ...resolved.asMap().entries.map((e) =>
                _buildViolationRow(e.value, e.key, resolved: true)),
          ],
        ],
      ),
    );
  }

  Widget _violationsHeader(String title, int count, Color color) {
    return Row(children: [
      Text(title, style: AppTextStyles.titleSmall),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$count',
            style: AppTextStyles.badgeLabel.copyWith(color: color)),
      ),
    ]);
  }

  Widget _buildViolationRow(_Violation v, int index, {bool resolved = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: resolved
            ? AppColors.elevatedCard
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: resolved
              ? AppColors.divider
              : v.severity.color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: v.severity.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              resolved ? Icons.check_rounded : Icons.report_problem_rounded,
              color: resolved ? AppColors.primary : v.severity.color,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(v.entityId,
                      style: AppTextStyles.labelMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  _chip(v.entityType, AppColors.primary),
                  const SizedBox(width: 6),
                  _chip(v.severity.label, v.severity.color),
                ]),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(
                    style: AppTextStyles.bodySmall,
                    children: [
                      TextSpan(
                          text: '${v.ruleName}  ',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondaryText)),
                      const TextSpan(text: 'Â·  field: '),
                      TextSpan(
                          text: v.field,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: AppColors.aiPurple)),
                      TextSpan(text: '  â€”  ${v.message}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(v.when,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.mutedText)),
          const SizedBox(width: 10),
          if (!resolved)
            OutlinedButton(
              onPressed: () => _resolveViolationApi(v),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: AppTextStyles.buttonSmall,
              ),
              child: const Text('Resolve'),
            ),
        ],
      ),
    ).animate(delay: AppAnimations.stagger(index)).fadeIn().slideX(begin: 0.02, end: 0);
  }

  // â”€â”€ Dialogs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showNewRuleDialog() => _showRuleDialog(null);

  void _showEditRuleDialog(_QualityRule rule) => _showRuleDialog(rule.copy());

  void _showRuleDialog(_QualityRule? existing) {
    final isEdit = existing != null;
    final rule = existing ??
        _QualityRule(
          id: 'r${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          entityType: 'All',
          dimension: 'Completeness',
          conditions: [_Condition(field: '', operator: _ConditionOperator.isNotEmpty)],
          action: _RuleAction.flag,
          severity: _RuleSeverity.medium,
        );

    showAzileDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDs) => AzileDialog(
          title: isEdit ? 'Edit Rule' : 'New Quality Rule',
          titleIcon: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.rule_outlined, size: 15, color: AppColors.primary),
          ),
          content: _RuleEditor(rule: rule, onChanged: setDs),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (rule.name.isEmpty || rule.conditions.isEmpty) return;
                Navigator.pop(ctx);
                setState(() {
                  if (isEdit) {
                    final idx = _rules.indexWhere((r) => r.id == rule.id);
                    if (idx >= 0) _rules[idx] = rule;
                  } else {
                    _rules.insert(0, rule);
                  }
                });
                if (isEdit) {
                  _updateRuleApi(rule);
                } else {
                  _createRuleApi(rule);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Save Changes' : 'Create Rule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAllRules() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Text(
              'Running ${_rules.where((r) => r.isActive).length} rules against all entitiesâ€¦',
              style: AppTextStyles.bodyMedium),
        ]),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    try {
      final client = GetIt.instance<ApiClient>();
      final opts   = await _authOpts();
      await client.post<void>(
        '${AppConstants.qualityRulesPath}/run',
        options: opts,
      );
    } catch (_) {}
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Rule editor widget (used inside dialog)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _RuleEditor extends StatefulWidget {
  final _QualityRule rule;
  final StateSetter onChanged;
  const _RuleEditor({required this.rule, required this.onChanged});

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late TextEditingController _nameCtrl;
  static const _entityTypes = ['All', 'Customer', 'Vendor', 'Material', 'Product', 'Employee', 'Location'];
  static const _dimensions  = ['Completeness', 'Accuracy', 'Consistency', 'Uniqueness', 'Timeliness', 'Validity'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.rule.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.inputHint,
    filled: true,
    fillColor: AppColors.inputFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
  );

  Widget _inlineDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.elevatedCard,
          style: AppTextStyles.inputText.copyWith(fontSize: 13),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 14, color: AppColors.secondaryText),
          items: items
              .map((i) => DropdownMenuItem<T>(
                    value: i,
                    child: Text(labelOf(i),
                        style: AppTextStyles.inputText.copyWith(fontSize: 13)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;

    return SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          Text('Rule Name', style: AppTextStyles.labelMedium),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            onChanged: (v) { r.name = v; widget.onChanged(() {}); },
            decoration: _deco('e.g. Customer Email Required'),
            style: AppTextStyles.inputText,
          ),
          const SizedBox(height: 14),
          // Entity type + Dimension row
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Entity Type', style: AppTextStyles.labelMedium),
                const SizedBox(height: 6),
                _inlineDropdown<String>(
                  value: r.entityType,
                  items: _entityTypes,
                  labelOf: (v) => v,
                  onChanged: (v) { if (v != null) setState(() => r.entityType = v); },
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dimension', style: AppTextStyles.labelMedium),
                const SizedBox(height: 6),
                _inlineDropdown<String>(
                  value: r.dimension,
                  items: _dimensions,
                  labelOf: (v) => v,
                  onChanged: (v) { if (v != null) setState(() => r.dimension = v); },
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          // Action + Severity row
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Action', style: AppTextStyles.labelMedium),
                const SizedBox(height: 6),
                _inlineDropdown<_RuleAction>(
                  value: r.action,
                  items: _RuleAction.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) { if (v != null) setState(() => r.action = v); },
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Severity', style: AppTextStyles.labelMedium),
                const SizedBox(height: 6),
                _inlineDropdown<_RuleSeverity>(
                  value: r.severity,
                  items: _RuleSeverity.values,
                  labelOf: (v) => v.label,
                  onChanged: (v) { if (v != null) setState(() => r.severity = v); },
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          // Conditions
          Row(children: [
            Text('Conditions', style: AppTextStyles.labelMedium),
            const SizedBox(width: 12),
            _inlineDropdown<String>(
              value: r.logicalOp,
              items: const ['AND', 'OR'],
              labelOf: (v) => v,
              onChanged: (v) { if (v != null) setState(() => r.logicalOp = v); },
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => r.conditions.add(
                  _Condition(field: '', operator: _ConditionOperator.isNotEmpty))),
              icon: const Icon(Icons.add_rounded, size: 14, color: AppColors.primary),
              label: Text('Add condition',
                  style: AppTextStyles.buttonSmall.copyWith(color: AppColors.primary)),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ]),
          const SizedBox(height: 8),
          // Condition list (drag-reorderable)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oi, ni) {
              setState(() {
                if (ni > oi) ni--;
                final c = r.conditions.removeAt(oi);
                r.conditions.insert(ni, c);
              });
            },
            children: r.conditions.asMap().entries.map((e) {
              final ci = e.key;
              final cond = e.value;
              return _buildConditionRow(cond, ci, r);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionRow(_Condition cond, int ci, _QualityRule r) {
    return Container(
      key: ValueKey('cond_$ci'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        const Icon(Icons.drag_indicator_rounded,
            size: 16, color: AppColors.mutedText),
        const SizedBox(width: 6),
        // Field
        SizedBox(
          width: 110,
          child: TextField(
            controller: TextEditingController(text: cond.field)
              ..selection = TextSelection.collapsed(offset: cond.field.length),
            onChanged: (v) => setState(() => cond.field = v),
            decoration: _deco('field_name'),
            style: AppTextStyles.inputText
                .copyWith(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 8),
        // Operator
        _inlineDropdown<_ConditionOperator>(
          value: cond.operator,
          items: _ConditionOperator.values,
          labelOf: (v) => v.label,
          onChanged: (v) { if (v != null) setState(() => cond.operator = v); },
        ),
        const SizedBox(width: 8),
        // Value (conditional)
        if (cond.operator.needsValue)
          Expanded(
            child: TextField(
              controller: TextEditingController(text: cond.value)
                ..selection = TextSelection.collapsed(offset: cond.value.length),
              onChanged: (v) => setState(() => cond.value = v),
              decoration: _deco(cond.operator == _ConditionOperator.postalFormatValid
                  ? 'country code (GB, USâ€¦)'
                  : 'value or regexâ€¦'),
              style: AppTextStyles.inputText
                  .copyWith(fontSize: 12, fontFamily: 'monospace'),
            ),
          )
        else
          const Spacer(),
        // Reference field (postal_city_match only)
        if (cond.operator == _ConditionOperator.postalCityMatch) ...[
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: cond.referenceField ?? '')
                ..selection = TextSelection.collapsed(offset: (cond.referenceField ?? '').length),
              onChanged: (v) => setState(() => cond.referenceField = v),
              decoration: _deco('city field name'),
              style: AppTextStyles.inputText
                  .copyWith(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
        const SizedBox(width: 6),
        // Remove
        if (r.conditions.length > 1)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 14),
            onPressed: () => setState(() => r.conditions.removeAt(ci)),
            color: AppColors.error,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
      ]),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Canvas block tile (visual builder â€” manages its own TextEditingControllers)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CanvasBlockTile extends StatefulWidget {
  final _VisualBlock block;
  final int index;
  final VoidCallback onDelete;
  const _CanvasBlockTile({
    required super.key,
    required this.block,
    required this.index,
    required this.onDelete,
  });

  @override
  State<_CanvasBlockTile> createState() => _CanvasBlockTileState();
}

class _CanvasBlockTileState extends State<_CanvasBlockTile> {
  late final TextEditingController _fieldCtrl;
  late final TextEditingController _valueCtrl;

  @override
  void initState() {
    super.initState();
    _fieldCtrl = TextEditingController(text: widget.block.field);
    _valueCtrl = TextEditingController(text: widget.block.value);
  }

  @override
  void dispose() {
    _fieldCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.inputHint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final type = block.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: type.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            Icon(type.icon, size: 15, color: type.color),
            const SizedBox(width: 8),
            Text(type.label,
                style: AppTextStyles.labelMedium.copyWith(
                    color: type.color, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 14),
              onPressed: widget.onDelete,
              color: AppColors.mutedText,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Remove block',
            ),
          ]),
          // Logic blocks have no fields â€” just a label
          if (!type.isLogic) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _fieldCtrl,
                  onChanged: (v) => block.field = v,
                  style: AppTextStyles.inputText
                      .copyWith(fontSize: 12, fontFamily: 'monospace'),
                  decoration: _deco('field name  (e.g. email)'),
                ),
              ),
              if (type == _VisualBlockType.formatCheck ||
                  type == _VisualBlockType.rangeCheck) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: type == _VisualBlockType.formatCheck ? 180 : 110,
                  child: TextField(
                    controller: _valueCtrl,
                    onChanged: (v) => block.value = v,
                    style: AppTextStyles.inputText.copyWith(
                        fontSize: 12,
                        fontFamily: type == _VisualBlockType.formatCheck
                            ? 'monospace'
                            : null),
                    decoration: _deco(
                      type == _VisualBlockType.formatCheck
                          ? 'regex  (e.g. ^[A-Z]{2}\$)'
                          : 'threshold value',
                    ),
                  ),
                ),
              ],
            ]),
          ],
        ],
      ),
    )
        .animate(delay: AppAnimations.stagger(widget.index))
        .fadeIn()
        .slideY(begin: 0.05, end: 0);
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Gauge painter
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  _GaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 8;
    const startAngle = math.pi * 0.75;
    const sweepMax   = math.pi * 1.5;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepMax, false,
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // Value arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepMax * value, false,
      Paint()
        ..color = color
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}
