import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ──────────────────────────────────────────────
// Domain models
// ──────────────────────────────────────────────

enum _WinnerSide { source, candidate }

enum _ReasonBadge { trustedSource, mostRecent, longest, override_ }

extension _ReasonBadgeLabel on _ReasonBadge {
  String get label {
    switch (this) {
      case _ReasonBadge.trustedSource:
        return 'Trusted Source';
      case _ReasonBadge.mostRecent:
        return 'Most Recent';
      case _ReasonBadge.longest:
        return 'Longest';
      case _ReasonBadge.override_:
        return 'Override';
    }
  }

  Color get color {
    switch (this) {
      case _ReasonBadge.trustedSource:
        return AppColors.primary;
      case _ReasonBadge.mostRecent:
        return AppColors.info;
      case _ReasonBadge.longest:
        return AppColors.warning;
      case _ReasonBadge.override_:
        return AppColors.aiPurple;
    }
  }
}

class _MergeAttribute {
  final String key;
  final String label;
  final String sourceValue;
  final String candidateValue;
  final _WinnerSide aiSuggestion;
  final _ReasonBadge aiReason;

  const _MergeAttribute({
    required this.key,
    required this.label,
    required this.sourceValue,
    required this.candidateValue,
    required this.aiSuggestion,
    required this.aiReason,
  });
}

// ──────────────────────────────────────────────
// Page
// ──────────────────────────────────────────────

class MergeStudioPage extends StatefulWidget {
  final String sourceId;
  final String candidateId;

  const MergeStudioPage({
    super.key,
    required this.sourceId,
    required this.candidateId,
  });

  @override
  State<MergeStudioPage> createState() => _MergeStudioPageState();
}

class _MergeStudioPageState extends State<MergeStudioPage> {
  bool _isExecuting = false;
  bool _aiApplied = true;

  static const _attributes = [
    _MergeAttribute(
      key: 'legal_name',
      label: 'Legal Name',
      sourceValue: 'Michael A. Rodriguez',
      candidateValue: 'M. Rodriguez Jr.',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.trustedSource,
    ),
    _MergeAttribute(
      key: 'email',
      label: 'Email',
      sourceValue: 'mrodriguez@company.com',
      candidateValue: 'michael.r@company.com',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.trustedSource,
    ),
    _MergeAttribute(
      key: 'phone',
      label: 'Phone',
      sourceValue: '+1-555-0147',
      candidateValue: '+1 (555) 0147',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.mostRecent,
    ),
    _MergeAttribute(
      key: 'address',
      label: 'Address',
      sourceValue: '350 Mission St, SF, CA',
      candidateValue: '350 Mission Street, San Francisco, CA 94105',
      aiSuggestion: _WinnerSide.candidate,
      aiReason: _ReasonBadge.longest,
    ),
    _MergeAttribute(
      key: 'tax_id',
      label: 'Tax ID',
      sourceValue: '92-1847365',
      candidateValue: '92-1847365',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.trustedSource,
    ),
    _MergeAttribute(
      key: 'revenue',
      label: 'Revenue (USD)',
      sourceValue: '\$4,200,000',
      candidateValue: '\$3,800,000',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.mostRecent,
    ),
    _MergeAttribute(
      key: 'employees',
      label: 'Employees',
      sourceValue: '248',
      candidateValue: '231',
      aiSuggestion: _WinnerSide.source,
      aiReason: _ReasonBadge.mostRecent,
    ),
  ];

  late Map<String, _WinnerSide> _selections;
  late Map<String, _ReasonBadge> _reasons;

  @override
  void initState() {
    super.initState();
    _applyAiSuggestions();
  }

  void _applyAiSuggestions() {
    _selections = {for (final a in _attributes) a.key: a.aiSuggestion};
    _reasons = {for (final a in _attributes) a.key: a.aiReason};
  }

  void _resetToManual() {
    setState(() {
      _aiApplied = false;
      for (final a in _attributes) {
        _selections[a.key] = _WinnerSide.source;
        _reasons[a.key] = _ReasonBadge.override_;
      }
    });
  }

  String _winnerValue(_MergeAttribute attr) {
    final side = _selections[attr.key] ?? _WinnerSide.source;
    return side == _WinnerSide.source ? attr.sourceValue : attr.candidateValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          _buildAiBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAttributeTable(),
                  const SizedBox(height: 24),
                  _buildGoldenPreview(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.secondaryText),
            onPressed: () => context.pop(),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Merging: ', style: AppTextStyles.titleSmall.copyWith(color: AppColors.secondaryText)),
                    Text('ENT-${widget.sourceId}', style: AppTextStyles.titleSmall.copyWith(color: AppColors.primary)),
                    Text(' + ', style: AppTextStyles.titleSmall.copyWith(color: AppColors.secondaryText)),
                    Text('ENT-${widget.candidateId}', style: AppTextStyles.titleSmall.copyWith(color: AppColors.warning)),
                    Text(' → ', style: AppTextStyles.titleSmall.copyWith(color: AppColors.secondaryText)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('NEW GOLDEN RECORD', style: AppTextStyles.badgeLabel.copyWith(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Attribute-level survivorship editor', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  // ── AI Banner ────────────────────────────────
  Widget _buildAiBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _aiApplied
            ? AppColors.aiPurple.withValues(alpha: 0.08)
            : AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _aiApplied
              ? AppColors.aiPurple.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 16,
            color: _aiApplied ? AppColors.aiPurple : AppColors.mutedText,
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _aiApplied
                  ? AppColors.aiPurple.withValues(alpha: 0.15)
                  : AppColors.cardSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _aiApplied ? 'AI Suggestion Applied' : 'Manual Mode',
              style: AppTextStyles.labelSmall.copyWith(
                color: _aiApplied ? AppColors.aiPurple : AppColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_aiApplied)
            Text(
              'Survivorship rules selected by AI — review and override as needed.',
              style: AppTextStyles.bodySmall,
            ),
          const Spacer(),
          TextButton(
            onPressed: _resetToManual,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryText,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Reset to Manual'),
          ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 350.ms);
  }

  // ── Attribute Table ──────────────────────────
  Widget _buildAttributeTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.elevatedCard,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text('ATTRIBUTE', style: AppTextStyles.tableHeader),
                ),
                Expanded(
                  child: Text(
                    'SOURCE (Salesforce)',
                    style: AppTextStyles.tableHeader.copyWith(color: AppColors.info),
                  ),
                ),
                Expanded(
                  child: Text(
                    'CANDIDATE (SAP)',
                    style: AppTextStyles.tableHeader.copyWith(color: AppColors.warning),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text('WINNER', style: AppTextStyles.tableHeader),
                ),
                SizedBox(
                  width: 120,
                  child: Text('REASON', style: AppTextStyles.tableHeader),
                ),
              ],
            ),
          ),

          // Rows
          ..._attributes.asMap().entries.map((e) {
            final i = e.key;
            final attr = e.value;
            final isLast = i == _attributes.length - 1;
            return _buildAttributeRow(attr, isLast, i);
          }),
        ],
      ),
    ).animate(delay: 150.ms).fadeIn(duration: 400.ms);
  }

  Widget _buildAttributeRow(_MergeAttribute attr, bool isLast, int index) {
    final currentSide = _selections[attr.key] ?? _WinnerSide.source;
    final currentReason = _reasons[attr.key] ?? _ReasonBadge.override_;
    final isSourceWin = currentSide == _WinnerSide.source;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Attribute name
            SizedBox(
              width: 140,
              child: Text(attr.label, style: AppTextStyles.titleSmall),
            ),

            // Source value
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  attr.sourceValue,
                  style: AppTextStyles.tableCell.copyWith(
                    color: isSourceWin ? AppColors.primaryText : AppColors.mutedText,
                    fontWeight: isSourceWin ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Candidate value
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  attr.candidateValue,
                  style: AppTextStyles.tableCell.copyWith(
                    color: !isSourceWin ? AppColors.primaryText : AppColors.mutedText,
                    fontWeight: !isSourceWin ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Winner radio selector
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  _WinnerRadio(
                    label: 'Src',
                    selected: isSourceWin,
                    onTap: () => setState(() {
                      _selections[attr.key] = _WinnerSide.source;
                      _reasons[attr.key] = _ReasonBadge.override_;
                      _aiApplied = false;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _WinnerRadio(
                    label: 'Can',
                    selected: !isSourceWin,
                    onTap: () => setState(() {
                      _selections[attr.key] = _WinnerSide.candidate;
                      _reasons[attr.key] = _ReasonBadge.override_;
                      _aiApplied = false;
                    }),
                  ),
                ],
              ),
            ),

            // Reason badge
            SizedBox(
              width: 120,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: currentReason.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: currentReason.color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  currentReason.label,
                  style: AppTextStyles.badgeLabel.copyWith(color: currentReason.color),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 50 + 200).ms).fadeIn(duration: 300.ms);
  }

  // ── Golden Record Preview ────────────────────
  Widget _buildGoldenPreview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.07),
            AppColors.cardSurface,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Text('Golden Record Preview', style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.statusGolden.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PREVIEW',
                  style: AppTextStyles.badgeLabel.copyWith(color: AppColors.statusGolden),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: _attributes.map((attr) {
              return SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(attr.label, style: AppTextStyles.tableHeader),
                    const SizedBox(height: 2),
                    Text(
                      _winnerValue(attr),
                      style: AppTextStyles.tableCell.copyWith(color: AppColors.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
  }

  // ── Bottom Bar ───────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // AI Suggestions button
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _applyAiSuggestions();
                _aiApplied = true;
              });
            },
            icon: const Icon(Icons.smart_toy_outlined, size: 16),
            label: const Text('Apply AI Suggestions'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.aiPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: AppTextStyles.buttonMedium,
            ),
          ),
          const SizedBox(width: 8),
          // Reset to rules
          OutlinedButton.icon(
            onPressed: _resetToManual,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Reset to Rules'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondaryText,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: AppTextStyles.buttonMedium,
            ),
          ),
          const Spacer(),
          // Execute Merge
          ElevatedButton.icon(
            onPressed: _isExecuting ? null : _executeMerge,
            icon: _isExecuting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.bolt_rounded, size: 18),
            label: Text(_isExecuting ? 'Executing...' : 'Execute Merge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              textStyle: AppTextStyles.buttonLarge,
              shadowColor: AppColors.primary.withValues(alpha: 0.4),
              elevation: 4,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  void _executeMerge() async {
    setState(() => _isExecuting = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _isExecuting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.stars_rounded, color: AppColors.statusGolden, size: 18),
            const SizedBox(width: 10),
            Text('Golden record created successfully.', style: AppTextStyles.bodyMedium),
          ],
        ),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.pop();
  }
}

// ──────────────────────────────────────────────
// Winner Radio Button
// ──────────────────────────────────────────────

class _WinnerRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WinnerRadio({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.navyBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: selected ? AppColors.primary : AppColors.secondaryText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
