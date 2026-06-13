import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/nexus_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// License manager (session-scoped; swap for SharedPreferences in prod)
// ─────────────────────────────────────────────────────────────────────────────

class _DqLicense {
  static const _validKeys = {
    'NXS-DQ-ENTERPRISE-2026',
    'NXS-DQ-PRO-2026',
    'NXS-DATA-QUALITY-PREMIUM',
  };

  static String? _key;
  static bool get isValid => _key != null && _validKeys.contains(_key);
  static void activate(String key) => _key = key.trim().toUpperCase();
  static void revoke() => _key = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain models
// ─────────────────────────────────────────────────────────────────────────────

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
}

extension _ConditionOperatorX on _ConditionOperator {
  String get label {
    switch (this) {
      case _ConditionOperator.isNotEmpty:   return 'is not empty';
      case _ConditionOperator.isEmpty:      return 'is empty';
      case _ConditionOperator.equals:       return 'equals';
      case _ConditionOperator.notEquals:    return 'not equals';
      case _ConditionOperator.contains:     return 'contains';
      case _ConditionOperator.startsWith:   return 'starts with';
      case _ConditionOperator.matches:      return 'matches regex';
      case _ConditionOperator.greaterThan:  return '> greater than';
      case _ConditionOperator.lessThan:     return '< less than';
    }
  }
  bool get needsValue => this != _ConditionOperator.isNotEmpty &&
      this != _ConditionOperator.isEmpty;
}

class _Condition {
  String field;
  _ConditionOperator operator;
  String value;
  _Condition({required this.field, required this.operator, this.value = ''});
  _Condition copy() => _Condition(field: field, operator: operator, value: value);
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
  final String entityId;
  final String entityType;
  final String ruleName;
  final _RuleSeverity severity;
  final String field;
  final String message;
  final String when;
  bool resolved = false;
  _Violation({
    required this.entityId,
    required this.entityType,
    required this.ruleName,
    required this.severity,
    required this.field,
    required this.message,
    required this.when,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class DataQualityPage extends StatefulWidget {
  const DataQualityPage({super.key});

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _builderTab = 0; // 0=Manual, 1=AI

  // License
  bool get _licensed => _DqLicense.isValid;
  final _licKeyCtrl = TextEditingController();
  String? _licError;

  // Rules
  late List<_QualityRule> _rules;

  // AI builder
  final _aiCtrl = TextEditingController();
  bool _aiGenerating = false;
  _QualityRule? _aiPreview;

  // Violations
  late List<_Violation> _violations;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _rules = _defaultRules();
    _violations = _defaultViolations();
  }

  @override
  void dispose() {
    _tab.dispose();
    _licKeyCtrl.dispose();
    _aiCtrl.dispose();
    super.dispose();
  }

  // ── Default seed data ─────────────────────────────────────────────────────

  static List<_QualityRule> _defaultRules() => [
    _QualityRule(
      id: 'r1', name: 'Customer Email Required', entityType: 'Customer',
      dimension: 'Completeness',
      conditions: [_Condition(field: 'email', operator: _ConditionOperator.isNotEmpty)],
      action: _RuleAction.flag, severity: _RuleSeverity.critical, violations: 42,
    ),
    _QualityRule(
      id: 'r2', name: 'Email Format Valid', entityType: 'Customer',
      dimension: 'Validity',
      conditions: [_Condition(field: 'email', operator: _ConditionOperator.matches, value: r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$')],
      action: _RuleAction.reject, severity: _RuleSeverity.high, violations: 18,
    ),
    _QualityRule(
      id: 'r3', name: 'Vendor Tax ID Present', entityType: 'Vendor',
      dimension: 'Completeness',
      conditions: [_Condition(field: 'tax_number', operator: _ConditionOperator.isNotEmpty)],
      action: _RuleAction.flag, severity: _RuleSeverity.critical, violations: 7,
    ),
    _QualityRule(
      id: 'r4', name: 'Country Code Format', entityType: 'All',
      dimension: 'Validity',
      conditions: [_Condition(field: 'country', operator: _ConditionOperator.matches, value: r'^[A-Z]{2}$')],
      action: _RuleAction.flag, severity: _RuleSeverity.medium, violations: 113,
    ),
    _QualityRule(
      id: 'r5', name: 'Credit Limit Positive', entityType: 'Customer',
      dimension: 'Accuracy',
      conditions: [_Condition(field: 'credit_limit', operator: _ConditionOperator.greaterThan, value: '0')],
      action: _RuleAction.quarantine, severity: _RuleSeverity.high, violations: 3,
      isActive: false,
    ),
    _QualityRule(
      id: 'r6', name: 'Material Number Format', entityType: 'Material',
      dimension: 'Validity',
      conditions: [_Condition(field: 'material_number', operator: _ConditionOperator.matches, value: r'^MAT-\d{6}$')],
      action: _RuleAction.flag, severity: _RuleSeverity.medium, violations: 29,
    ),
  ];

  static List<_Violation> _defaultViolations() => [
    _Violation(entityId: 'CUST-001145', entityType: 'Customer', ruleName: 'Customer Email Required',
        severity: _RuleSeverity.critical, field: 'email', message: 'Field is empty', when: '2 min ago'),
    _Violation(entityId: 'CUST-000892', entityType: 'Customer', ruleName: 'Email Format Valid',
        severity: _RuleSeverity.high, field: 'email', message: 'Value "user@" does not match pattern', when: '14 min ago'),
    _Violation(entityId: 'CUST-001098', entityType: 'Customer', ruleName: 'Country Code Format',
        severity: _RuleSeverity.medium, field: 'country', message: 'Value "United States" expected ISO-2', when: '23 min ago'),
    _Violation(entityId: 'VEND-000312', entityType: 'Vendor', ruleName: 'Vendor Tax ID Present',
        severity: _RuleSeverity.critical, field: 'tax_number', message: 'Field is empty', when: '1 hr ago'),
    _Violation(entityId: 'MAT-000078', entityType: 'Material', ruleName: 'Material Number Format',
        severity: _RuleSeverity.medium, field: 'material_number', message: '"MAT78" missing leading zeros', when: '2 hr ago'),
  ];

  // ── Scores ────────────────────────────────────────────────────────────────

  static const _dimensions = [
    ('Completeness', 0.82, Color(0xFF00C896)),
    ('Accuracy',     0.77, Color(0xFF3B82F6)),
    ('Consistency',  0.91, Color(0xFF8B5CF6)),
    ('Uniqueness',   0.96, Color(0xFFFF6B35)),
    ('Timeliness',   0.88, Color(0xFFFFD700)),
    ('Validity',     0.74, Color(0xFFFF4D6D)),
  ];

  double get _overallScore =>
      _dimensions.fold(0.0, (s, d) => s + d.$2) / _dimensions.length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_licensed) return _buildLicenseGate();
    return _buildMain();
  }

  // ── License gate ──────────────────────────────────────────────────────────

  Widget _buildLicenseGate() {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppColors.glowShadow(color: AppColors.primary, intensity: 0.6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppColors.auroraGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.health_and_safety_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text('Data Quality Engine',
                    style: AppTextStyles.titleLarge.copyWith(fontSize: 22)),
                const SizedBox(height: 8),
                Text(
                  'This module requires a Data Quality license.\nEnter your license key to unlock rule building,\nquality scoring, and violation management.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: AppColors.mutedText),
                        const SizedBox(width: 6),
                        Text('Demo keys:', style: AppTextStyles.labelSmall),
                      ]),
                      const SizedBox(height: 6),
                      _demoKeyChip('NXS-DQ-ENTERPRISE-2026'),
                      const SizedBox(height: 4),
                      _demoKeyChip('NXS-DQ-PRO-2026'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _licKeyCtrl,
                  onChanged: (_) => setState(() => _licError = null),
                  style: AppTextStyles.inputText
                      .copyWith(fontFamily: 'monospace', letterSpacing: 1.4),
                  decoration: InputDecoration(
                    hintText: 'NXS-DQ-XXXX-XXXX',
                    hintStyle: AppTextStyles.inputHint,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    prefixIcon: const Icon(Icons.vpn_key_outlined,
                        size: 18, color: AppColors.mutedText),
                    errorText: _licError,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _activateLicense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Activate License'),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: AppAnimations.slow)
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1),
                  curve: AppAnimations.spring),
        ),
      ),
    );
  }

  Widget _demoKeyChip(String key) {
    return GestureDetector(
      onTap: () {
        _licKeyCtrl.text = key;
        setState(() => _licError = null);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.content_copy_rounded,
              size: 11, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(key,
              style: AppTextStyles.badgeLabel
                  .copyWith(color: AppColors.primary, fontFamily: 'monospace')),
        ]),
      ),
    );
  }

  void _activateLicense() {
    final key = _licKeyCtrl.text.trim().toUpperCase();
    _DqLicense.activate(key);
    if (_DqLicense.isValid) {
      setState(() {});
    } else {
      setState(() => _licError = 'Invalid license key — check and try again');
    }
  }

  // ── Main dashboard ─────────────────────────────────────────────────────────

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
                '$activeRules active rules  ·  $openViolations open violations  ·  '
                'Overall ${(_overallScore * 100).round()}%',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              setState(() => _DqLicense.revoke());
            },
            icon: const Icon(Icons.vpn_key_outlined,
                size: 14, color: AppColors.mutedText),
            label: Text('License',
                style: AppTextStyles.buttonSmall
                    .copyWith(color: AppColors.mutedText)),
          ),
          const SizedBox(width: 8),
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

  // ── Overview tab ──────────────────────────────────────────────────────────

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
          topRule?.name ?? '—',
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

  // ── Rule builder tab ──────────────────────────────────────────────────────

  Widget _buildRuleBuilderTab() {
    return Column(
      children: [
        // Sub-tab toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: AppColors.navyBackground,
          child: Row(
            children: [
              _subTabBtn(0, Icons.drag_indicator_rounded, 'Manual Builder'),
              const SizedBox(width: 8),
              _subTabBtn(1, Icons.auto_awesome_rounded, 'AI Rule Generator'),
              const Spacer(),
              if (_builderTab == 0)
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
            ],
          ),
        ),
        Expanded(
          child: _builderTab == 0
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

  // ── Manual drag-and-drop builder ──────────────────────────────────────────

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
                  onChanged: (v) => setState(() => rule.isActive = v),
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
                  onPressed: () =>
                      setState(() => _rules.removeWhere((r) => r.id == rule.id)),
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

  // ── AI rule builder ───────────────────────────────────────────────────────

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
                        Text(_aiGenerating ? 'Generating…' : 'Generate Rule'),
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
                  _builderTab = 0;
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
    // Simulate AI generation latency
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    final generated = _parseAiRule(prompt);
    setState(() {
      _aiGenerating = false;
      _aiPreview = generated;
    });
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
    final name = prompt.length > 48 ? '${prompt.substring(0, 45)}…' : prompt;

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

  // ── Violations tab ────────────────────────────────────────────────────────

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
                      const TextSpan(text: '·  field: '),
                      TextSpan(
                          text: v.field,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: AppColors.aiPurple)),
                      TextSpan(text: '  —  ${v.message}'),
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
              onPressed: () =>
                  setState(() => v.resolved = true),
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

  // ── Dialogs ───────────────────────────────────────────────────────────────

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

    showNexusDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDs) => NexusDialog(
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

  void _runAllRules() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Text(
              'Running ${_rules.where((r) => r.isActive).length} rules against all entities…',
              style: AppTextStyles.bodyMedium),
        ]),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rule editor widget (used inside dialog)
// ─────────────────────────────────────────────────────────────────────────────

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
              decoration: _deco('value or regex…'),
              style: AppTextStyles.inputText
                  .copyWith(fontSize: 12, fontFamily: 'monospace'),
            ),
          )
        else
          const Spacer(),
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

// ─────────────────────────────────────────────────────────────────────────────
// Gauge painter
// ─────────────────────────────────────────────────────────────────────────────

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
