import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';

class StewardDashboardPage extends StatefulWidget {
  const StewardDashboardPage({super.key});

  @override
  State<StewardDashboardPage> createState() => _StewardDashboardPageState();
}

class _StewardDashboardPageState extends State<StewardDashboardPage> {
  bool _isLoading = true;
  String _displayName = '';
  List<String> _assignedTypes = [];
  List<_EntityTypeStat> _typeStats = [];
  int _pendingTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _displayName   = await AuthManager.getUserName() ?? '';
    _assignedTypes = await AuthManager.getAssignedEntityTypes();
    final client   = ApiClient();

    final stats = await Future.wait(
      _assignedTypes.map((code) => _fetchTypeStat(client, code)),
    );

    if (!mounted) return;
    setState(() {
      _isLoading    = false;
      _typeStats    = stats.whereType<_EntityTypeStat>().toList();
      _pendingTotal = _typeStats.fold(0, (acc, s) => acc + s.pendingReview);
    });
  }

  Future<_EntityTypeStat?> _fetchTypeStat(ApiClient client, String code) async {
    try {
      final r = await client.get<Map<String, dynamic>>(
        '/entities?type=$code&status=PendingReview&page=1&page_size=1',
      );
      final data = r.data;
      final pending = (data?['total'] as int?) ?? 0;

      final r2 = await client.get<Map<String, dynamic>>(
        '/entities?type=$code&page=1&page_size=1',
      );
      final data2 = r2.data;
      final total = (data2?['total'] as int?) ?? 0;

      return _EntityTypeStat(code: code, totalEntities: total, pendingReview: pending);
    } catch (_) {
      return _EntityTypeStat(code: code, totalEntities: 0, pendingReview: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    return _buildContent(context);
  }

  Widget _buildSkeleton() {
    Widget block(double h) => Container(
          height: h,
          decoration: BoxDecoration(
            color: AppColors.elevatedCard,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        block(36), const SizedBox(height: 8), block(16),
        const SizedBox(height: 32), block(200),
        const SizedBox(height: 24), block(160),
      ]),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        const SizedBox(height: 28),
        if (_pendingTotal > 0) ...[
          _buildAlertBanner(context),
          const SizedBox(height: 20),
        ],
        _buildEntityTypeCards(context),
        const SizedBox(height: 24),
        _buildQuickActions(context),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildHeader() {
    final first = _displayName.isNotEmpty ? _displayName.split(' ').first : 'Steward';
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: AppColors.purpleGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.manage_accounts_outlined, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Welcome, $first', style: AppTextStyles.headlineSmall),
        Text(
          _assignedTypes.isEmpty
              ? 'No entities assigned yet'
              : 'Managing ${_assignedTypes.length} entity ${_assignedTypes.length == 1 ? "type" : "types"}',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
      ]),
      const Spacer(),
      IconButton(
        onPressed: () { setState(() => _isLoading = true); _load(); },
        icon: const Icon(Icons.refresh_outlined),
        color: AppColors.secondaryText,
        tooltip: 'Refresh',
      ),
    ]).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildAlertBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/dashboard/match-queue'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.pending_actions_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(
            '$_pendingTotal ${_pendingTotal == 1 ? "record" : "records"} pending your review',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
          )),
          const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.warning, size: 14),
        ]),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.05, end: 0);
  }

  Widget _buildEntityTypeCards(BuildContext context) {
    if (_assignedTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(child: Column(children: [
          Icon(Icons.category_outlined, size: 48, color: AppColors.mutedText),
          const SizedBox(height: 12),
          Text('No entity types assigned', style: AppTextStyles.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Contact your administrator to get assigned to entity types.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
            textAlign: TextAlign.center,
          ),
        ])),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your Entity Types', style: AppTextStyles.titleSmall),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth > 700 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 130,
          ),
          itemCount: _typeStats.isNotEmpty ? _typeStats.length : _assignedTypes.length,
          itemBuilder: (context, i) {
            final stat = i < _typeStats.length
                ? _typeStats[i]
                : _EntityTypeStat(code: _assignedTypes[i], totalEntities: 0, pendingReview: 0);
            return _EntityTypeCard(stat: stat, onTap: () {
              context.go('/dashboard/entities?type=${stat.code}');
            }).animate(delay: (i * 60).ms).fadeIn(duration: 280.ms).slideY(begin: 0.1, end: 0);
          },
        );
      }),
    ]);
  }

  Widget _buildQuickActions(BuildContext context) {
    final typeParam = _assignedTypes.isEmpty ? '' : '?type=${_assignedTypes.first}';
    final actions = [
      _Action(Icons.pending_actions_outlined, 'Review Queue',
          'Pending records for your entities', () => context.go('/dashboard/match-queue')),
      _Action(Icons.list_alt_outlined, 'Browse Entities',
          'View all entities in your scope', () => context.go('/dashboard/entities$typeParam')),
      _Action(Icons.merge_outlined, 'Match Queue',
          'Review duplicate candidates', () => context.go('/dashboard/match-queue')),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quick Actions', style: AppTextStyles.titleSmall),
        const SizedBox(height: 16),
        ...actions.asMap().entries.map((e) => _ActionTile(action: e.value)
            .animate(delay: (e.key * 60).ms).fadeIn(duration: 240.ms)),
      ]),
    ).animate(delay: 200.ms).fadeIn(duration: 300.ms);
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _EntityTypeStat {
  final String code;
  final int totalEntities;
  final int pendingReview;
  const _EntityTypeStat({required this.code, required this.totalEntities, required this.pendingReview});
}

class _Action {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.subtitle, this.onTap);
}

// ─── Private widgets ──────────────────────────────────────────────────────────

class _EntityTypeCard extends StatelessWidget {
  final _EntityTypeStat stat;
  final VoidCallback onTap;
  const _EntityTypeCard({required this.stat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = stat.code
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: stat.pendingReview > 0 ? AppColors.warning.withValues(alpha: 0.5) : AppColors.divider,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.aiPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.category_outlined, color: AppColors.aiPurple, size: 18),
            ),
            const Spacer(),
            if (stat.pendingReview > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${stat.pendingReview} pending',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.warning),
                ),
              ),
          ]),
          const Spacer(),
          Text(displayName, style: AppTextStyles.titleSmall),
          const SizedBox(height: 2),
          Text(
            '${stat.totalEntities} total records',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText),
          ),
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final _Action action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(action.icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(action.label, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            Text(action.subtitle,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText)),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, size: 16, color: AppColors.mutedText),
        ]),
      ),
    );
  }
}
