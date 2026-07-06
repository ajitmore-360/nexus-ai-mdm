import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';

class BusinessAdminDashboardPage extends StatefulWidget {
  const BusinessAdminDashboardPage({super.key});

  @override
  State<BusinessAdminDashboardPage> createState() =>
      _BusinessAdminDashboardPageState();
}

class _BusinessAdminDashboardPageState
    extends State<BusinessAdminDashboardPage> {
  bool _isLoading = true;
  String _displayName = '';
  String _tenantName  = '';
  int _userCount        = 0;
  int _sourceCount      = 0;
  int _entityTypeCount  = 0;
  List<_SourceInfo> _sources = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _displayName = await AuthManager.getUserName() ?? '';
    _tenantName  = await AuthManager.getTenantName() ?? '';
    final client = ApiClient();

    final results = await Future.wait([
      _fetchCount(client, '/admin/users'),
      _fetchCount(client, '/admin/source-systems'),
      _fetchCount(client, '/entity-types'),
      _fetchSources(client),
    ]);

    if (!mounted) return;
    setState(() {
      _isLoading       = false;
      _userCount       = results[0] as int;
      _sourceCount     = results[1] as int;
      _entityTypeCount = results[2] as int;
      _sources         = results[3] as List<_SourceInfo>;
    });
  }

  Future<int> _fetchCount(ApiClient client, String path) async {
    try {
      final r = await client.get<Map<String, dynamic>>(path);
      final data = r.data;
      if (data == null || data['success'] != true) return 0;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<_SourceInfo>> _fetchSources(ApiClient client) async {
    try {
      final r = await client.get<Map<String, dynamic>>('/admin/source-systems');
      final data = r.data;
      if (data == null || data['success'] != true) return [];
      final list = (data['data'] as List<dynamic>? ?? []);
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return _SourceInfo(
          name:      m['name']   as String? ?? m['source_system_code'] as String? ?? 'Unknown',
          code:      m['source_system_code'] as String? ?? '',
          isActive:  (m['is_active'] as bool?) ?? true,
          protocol:  m['protocol'] as String? ?? m['connection_type'] as String? ?? '—',
        );
      }).toList();
    } catch (_) {
      return [];
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
        const SizedBox(height: 32),
        Row(children: List.generate(3, (_) => Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 16), child: block(110))))),
        const SizedBox(height: 32), block(240),
      ]),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        const SizedBox(height: 28),
        _buildMetricCards(context),
        const SizedBox(height: 28),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildSourcesPanel()),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: _buildQuickActions(context)),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildHeader() {
    final first = _displayName.isNotEmpty ? _displayName.split(' ').first : 'Admin';
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.business_center_outlined, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Welcome, $first', style: AppTextStyles.headlineSmall),
        Text(
          _tenantName.isNotEmpty ? _tenantName : 'Tenant Administration',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
      ]),
      const Spacer(),
      _RefreshButton(onTap: () { setState(() => _isLoading = true); _load(); }),
    ]).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildMetricCards(BuildContext context) {
    final cards = [
      _MetricCard(
        label: 'Users',
        value: '$_userCount',
        sub: 'in this tenant',
        icon: Icons.people_outlined,
        color: AppColors.primary,
        onTap: () => context.go('/dashboard/org/users'),
      ),
      _MetricCard(
        label: 'Source Systems',
        value: '$_sourceCount',
        sub: '${_sources.where((s) => s.isActive).length} active',
        icon: Icons.electrical_services_outlined,
        color: AppColors.success,
        onTap: () => context.go('/dashboard/org/sources'),
      ),
      _MetricCard(
        label: 'Entity Types',
        value: '$_entityTypeCount',
        sub: 'configured',
        icon: Icons.category_outlined,
        color: AppColors.aiPurple,
        onTap: () => context.go('/dashboard/org/entity-types'),
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 600 ? 3 : 1;
      return GridView.count(
        crossAxisCount: cols,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 110,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cards.asMap().entries.map((e) =>
          e.value.animate(delay: (e.key * 70).ms).fadeIn(duration: 300.ms).slideY(begin: 0.12, end: 0),
        ).toList(),
      );
    });
  }

  Widget _buildSourcesPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Source Systems', style: AppTextStyles.titleSmall),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.go('/dashboard/org/sources'),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Manage'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_sources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Column(children: [
              Icon(Icons.electrical_services_outlined, color: AppColors.mutedText, size: 36),
              const SizedBox(height: 8),
              Text('No source systems configured yet',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/dashboard/org/sources'),
                child: const Text('Add Source System'),
              ),
            ])),
          )
        else
          ..._sources.map((s) => _SourceRow(source: s)),
      ]),
    ).animate(delay: 150.ms).fadeIn(duration: 300.ms);
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _Action(Icons.person_add_outlined,      'Invite User',            () => context.go('/dashboard/org/users')),
      _Action(Icons.add_link_outlined,         'Add Source System',      () => context.go('/dashboard/org/sources')),
      _Action(Icons.category_outlined,         'Configure Entity Types', () => context.go('/dashboard/org/entity-types')),
      _Action(Icons.shield_outlined,           'Data Governance Setup',  () => context.go('/dashboard/org/data-governance')),
      _Action(Icons.policy_outlined,           'Domain Policies',        () => context.go('/dashboard/org/domain-policies')),
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
        ...actions.asMap().entries.map((e) => _ActionRow(action: e.value)
            .animate(delay: (e.key * 60).ms).fadeIn(duration: 250.ms)),
      ]),
    ).animate(delay: 200.ms).fadeIn(duration: 300.ms);
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _SourceInfo {
  final String name;
  final String code;
  final bool isActive;
  final String protocol;
  const _SourceInfo({required this.name, required this.code, required this.isActive, required this.protocol});
}

class _Action {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.onTap);
}

// ─── Private widgets ──────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MetricCard({required this.label, required this.value, required this.sub,
      required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: AppTextStyles.titleLarge.copyWith(color: color)),
            Text(label, style: AppTextStyles.labelSmall),
            Text(sub, style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText)),
          ]),
        ]),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final _SourceInfo source;
  const _SourceRow({required this.source});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: source.isActive ? AppColors.success : AppColors.mutedText,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(source.name, style: AppTextStyles.bodySmall)),
        Text(source.protocol,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (source.isActive ? AppColors.success : AppColors.mutedText)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            source.isActive ? 'Active' : 'Inactive',
            style: AppTextStyles.labelSmall.copyWith(
                color: source.isActive ? AppColors.success : AppColors.mutedText),
          ),
        ),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final _Action action;
  const _ActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Icon(action.icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(action.label, style: AppTextStyles.bodySmall),
          const Spacer(),
          Icon(Icons.chevron_right, size: 16, color: AppColors.mutedText),
        ]),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RefreshButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.refresh_outlined),
      color: AppColors.secondaryText,
      tooltip: 'Refresh',
    );
  }
}
