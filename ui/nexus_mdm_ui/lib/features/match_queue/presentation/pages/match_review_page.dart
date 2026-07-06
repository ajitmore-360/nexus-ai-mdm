import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/models/entity.dart';
import '../../../entities/data/entity_repository.dart';
import '../../data/match_repository.dart';

// ──────────────────────────────────────────────
// Demo Data Models
// ──────────────────────────────────────────────

enum _MatchType { exact, fuzzy, conflict }

class _FieldComparison {
  final String fieldName;
  final String sourceValue;
  final String candidateValue;
  final _MatchType matchType;
  final double score;

  const _FieldComparison({
    required this.fieldName,
    required this.sourceValue,
    required this.candidateValue,
    required this.matchType,
    required this.score,
  });
}

class _ReviewRecord {
  final String entityName;
  final String entityId;
  final String sourceSystem;
  final String type;

  const _ReviewRecord({
    required this.entityName,
    required this.entityId,
    required this.sourceSystem,
    required this.type,
  });
}

// ──────────────────────────────────────────────
// Page
// ──────────────────────────────────────────────

class MatchReviewPage extends StatefulWidget {
  final String matchId;

  const MatchReviewPage({super.key, required this.matchId});

  @override
  State<MatchReviewPage> createState() => _MatchReviewPageState();
}

class _MatchReviewPageState extends State<MatchReviewPage>
    with SingleTickerProviderStateMixin {
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingAi = false;

  ReviewQueueItem? _reviewItem;

  // These defaults show until real data loads
  _ReviewRecord _source = const _ReviewRecord(
    entityName: 'Loading…',
    entityId: '—',
    sourceSystem: '—',
    type: '—',
  );

  _ReviewRecord _candidate = const _ReviewRecord(
    entityName: 'Loading…',
    entityId: '—',
    sourceSystem: '—',
    type: '—',
  );

  double _overallScore = 0.0;
  double _aiConfidence = 0.0;
  String _aiExplanation = 'Loading AI analysis…';
  List<_FieldComparison> _fields = [];
  bool _fieldsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviewItem();
  }

  Future<void> _loadReviewItem() async {
    final repo = GetIt.instance<MatchRepository>();
    final result = await repo.getReviewQueue();
    if (!mounted) return;
    if (result case Success(:final data)) {
      final item = data.cast<ReviewQueueItem?>().firstWhere(
            (i) => i!.requestId == widget.matchId || i.candidateId == widget.matchId,
            orElse: () => null,
          );
      if (item != null) {
        setState(() {
          _reviewItem = item;
          _source = _ReviewRecord(
            entityName: item.sourceEntityId,
            entityId: item.sourceEntityId,
            sourceSystem: 'Source System',
            type: 'Entity',
          );
          _candidate = _ReviewRecord(
            entityName: item.candidateEntityId,
            entityId: item.candidateEntityId,
            sourceSystem: 'Candidate System',
            type: 'Entity',
          );
          _overallScore = item.score;
          _aiConfidence = item.aiConfidence ?? 0.0;
          _aiExplanation = item.aiExplanation ??
              'AI analysis based on field-level similarity scores.';
        });
        _loadFieldComparisons(item.sourceEntityId, item.candidateEntityId);
      } else {
        if (mounted) setState(() => _fieldsLoading = false);
      }
    } else {
      if (mounted) setState(() => _fieldsLoading = false);
    }
  }

  Future<void> _loadFieldComparisons(String sourceId, String candidateId) async {
    final entityRepo = EntityRepository(ApiClient());
    final results = await Future.wait([
      entityRepo.getEntity(sourceId),
      entityRepo.getEntity(candidateId),
    ]);
    if (!mounted) return;

    CanonicalEntity? src, cand;
    if (results[0] case Success<CanonicalEntity>(:final data)) src = data;
    if (results[1] case Success<CanonicalEntity>(:final data)) cand = data;

    final srcAttrs = src?.attributes ?? {};
    final candAttrs = cand?.attributes ?? {};
    final allKeys = {...srcAttrs.keys, ...candAttrs.keys};

    final comparisons = allKeys.map((key) {
      final s = srcAttrs[key];
      final c = candAttrs[key];
      final sv = s?.value?.toString() ?? '—';
      final cv = c?.value?.toString() ?? '—';

      _MatchType type;
      double score;
      if (sv == cv) {
        type = _MatchType.exact;
        score = 1.0;
      } else if (sv == '—' || cv == '—') {
        type = _MatchType.conflict;
        score = 0.0;
      } else {
        // Simple similarity: length-overlap ratio
        final shorter = sv.length < cv.length ? sv : cv;
        final longer  = sv.length >= cv.length ? sv : cv;
        final overlap = shorter.split('').where(longer.contains).length;
        score = longer.isEmpty ? 0.0 : (overlap / longer.length).clamp(0.0, 1.0);
        type = score >= 0.8 ? _MatchType.fuzzy : _MatchType.conflict;
      }

      return _FieldComparison(
        fieldName: s?.displayName ?? c?.displayName ?? key,
        sourceValue: sv,
        candidateValue: cv,
        matchType: type,
        score: score,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    setState(() {
      _fields = comparisons;
      // Update entity names now that we have real data
      if (src != null) {
        _source = _ReviewRecord(
          entityName: src.displayName,
          entityId: src.id,
          sourceSystem: src.sourceSystems.firstOrNull ?? '—',
          type: src.type.name,
        );
      }
      if (cand != null) {
        _candidate = _ReviewRecord(
          entityName: cand.displayName,
          entityId: cand.id,
          sourceSystem: cand.sourceSystems.firstOrNull ?? '—',
          type: cand.type.name,
        );
      }
      _fieldsLoading = false;
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Color _scoreColor(double score) {
    if (score >= 0.85) return AppColors.primary;
    if (score >= 0.65) return AppColors.warning;
    return AppColors.error;
  }

  Widget _matchIcon(_MatchType type) {
    switch (type) {
      case _MatchType.exact:
        return const Text('✅', style: TextStyle(fontSize: 14));
      case _MatchType.fuzzy:
        return const Text('≈', style: TextStyle(fontSize: 16, color: AppColors.warning));
      case _MatchType.conflict:
        return const Text('🔴', style: TextStyle(fontSize: 13));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildTopScoreHeader(),
          _buildAiBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildMainComparisonLayout(),
                ],
              ),
            ),
          ),
          _buildActionBar(),
        ],
      ),
    );
  }

  // ── Top score header ─────────────────────────
  Widget _buildTopScoreHeader() {
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
            tooltip: 'Back to queue',
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Match Review', style: AppTextStyles.titleMedium),
              Text(
                'ID: ${widget.matchId}',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          // Overall score circle
          _OverallScoreIndicator(score: _overallScore),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pending_actions_rounded, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text('Pending Review', style: AppTextStyles.labelSmall.copyWith(color: AppColors.warning)),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.aiPurple.withValues(alpha: 0.18),
            AppColors.aiPurpleDark.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.aiPurple.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.purpleGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _aiConfidence > 0
                          ? 'AI Confidence: ${(_aiConfidence * 100).toStringAsFixed(1)}%'
                          : 'AI Analysis',
                      style: AppTextStyles.titleSmall.copyWith(color: AppColors.aiPurple),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'RECOMMEND MERGE',
                        style: AppTextStyles.badgeLabel.copyWith(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _aiExplanation,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => _triggerAiExplain(),
            icon: Icon(
              _isLoadingAi ? Icons.hourglass_empty : Icons.lightbulb_outline,
              size: 14,
              color: AppColors.aiPurple,
            ),
            label: Text(
              _isLoadingAi ? 'Thinking...' : 'Explain further',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.aiPurple),
            ),
          ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0);
  }

  Future<void> _triggerAiExplain() async {
    setState(() => _isLoadingAi = true);
    final prompt =
        'Briefly explain why "${_source.entityName}" (${_source.sourceSystem}) '
        'and "${_candidate.entityName}" (${_candidate.sourceSystem}) are a '
        '${(_overallScore * 100).toStringAsFixed(0)}% match. '
        'Focus on the key matching factors in 2-3 sentences.';
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        '/v1/copilot',
        data: {'message': prompt},
      );
      if (!mounted) return;
      final data = resp.data;
      final answer = data?['answer'] as String? ??
          data?['response'] as String? ??
          _aiExplanation;
      setState(() {
        _aiExplanation = answer;
        _isLoadingAi = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingAi = false);
    }
  }

  // ── Main 2-Column Layout ─────────────────────
  Widget _buildMainComparisonLayout() {
    return Column(
      children: [
        // Column headers
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                label: 'Source Record',
                system: _source.sourceSystem,
                icon: Icons.upload_file_outlined,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 80),
            Expanded(
              child: _SectionHeader(
                label: 'Candidate Record',
                system: _candidate.sourceSystem,
                icon: Icons.download_outlined,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Entity identity row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _EntityCard(record: _source)),
            const SizedBox(width: 80),
            Expanded(child: _EntityCard(record: _candidate)),
          ],
        ),
        const SizedBox(height: 24),

        // Field comparisons
        if (_fieldsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ..._fields.asMap().entries.map((e) {
            final i = e.key;
            final field = e.value;
            return _buildFieldRow(field, i).animate(delay: (i * 60 + 200).ms).fadeIn(duration: 350.ms).slideX(begin: 0.02, end: 0);
          }),
      ],
    );
  }

  Widget _buildFieldRow(_FieldComparison field, int index) {
    final color = _scoreColor(field.score);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Source value
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.fieldName.toUpperCase(),
                    style: AppTextStyles.tableHeader,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    field.sourceValue,
                    style: AppTextStyles.tableCell,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Score bar in the middle
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _matchIcon(field.matchType),
                const SizedBox(height: 6),
                Stack(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: field.score.clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${(field.score * 100).round()}%',
                  style: AppTextStyles.badgeLabel.copyWith(color: color),
                ),
              ],
            ),
          ),

          // Candidate value
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(color: AppColors.divider),
                  right: BorderSide(color: AppColors.divider),
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.fieldName.toUpperCase(),
                    style: AppTextStyles.tableHeader,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          field.candidateValue,
                          style: AppTextStyles.tableCell.copyWith(
                            color: field.matchType == _MatchType.conflict
                                ? AppColors.error
                                : AppColors.primaryText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Bar ───────────────────────────────
  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Add review notes (optional)...',
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
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              style: AppTextStyles.inputText,
            ),
          ),
          const SizedBox(width: 16),
          // Defer
          TextButton.icon(
            onPressed: _isSubmitting ? null : _handleDefer,
            icon: const Icon(Icons.schedule_rounded, size: 16),
            label: const Text('Defer'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryText,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(width: 8),
          // Reject
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _handleReject,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: AppTextStyles.buttonMedium,
            ),
          ),
          const SizedBox(width: 8),
          // Approve
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _handleApprove,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: Text(_isSubmitting ? 'Processing...' : 'Approve Merge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              textStyle: AppTextStyles.buttonMedium,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  void _handleApprove() async {
    setState(() => _isSubmitting = true);
    final repo = GetIt.instance<MatchRepository>();
    final notes = _notesController.text.trim();
    ApiResult<bool> result;
    if (_reviewItem != null) {
      result = await repo.approveReview(
        _reviewItem!.requestId,
        _reviewItem!.candidateId,
        notes: notes.isEmpty ? null : notes,
      );
    } else {
      result = await repo.approveMatch(widget.matchId);
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    final messenger = ScaffoldMessenger.of(context);
    if (result case Failure(:final exception)) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error: ${exception.message}', style: AppTextStyles.bodyMedium),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Text('Merge approved. Golden record created.', style: AppTextStyles.bodyMedium),
      ]),
      backgroundColor: AppColors.cardSurface,
      behavior: SnackBarBehavior.floating,
    ));
    context.pop();
  }

  void _handleReject() async {
    final repo = GetIt.instance<MatchRepository>();
    final notes = _notesController.text.trim();
    if (_reviewItem != null) {
      await repo.rejectReview(
        _reviewItem!.requestId,
        _reviewItem!.candidateId,
        notes: notes.isEmpty ? null : notes,
      );
    } else {
      await repo.rejectMatch(widget.matchId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Marked as not a duplicate.', style: AppTextStyles.bodyMedium),
      backgroundColor: AppColors.cardSurface,
      behavior: SnackBarBehavior.floating,
    ));
    context.pop();
  }

  void _handleDefer() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Review deferred for later.', style: AppTextStyles.bodyMedium),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.pop();
  }
}

// ──────────────────────────────────────────────
// Supporting Widgets
// ──────────────────────────────────────────────

class _OverallScoreIndicator extends StatelessWidget {
  final double score;
  const _OverallScoreIndicator({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 0.85
        ? AppColors.primary
        : score >= 0.65
            ? AppColors.warning
            : AppColors.error;

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 5,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeCap: StrokeCap.round,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(score * 100).round()}%',
                style: AppTextStyles.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                'match',
                style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String system;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.system,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.titleSmall),
            Text(system, style: AppTextStyles.bodySmall.copyWith(color: color)),
          ],
        ),
      ],
    );
  }
}

class _EntityCard extends StatelessWidget {
  final _ReviewRecord record;
  const _EntityCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.entityName,
                      style: AppTextStyles.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.entityId,
                        style: AppTextStyles.badgeLabel.copyWith(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.circle, size: 8, color: AppColors.secondaryText),
              const SizedBox(width: 6),
              Text(record.type, style: AppTextStyles.bodySmall),
              const SizedBox(width: 12),
              const Icon(Icons.storage_rounded, size: 12, color: AppColors.mutedText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  record.sourceSystem,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
