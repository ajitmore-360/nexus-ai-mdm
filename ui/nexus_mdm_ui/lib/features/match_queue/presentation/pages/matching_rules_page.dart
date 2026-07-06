import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class MatchingRulesPage extends StatefulWidget {
  const MatchingRulesPage({super.key});

  @override
  State<MatchingRulesPage> createState() => _MatchingRulesPageState();
}

class _MatchingRulesPageState extends State<MatchingRulesPage> {
  final _api = GetIt.instance<ApiClient>();

  // Thresholds
  double _autoMergeThreshold = 0.95;
  double _reviewThreshold = 0.75;
  double _ambiguityDelta = 0.03;

  // Weights (should sum to 1.0)
  double _exactWeight = 0.35;
  double _fuzzyWeight = 0.30;
  double _phoneticWeight = 0.10;
  double _semanticWeight = 0.15;
  double _vectorWeight = 0.10;

  bool _saving = false;

  double get _weightSum =>
      _exactWeight + _fuzzyWeight + _phoneticWeight + _semanticWeight + _vectorWeight;

  bool get _weightsBalanced => (_weightSum - 1.0).abs() < 0.005;

  void _normalizeWeights() {
    final total = _weightSum;
    if (total == 0) return;
    setState(() {
      _exactWeight = _exactWeight / total;
      _fuzzyWeight = _fuzzyWeight / total;
      _phoneticWeight = _phoneticWeight / total;
      _semanticWeight = _semanticWeight / total;
      _vectorWeight = _vectorWeight / total;
    });
  }

  Future<void> _save() async {
    if (!_weightsBalanced) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.cardSurface,
        content: Text(
          'Weights must sum to 1.0. Use "Normalize" to fix.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.warning),
        ),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      await _api.patch<Map<String, dynamic>>(
        '/policy/weights',
        data: {
          'auto_merge_threshold': _autoMergeThreshold,
          'review_threshold': _reviewThreshold,
          'ambiguity_delta': _ambiguityDelta,
          'exact_weight': _exactWeight,
          'fuzzy_weight': _fuzzyWeight,
          'phonetic_weight': _phoneticWeight,
          'semantic_weight': _semanticWeight,
          'vector_weight': _vectorWeight,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.cardSurface,
        content: Text(
          'Matching policy updated.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.cardSurface,
        content: Text(
          'Failed: $e',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
        ),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildThresholdsCard(),
              const SizedBox(height: 16),
              _buildWeightsCard(),
              const SizedBox(height: 24),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune_outlined,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Matching Policy', style: AppTextStyles.titleMedium),
                Text(
                  'Configure auto-merge thresholds and feature weights.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThresholdsCard() {
    return _card(
      title: 'Decision Thresholds',
      icon: Icons.speed_outlined,
      iconColor: AppColors.cyan,
      children: [
        Text(
          'Scores above the auto-merge threshold bypass human review. '
          'Scores between the review and auto-merge thresholds enter the review queue.',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 20),
        _ThresholdSlider(
          label: 'Auto-merge threshold',
          value: _autoMergeThreshold,
          min: 0.80,
          max: 1.0,
          color: AppColors.success,
          description: 'Matches scoring above this are merged automatically.',
          onChanged: (v) {
            setState(() {
              _autoMergeThreshold = v;
              if (_reviewThreshold >= v) {
                _reviewThreshold = v - 0.05;
              }
            });
          },
        ),
        const SizedBox(height: 16),
        _ThresholdSlider(
          label: 'Review threshold',
          value: _reviewThreshold,
          min: 0.40,
          max: _autoMergeThreshold - 0.01,
          color: AppColors.warning,
          description: 'Matches scoring above this go to the review queue.',
          onChanged: (v) => setState(() => _reviewThreshold = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ambiguity delta',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.mutedText,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    'Minimum score gap between top candidates for auto-merge.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: _ambiguityDelta.toStringAsFixed(2),
                style: AppTextStyles.bodyMedium.copyWith(fontFamily: 'monospace'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.inputFill,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
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
                ),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null && d >= 0 && d <= 0.2) {
                    setState(() => _ambiguityDelta = d);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeightsCard() {
    final sumColor = _weightsBalanced
        ? AppColors.success
        : (_weightSum > 1.0 ? AppColors.error : AppColors.warning);

    return _card(
      title: 'Feature Weights',
      icon: Icons.bar_chart_outlined,
      iconColor: AppColors.aiPurple,
      trailing: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: sumColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sumColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Σ = ${_weightSum.toStringAsFixed(3)}',
              style: AppTextStyles.labelSmall.copyWith(
                color: sumColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (!_weightsBalanced) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _normalizeWeights,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Normalize',
                  style: AppTextStyles.buttonSmall
                      .copyWith(color: AppColors.primary)),
            ),
          ],
        ],
      ),
      children: [
        Text(
          'Weights determine how much each matching strategy contributes to the overall score. '
          'They must sum to 1.0.',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 20),
        _WeightSlider(
          label: 'Exact match',
          icon: Icons.check_circle_outline_rounded,
          value: _exactWeight,
          color: AppColors.primary,
          onChanged: (v) => setState(() => _exactWeight = v),
        ),
        const SizedBox(height: 12),
        _WeightSlider(
          label: 'Fuzzy match',
          icon: Icons.blur_on_rounded,
          value: _fuzzyWeight,
          color: AppColors.cyan,
          onChanged: (v) => setState(() => _fuzzyWeight = v),
        ),
        const SizedBox(height: 12),
        _WeightSlider(
          label: 'Phonetic',
          icon: Icons.record_voice_over_outlined,
          value: _phoneticWeight,
          color: AppColors.success,
          onChanged: (v) => setState(() => _phoneticWeight = v),
        ),
        const SizedBox(height: 12),
        _WeightSlider(
          label: 'Semantic (AI)',
          icon: Icons.auto_awesome_outlined,
          value: _semanticWeight,
          color: AppColors.aiPurple,
          onChanged: (v) => setState(() => _semanticWeight = v),
        ),
        const SizedBox(height: 12),
        _WeightSlider(
          label: 'Vector similarity',
          icon: Icons.scatter_plot_outlined,
          value: _vectorWeight,
          color: AppColors.warning,
          onChanged: (v) => setState(() => _vectorWeight = v),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => setState(() {
            _autoMergeThreshold = 0.95;
            _reviewThreshold = 0.75;
            _ambiguityDelta = 0.03;
            _exactWeight = 0.35;
            _fuzzyWeight = 0.30;
            _phoneticWeight = 0.10;
            _semanticWeight = 0.15;
            _vectorWeight = 0.10;
          }),
          child: Text('Reset to defaults',
              style: AppTextStyles.buttonMedium
                  .copyWith(color: AppColors.secondaryText)),
        ),
        const SizedBox(width: 12),
        _saving
            ? const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            : ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Apply Policy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    required List<Widget> children,
  }) {
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
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.titleSmall),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

// ─── Threshold slider ─────────────────────────────────────────────────────────

class _ThresholdSlider extends StatelessWidget {
  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  const _ThresholdSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.mutedText, letterSpacing: 0.8)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${(value * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.labelSmall.copyWith(
                    color: color, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: AppColors.divider,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 100).round(),
            onChanged: onChanged,
          ),
        ),
        Text(description,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText, fontSize: 11)),
      ],
    );
  }
}

// ─── Weight slider ────────────────────────────────────────────────────────────

class _WeightSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _WeightSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        SizedBox(
          width: 130,
          child: Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primaryText)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: AppColors.divider,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: AppTextStyles.labelSmall.copyWith(
                color: color, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
