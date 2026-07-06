import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../widgets/admin_form_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class FieldWeights {
  final double exact;
  final double fuzzy;
  final double phonetic;
  final double semantic;
  final double vector;

  const FieldWeights({
    required this.exact,
    required this.fuzzy,
    required this.phonetic,
    required this.semantic,
    required this.vector,
  });

  double get total => exact + fuzzy + phonetic + semantic + vector;

  factory FieldWeights.fromJson(Map<String, dynamic> json) => FieldWeights(
        exact: (json['exact'] as num?)?.toDouble() ?? 0.0,
        fuzzy: (json['fuzzy'] as num?)?.toDouble() ?? 0.0,
        phonetic: (json['phonetic'] as num?)?.toDouble() ?? 0.0,
        semantic: (json['semantic'] as num?)?.toDouble() ?? 0.0,
        vector: (json['vector'] as num?)?.toDouble() ?? 0.0,
      );

  factory FieldWeights.defaults() => const FieldWeights(
        exact: 0.30,
        fuzzy: 0.25,
        phonetic: 0.15,
        semantic: 0.20,
        vector: 0.10,
      );

  Map<String, dynamic> toJson() => {
        'exact': exact,
        'fuzzy': fuzzy,
        'phonetic': phonetic,
        'semantic': semantic,
        'vector': vector,
      };

  FieldWeights copyWith({
    double? exact,
    double? fuzzy,
    double? phonetic,
    double? semantic,
    double? vector,
  }) =>
      FieldWeights(
        exact: exact ?? this.exact,
        fuzzy: fuzzy ?? this.fuzzy,
        phonetic: phonetic ?? this.phonetic,
        semantic: semantic ?? this.semantic,
        vector: vector ?? this.vector,
      );
}

class DomainPolicy {
  final String entityTypeCode;
  final double autoMergeThreshold;
  final double reviewThreshold;
  final FieldWeights fieldWeights;

  const DomainPolicy({
    required this.entityTypeCode,
    required this.autoMergeThreshold,
    required this.reviewThreshold,
    required this.fieldWeights,
  });

  factory DomainPolicy.fromJson(Map<String, dynamic> json) => DomainPolicy(
        entityTypeCode: json['entity_type_code'] as String? ?? '',
        autoMergeThreshold:
            (json['auto_merge_threshold'] as num?)?.toDouble() ?? 0.90,
        reviewThreshold:
            (json['review_threshold'] as num?)?.toDouble() ?? 0.70,
        fieldWeights: json['field_weights'] != null
            ? FieldWeights.fromJson(
                json['field_weights'] as Map<String, dynamic>)
            : FieldWeights.defaults(),
      );

  Map<String, dynamic> toJson() => {
        'entity_type_code': entityTypeCode,
        'auto_merge_threshold': autoMergeThreshold,
        'review_threshold': reviewThreshold,
        'field_weights': fieldWeights.toJson(),
      };

  DomainPolicy copyWith({
    double? autoMergeThreshold,
    double? reviewThreshold,
    FieldWeights? fieldWeights,
  }) =>
      DomainPolicy(
        entityTypeCode: entityTypeCode,
        autoMergeThreshold: autoMergeThreshold ?? this.autoMergeThreshold,
        reviewThreshold: reviewThreshold ?? this.reviewThreshold,
        fieldWeights: fieldWeights ?? this.fieldWeights,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class _DomainPolicyRepository {
  final ApiClient _api;
  _DomainPolicyRepository(this._api);

  Future<List<DomainPolicy>> listPolicies() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>('/v1/domain-policies');
      final data = response.data;
      if (data == null) return [];
      final items = data['items'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          [];
      return items
          .map((e) => DomainPolicy.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      assert(() {
        debugPrint('[DomainPolicyRepository] listPolicies error: $e');
        return true;
      }());
      return [];
    }
  }

  Future<bool> savePolicy(DomainPolicy policy) async {
    try {
      await _api.put<Map<String, dynamic>>(
        '/v1/domain-policies/${policy.entityTypeCode}',
        data: policy.toJson(),
      );
      return true;
    } catch (e) {
      assert(() {
        debugPrint('[DomainPolicyRepository] savePolicy error: $e');
        return true;
      }());
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entity type metadata
// ─────────────────────────────────────────────────────────────────────────────

const _kEntityTypes = [
  _EntityMeta(code: 'CUSTOMER', label: 'Customer', icon: '👤'),
  _EntityMeta(code: 'PRODUCT', label: 'Product', icon: '📦'),
  _EntityMeta(code: 'VENDOR', label: 'Vendor', icon: '🏭'),
  _EntityMeta(code: 'EMPLOYEE', label: 'Employee', icon: '💼'),
  _EntityMeta(code: 'LOCATION', label: 'Location', icon: '📍'),
  _EntityMeta(code: 'ORGANIZATION', label: 'Organization', icon: '🏢'),
  _EntityMeta(code: 'ASSET', label: 'Asset', icon: '🔧'),
];

class _EntityMeta {
  final String code;
  final String label;
  final String icon;
  const _EntityMeta(
      {required this.code, required this.label, required this.icon});
}

_EntityMeta _metaFor(String code) => _kEntityTypes.firstWhere(
      (m) => m.code == code,
      orElse: () => _EntityMeta(code: code, label: code, icon: '📄'),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class DomainPolicyPage extends StatefulWidget {
  const DomainPolicyPage({super.key});

  @override
  State<DomainPolicyPage> createState() => _DomainPolicyPageState();
}

class _DomainPolicyPageState extends State<DomainPolicyPage> {
  late final _DomainPolicyRepository _repo;
  List<DomainPolicy> _policies = [];
  bool _loading = true;
  String? _error;

  static const _defaultPolicy = DomainPolicy(
    entityTypeCode: 'DEFAULT',
    autoMergeThreshold: 0.92,
    reviewThreshold: 0.72,
    fieldWeights: FieldWeights(
      exact: 0.30,
      fuzzy: 0.25,
      phonetic: 0.15,
      semantic: 0.20,
      vector: 0.10,
    ),
  );

  @override
  void initState() {
    super.initState();
    _repo = _DomainPolicyRepository(GetIt.instance<ApiClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final policies = await _repo.listPolicies();
      if (!mounted) return;
      setState(() {
        _policies = policies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load domain policies. Check your connection.';
        _loading = false;
      });
    }
  }

  void _openCreateDialog() {
    final existingCodes = _policies.map((p) => p.entityTypeCode).toSet();
    final available =
        _kEntityTypes.where((m) => !existingCodes.contains(m.code)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(
            'All entity types already have policies configured.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText),
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _PolicyEditDialog(
        policy: DomainPolicy(
          entityTypeCode: available.first.code,
          autoMergeThreshold: _defaultPolicy.autoMergeThreshold,
          reviewThreshold: _defaultPolicy.reviewThreshold,
          fieldWeights: _defaultPolicy.fieldWeights,
        ),
        isCreating: true,
        availableCodes: available.map((m) => m.code).toList(),
        repo: _repo,
        onSaved: _load,
      ),
    );
  }

  void _openEditDialog(DomainPolicy policy) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _PolicyEditDialog(
        policy: policy,
        isCreating: false,
        availableCodes: [policy.entityTypeCode],
        repo: _repo,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add domain policy',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _buildHeader(),
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
              Text('Domain Matching Policies', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${_policies.length} custom ${_policies.length == 1 ? 'policy' : 'policies'} configured',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Add Policy',
            onTap: _openCreateDialog,
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
          Text(
            _error!,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: Text('Retry',
                style: AppTextStyles.buttonMedium
                    .copyWith(color: AppColors.primary)),
          ),
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
          // Default policy reference card
          const _DefaultPolicyCard(policy: _defaultPolicy),
          const SizedBox(height: 28),

          // Section header
          if (_policies.isNotEmpty) ...[
            const Row(
              children: [
                AdminSectionHeader(label: 'CUSTOM POLICIES'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _policies
                  .map((p) => _PolicyCard(
                        policy: p,
                        onTap: () => _openEditDialog(p),
                      ))
                  .toList(),
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Icon(
                      Icons.tune_outlined,
                      size: 48,
                      color: AppColors.mutedText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No custom policies yet.',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All entity types use the default policy above.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Bottom padding for FAB
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default policy reference card (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class _DefaultPolicyCard extends StatelessWidget {
  final DomainPolicy policy;
  const _DefaultPolicyCard({required this.policy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'SYSTEM DEFAULT',
                  style: AppTextStyles.chipLabel.copyWith(
                    color: AppColors.cyan,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('Global fallback — read only',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ThresholdBadge(
                  label: 'AUTO-MERGE',
                  value: policy.autoMergeThreshold,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThresholdBadge(
                  label: 'REVIEW',
                  value: policy.reviewThreshold,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThresholdBadge(
                  label: 'REJECT BELOW',
                  value: policy.reviewThreshold,
                  color: AppColors.error,
                  isBelow: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('FIELD WEIGHTS', style: AppTextStyles.labelSmall.copyWith(
            fontSize: 10,
            color: AppColors.mutedText,
            letterSpacing: 1.0,
          )),
          const SizedBox(height: 10),
          _WeightBar(weights: policy.fieldWeights),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Policy card (per entity type)
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyCard extends StatelessWidget {
  final DomainPolicy policy;
  final VoidCallback onTap;

  const _PolicyCard({required this.policy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(policy.entityTypeCode);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
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
                    child: Text(meta.icon,
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meta.label,
                          style: AppTextStyles.titleSmall,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        policy.entityTypeCode,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontFamily: 'monospace',
                          color: AppColors.mutedText,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined,
                    size: 15, color: AppColors.secondaryText),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniThreshold(
                    label: 'Merge',
                    value: policy.autoMergeThreshold,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniThreshold(
                    label: 'Review',
                    value: policy.reviewThreshold,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _WeightBar(weights: policy.fieldWeights, compact: true),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared display sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ThresholdBadge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isBelow;

  const _ThresholdBadge({
    required this.label,
    required this.value,
    required this.color,
    this.isBelow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: color.withValues(alpha: 0.8),
              fontSize: 9,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isBelow ? '< ${value.toStringAsFixed(2)}' : value.toStringAsFixed(2),
            style: AppTextStyles.titleSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniThreshold extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MiniThreshold(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text(label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondaryText,
                fontSize: 10,
              )),
          const Spacer(),
          Text(
            value.toStringAsFixed(2),
            style: AppTextStyles.labelMedium.copyWith(
              color: color,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Stacked bar showing proportional weight breakdown
class _WeightBar extends StatelessWidget {
  final FieldWeights weights;
  final bool compact;

  const _WeightBar({required this.weights, this.compact = false});

  static const _labels = ['Exact', 'Fuzzy', 'Phonetic', 'Semantic', 'Vector'];
  static const _colors = [
    Color(0xFF7C3AED), // violet — exact
    Color(0xFF00D9FF), // cyan — fuzzy
    Color(0xFFA855F7), // violet light — phonetic
    Color(0xFFFFB800), // amber — semantic
    Color(0xFF10F090), // green — vector
  ];

  List<double> get _values => [
        weights.exact,
        weights.fuzzy,
        weights.phonetic,
        weights.semantic,
        weights.vector,
      ];

  @override
  Widget build(BuildContext context) {
    final total = weights.total;
    final values = _values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stacked bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: List.generate(values.length, (i) {
                final frac = total > 0 ? values[i] / total : 0.0;
                return Expanded(
                  flex: (frac * 1000).round(),
                  child: Container(
                    color: _colors[i],
                  ),
                );
              }),
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(values.length, (i) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colors[i],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_labels[i]} ${(values[i] * 100).toStringAsFixed(0)}%',
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit / create dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyEditDialog extends StatefulWidget {
  final DomainPolicy policy;
  final bool isCreating;
  final List<String> availableCodes;
  final _DomainPolicyRepository repo;
  final VoidCallback onSaved;

  const _PolicyEditDialog({
    required this.policy,
    required this.isCreating,
    required this.availableCodes,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_PolicyEditDialog> createState() => _PolicyEditDialogState();
}

class _PolicyEditDialogState extends State<_PolicyEditDialog> {
  late String _selectedCode;
  late double _autoMerge;
  late double _review;
  late double _exact;
  late double _fuzzy;
  late double _phonetic;
  late double _semantic;
  late double _vector;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.policy.entityTypeCode;
    _autoMerge = widget.policy.autoMergeThreshold;
    _review = widget.policy.reviewThreshold;
    _exact = widget.policy.fieldWeights.exact;
    _fuzzy = widget.policy.fieldWeights.fuzzy;
    _phonetic = widget.policy.fieldWeights.phonetic;
    _semantic = widget.policy.fieldWeights.semantic;
    _vector = widget.policy.fieldWeights.vector;
  }

  double get _weightsTotal => _exact + _fuzzy + _phonetic + _semantic + _vector;

  Color get _sumColor {
    final t = _weightsTotal;
    if ((t - 1.0).abs() <= 0.05) return AppColors.success;
    if ((t - 1.0).abs() <= 0.15) return AppColors.warning;
    return AppColors.error;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = DomainPolicy(
      entityTypeCode: _selectedCode,
      autoMergeThreshold: _autoMerge,
      reviewThreshold: _review,
      fieldWeights: FieldWeights(
        exact: _exact,
        fuzzy: _fuzzy,
        phonetic: _phonetic,
        semantic: _semantic,
        vector: _vector,
      ),
    );
    final ok = await widget.repo.savePolicy(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
      widget.onSaved();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(
            'Failed to save policy. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ),
      );
    }
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    Color? activeColor,
    String? hint,
  }) {
    final color = activeColor ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11,
                color: AppColors.mutedText,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                value.toStringAsFixed(2),
                style: AppTextStyles.codeStyle.copyWith(
                  color: color,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.15),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.12),
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 100).round(),
            onChanged: onChanged,
          ),
        ),
        if (hint != null)
          Text(hint,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.mutedText, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(_selectedCode);

    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(meta.icon,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isCreating
                              ? 'New Domain Policy'
                              : 'Edit Policy',
                          style: AppTextStyles.titleMedium,
                        ),
                        Text(
                          widget.isCreating
                              ? 'Configure matching thresholds and weights'
                              : meta.label,
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
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
            ),

            // Body — scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Entity type selector (create) or locked label (edit)
                    if (widget.isCreating) ...[
                      AdminDropdownField<String>(
                        label: 'ENTITY TYPE',
                        value: _selectedCode,
                        items: widget.availableCodes,
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedCode = v);
                        },
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ENTITY TYPE',
                            style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 11,
                              color: AppColors.mutedText,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${meta.icon}  ${meta.label}',
                                  style: AppTextStyles.inputText,
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.mutedText
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _selectedCode,
                                    style: AppTextStyles.codeStyle.copyWith(
                                      fontSize: 10,
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Thresholds section
                    const AdminSectionHeader(label: 'MATCH THRESHOLDS'),
                    const SizedBox(height: 4),
                    _buildSlider(
                      label: 'AUTO-MERGE THRESHOLD',
                      value: _autoMerge,
                      min: 0.70,
                      max: 1.0,
                      activeColor: AppColors.success,
                      hint:
                          'Records scoring above this are merged automatically',
                      onChanged: (v) {
                        setState(() {
                          _autoMerge = v;
                          if (_review >= v) {
                            _review = (v - 0.05).clamp(0.50, 0.95);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSlider(
                      label: 'REVIEW THRESHOLD',
                      value: _review,
                      min: 0.50,
                      max: 0.95,
                      activeColor: AppColors.warning,
                      hint:
                          'Records between this and auto-merge are queued for review',
                      onChanged: (v) {
                        setState(() {
                          _review = v;
                          if (_autoMerge <= v) {
                            _autoMerge = (v + 0.05).clamp(0.70, 1.0);
                          }
                        });
                      },
                    ),

                    // Visual range summary
                    const SizedBox(height: 12),
                    _ThresholdRangeSummary(
                      autoMerge: _autoMerge,
                      review: _review,
                    ),

                    const SizedBox(height: 24),

                    // Field weights section
                    Row(
                      children: [
                        const AdminSectionHeader(label: 'FIELD WEIGHTS'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _sumColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: _sumColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Sum: ${_weightsTotal.toStringAsFixed(2)}${((_weightsTotal - 1.0).abs() <= 0.05) ? ' ✓' : '  — should be ~1.0'}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: _sumColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildSlider(
                      label: 'EXACT MATCH',
                      value: _exact,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFF7C3AED),
                      onChanged: (v) => setState(() => _exact = v),
                    ),
                    const SizedBox(height: 4),
                    _buildSlider(
                      label: 'FUZZY MATCH',
                      value: _fuzzy,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFF00D9FF),
                      onChanged: (v) => setState(() => _fuzzy = v),
                    ),
                    const SizedBox(height: 4),
                    _buildSlider(
                      label: 'PHONETIC',
                      value: _phonetic,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFFA855F7),
                      onChanged: (v) => setState(() => _phonetic = v),
                    ),
                    const SizedBox(height: 4),
                    _buildSlider(
                      label: 'SEMANTIC',
                      value: _semantic,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFFFFB800),
                      onChanged: (v) => setState(() => _semantic = v),
                    ),
                    const SizedBox(height: 4),
                    _buildSlider(
                      label: 'VECTOR SIMILARITY',
                      value: _vector,
                      min: 0.0,
                      max: 1.0,
                      activeColor: const Color(0xFF10F090),
                      onChanged: (v) => setState(() => _vector = v),
                    ),

                    const SizedBox(height: 16),
                    // Live weight bar preview
                    _WeightBar(
                      weights: FieldWeights(
                        exact: _exact,
                        fuzzy: _fuzzy,
                        phonetic: _phonetic,
                        semantic: _semantic,
                        vector: _vector,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer actions
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Text(
                    widget.isCreating ? 'New policy' : 'Editing ${meta.label}',
                    style: AppTextStyles.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: AppTextStyles.buttonMedium
                            .copyWith(color: AppColors.secondaryText)),
                  ),
                  const SizedBox(width: 12),
                  AdminGradientButton(
                    label: widget.isCreating ? 'Create Policy' : 'Save Changes',
                    loading: _saving,
                    onTap: _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Threshold range visual summary
// ─────────────────────────────────────────────────────────────────────────────

class _ThresholdRangeSummary extends StatelessWidget {
  final double autoMerge;
  final double review;

  const _ThresholdRangeSummary(
      {required this.autoMerge, required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _Band(
            label: 'REJECT',
            range: '< ${review.toStringAsFixed(2)}',
            color: AppColors.error,
            flex: (review * 100).round(),
          ),
          const SizedBox(width: 4),
          _Band(
            label: 'REVIEW',
            range:
                '${review.toStringAsFixed(2)} – ${autoMerge.toStringAsFixed(2)}',
            color: AppColors.warning,
            flex: ((autoMerge - review) * 100).round(),
          ),
          const SizedBox(width: 4),
          _Band(
            label: 'AUTO-MERGE',
            range: '> ${autoMerge.toStringAsFixed(2)}',
            color: AppColors.success,
            flex: ((1.0 - autoMerge) * 100).round(),
          ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final String label;
  final String range;
  final Color color;
  final int flex;

  const _Band(
      {required this.label,
      required this.range,
      required this.color,
      required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex.clamp(1, 100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 9,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              range,
              style: AppTextStyles.codeStyle.copyWith(
                fontSize: 9,
                color: color.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
