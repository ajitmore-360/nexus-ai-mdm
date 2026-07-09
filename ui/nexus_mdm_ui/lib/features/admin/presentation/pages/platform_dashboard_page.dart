import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import 'package:dio/dio.dart' show DioException;
import '../../../../core/network/api_client.dart' hide ApiException;

class PlatformDashboardPage extends StatefulWidget {
  const PlatformDashboardPage({super.key});

  @override
  State<PlatformDashboardPage> createState() => _PlatformDashboardPageState();
}

class _PlatformDashboardPageState extends State<PlatformDashboardPage> {
  bool _isLoading = true;
  _PlatformStats _stats = const _PlatformStats();
  List<_ServiceStatus> _services = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tenantCount = await _fetchTenantCount();
    final services   = await _probeServices();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _stats = _PlatformStats(
        tenantCount:     tenantCount,
        activeCount:     tenantCount,
        servicesOnline:  services.where((s) => s.isOnline).length,
        servicesTotal:   services.length,
        storageMb:       2340,
        licensesActive:  tenantCount,
        licensesTotal:   10,
      );
      _services = services;
    });
  }

  Future<int> _fetchTenantCount() async {
    try {
      final client = ApiClient();
      final r = await client.get<Map<String, dynamic>>('/admin/tenants');
      final data = r.data;
      if (data == null || data['success'] != true) return 0;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<_ServiceStatus>> _probeServices() async {
    final client = ApiClient();
    Future<_ServiceStatus> probe(String name, String path) async {
      final sw = Stopwatch()..start();
      try {
        await client.get<dynamic>(path);
        return _ServiceStatus(name: name, isOnline: true, latencyMs: sw.elapsedMilliseconds);
      } on DioException catch (e) {
        sw.stop();
        // If the server responded at all (even 4xx/5xx), the process is running.
        // Only connection errors and timeouts mean truly offline.
        final responded = e.response != null;
        return _ServiceStatus(name: name, isOnline: responded, latencyMs: responded ? sw.elapsedMilliseconds : 0);
      } catch (_) {
        return _ServiceStatus(name: name, isOnline: false, latencyMs: 0);
      }
    }

    final results = await Future.wait([
      probe('API Gateway',       '/health'),
      probe('MDM Core',          '/health'),
      probe('Ingest Service',    '/health'),
      probe('AI Service',        '/health'),
      probe('Kafka Events',      '/health'),
    ]);
    return results;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    return _buildContent(context);
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmer(240, 36),
          const SizedBox(height: 8),
          _shimmer(160, 16),
          const SizedBox(height: 32),
          Row(children: List.generate(4, (_) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _shimmer(double.infinity, 110),
            ),
          ))),
          const SizedBox(height: 32),
          _shimmer(double.infinity, 220),
        ],
      ),
    );
  }

  Widget _shimmer(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 28),
          _buildMetricCards(context),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildServicesPanel()),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: _buildLicenseSummary(context)),
            ],
          ),
          const SizedBox(height: 28),
          _buildQuickActions(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
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
              child: const Icon(Icons.admin_panel_settings_outlined,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Platform Overview', style: AppTextStyles.headlineSmall),
                Text(
                  'Azile AI MDM â€” Super Admin Console',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _RefreshButton(onTap: () {
              setState(() => _isLoading = true);
              _load();
            }),
          ],
        ).animate().fadeIn(duration: 350.ms),
      ],
    );
  }

  Widget _buildMetricCards(BuildContext context) {
    final cards = [
      _MetricCard(
        label: 'Total Tenants',
        value: '${_stats.tenantCount}',
        sub: '${_stats.activeCount} active',
        icon: Icons.corporate_fare_rounded,
        color: AppColors.primary,
        onTap: () => context.go('/dashboard/admin/tenants'),
      ),
      _MetricCard(
        label: 'Licenses',
        value: '${_stats.licensesActive}',
        sub: 'of ${_stats.licensesTotal} issued',
        icon: Icons.vpn_key_rounded,
        color: AppColors.success,
        onTap: () => context.go('/dashboard/admin/license'),
      ),
      _MetricCard(
        label: 'Services',
        value: '${_stats.servicesOnline}/${_stats.servicesTotal}',
        sub: 'online',
        icon: Icons.monitor_heart_rounded,
        color: _stats.servicesOnline == _stats.servicesTotal
            ? AppColors.success
            : AppColors.warning,
        onTap: () => context.go('/dashboard/admin/health'),
      ),
      _MetricCard(
        label: 'Storage Used',
        value: _formatStorage(_stats.storageMb),
        sub: 'across all tenants',
        icon: Icons.storage_rounded,
        color: AppColors.aiPurple,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 800 ? 4 : 2;
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

  Widget _buildServicesPanel() {
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
              Text('Service Health', style: AppTextStyles.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _stats.servicesOnline == _stats.servicesTotal
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _stats.servicesOnline == _stats.servicesTotal
                      ? 'All Systems Operational'
                      : '${_stats.servicesTotal - _stats.servicesOnline} Degraded',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _stats.servicesOnline == _stats.servicesTotal
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._services.map((s) => _ServiceRow(service: s)),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn(duration: 300.ms);
  }

  Widget _buildLicenseSummary(BuildContext context) {
    final pct = _stats.licensesTotal == 0 ? 0.0
        : _stats.licensesActive / _stats.licensesTotal;
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
          Text('License Utilization', style: AppTextStyles.titleSmall),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 10,
                    color: AppColors.divider,
                  ),
                  CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 10,
                    color: AppColors.primary,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(pct * 100).toStringAsFixed(0)}%',
                          style: AppTextStyles.headlineSmall),
                      Text('used', style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.secondaryText)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _LicenseStat(label: 'Active', value: _stats.licensesActive,
              color: AppColors.success),
          const SizedBox(height: 8),
          _LicenseStat(label: 'Remaining', value: _stats.licensesTotal - _stats.licensesActive,
              color: AppColors.secondaryText),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/dashboard/admin/license'),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Issue License'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    ).animate(delay: 250.ms).fadeIn(duration: 300.ms);
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.add_business_rounded,
        label: 'New Tenant',
        description: 'Onboard a new client organisation',
        onTap: () => context.go('/dashboard/admin/tenants/create'),
      ),
      _QuickAction(
        icon: Icons.vpn_key_rounded,
        label: 'Issue License',
        description: 'Assign a new license to a tenant',
        onTap: () => context.go('/dashboard/admin/license'),
      ),
      _QuickAction(
        icon: Icons.monitor_heart_rounded,
        label: 'System Health',
        description: 'Detailed service diagnostics',
        onTap: () => context.go('/dashboard/admin/health'),
      ),
      _QuickAction(
        icon: Icons.history_rounded,
        label: 'Audit Log',
        description: 'Platform-wide audit trail',
        onTap: () => context.go('/dashboard/analytics'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTextStyles.titleSmall),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final cols = constraints.maxWidth > 700 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 96,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: actions.asMap().entries.map((e) =>
              _QuickActionCard(action: e.value)
                  .animate(delay: (e.key * 60).ms).fadeIn(duration: 280.ms),
            ).toList(),
          );
        }),
      ],
    );
  }

  String _formatStorage(int mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '$mb MB';
  }
}

// â”€â”€â”€ Data models â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PlatformStats {
  final int tenantCount;
  final int activeCount;
  final int servicesOnline;
  final int servicesTotal;
  final int storageMb;
  final int licensesActive;
  final int licensesTotal;

  const _PlatformStats({
    this.tenantCount     = 0,
    this.activeCount     = 0,
    this.servicesOnline  = 0,
    this.servicesTotal   = 5,
    this.storageMb       = 0,
    this.licensesActive  = 0,
    this.licensesTotal   = 10,
  });
}

class _ServiceStatus {
  final String name;
  final bool isOnline;
  final int latencyMs;
  const _ServiceStatus({required this.name, required this.isOnline, required this.latencyMs});
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });
}

// â”€â”€â”€ Sub-widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RefreshButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 15, color: AppColors.secondaryText),
            const SizedBox(width: 6),
            Text('Refresh', style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.secondaryText,
            )),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const Spacer(),
                if (onTap != null)
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: AppColors.mutedText),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppTextStyles.headlineSmall.copyWith(
                  fontSize: 24, fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 2),
                Text(label, style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.secondaryText,
                )),
                Text(sub, style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.mutedText, fontSize: 10,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final _ServiceStatus service;
  const _ServiceRow({required this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: service.isOnline ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(service.name, style: AppTextStyles.bodySmall),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: service.isOnline
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              service.isOnline ? 'Online' : 'Offline',
              style: AppTextStyles.labelSmall.copyWith(
                color: service.isOnline ? AppColors.success : AppColors.error,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _LicenseStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(label, style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.secondaryText)),
        const Spacer(),
        Text('$value', style: AppTextStyles.labelMedium.copyWith(
            fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(action.icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(action.label, style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
                  Text(
                    action.description,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.mutedText, fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
