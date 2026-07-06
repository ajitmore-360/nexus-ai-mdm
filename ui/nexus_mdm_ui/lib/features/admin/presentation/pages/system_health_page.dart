import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart' hide ApiException;

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key});

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  bool _isLoading = true;
  List<_ServiceHealth> _services = [];

  static const _serviceEndpoints = [
    ('API Gateway',      '/health'),
    ('MDM Core',         '/health'),
    ('Ingest Service',   '/health'),
    ('AI Service',       '/health'),
    ('Kafka Events',     '/health'),
    ('Notification Svc', '/health'),
  ];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    setState(() => _isLoading = true);
    final client = ApiClient();
    final results = await Future.wait(
      _serviceEndpoints.map((e) => _checkService(client, e.$1, e.$2)),
    );
    if (!mounted) return;
    setState(() {
      _services = results;
      _isLoading = false;
    });
  }

  Future<_ServiceHealth> _checkService(
      ApiClient client, String name, String path) async {
    final sw = Stopwatch()..start();
    try {
      await client.get<dynamic>(path);
      sw.stop();
      return _ServiceHealth(
        name: name, status: _Status.online, latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      final msg = e.toString();
      // 4xx / 200 still means service is reachable
      final reachable = msg.contains('DioException') && (
          msg.contains('400') || msg.contains('401') ||
          msg.contains('403') || msg.contains('404') || msg.contains('200'));
      return _ServiceHealth(
        name: name,
        status: reachable ? _Status.online : _Status.offline,
        latencyMs: sw.elapsedMilliseconds,
        error: reachable ? null : msg,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 28),
          if (_isLoading) _buildSkeleton() else _buildGrid(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final online = _services.where((s) => s.status == _Status.online).length;
    final total  = _services.length;
    final allOk  = !_isLoading && online == total && total > 0;
    final someDown = !_isLoading && online < total;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (allOk ? AppColors.success : someDown ? AppColors.warning : AppColors.cardSurface)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.monitor_heart_rounded,
            color: allOk ? AppColors.success : someDown ? AppColors.warning : AppColors.secondaryText,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Health', style: AppTextStyles.headlineSmall),
            if (!_isLoading)
              Text(
                allOk
                    ? 'All $total services operational'
                    : '$online / $total services online',
                style: AppTextStyles.bodySmall.copyWith(
                  color: allOk ? AppColors.success : AppColors.warning,
                ),
              ),
          ],
        ),
        const Spacer(),
        InkWell(
          onTap: _probe,
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
                Text('Re-probe', style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.secondaryText,
                )),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildSkeleton() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      mainAxisExtent: 140,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(6, (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
      )),
    );
  }

  Widget _buildGrid() {
    return GridView.count(
      crossAxisCount: _services.length >= 4 ? 3 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      mainAxisExtent: 140,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _services.asMap().entries.map((e) =>
        _ServiceCard(health: e.value)
            .animate(delay: (e.key * 60).ms)
            .fadeIn(duration: 280.ms)
            .slideY(begin: 0.1, end: 0),
      ).toList(),
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

enum _Status { online, offline, degraded }

class _ServiceHealth {
  final String name;
  final _Status status;
  final int latencyMs;
  final String? error;

  const _ServiceHealth({
    required this.name,
    required this.status,
    required this.latencyMs,
    this.error,
  });
}

// ─── Service card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final _ServiceHealth health;
  const _ServiceCard({required this.health});

  Color get _statusColor => switch (health.status) {
    _Status.online   => AppColors.success,
    _Status.offline  => AppColors.error,
    _Status.degraded => AppColors.warning,
  };

  String get _statusLabel => switch (health.status) {
    _Status.online   => 'Online',
    _Status.offline  => 'Offline',
    _Status.degraded => 'Degraded',
  };

  IconData get _statusIcon => switch (health.status) {
    _Status.online   => Icons.check_circle_rounded,
    _Status.offline  => Icons.cancel_rounded,
    _Status.degraded => Icons.warning_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: health.status == _Status.online
              ? AppColors.divider
              : _statusColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor, size: 18),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _statusColor, fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(health.name, style: AppTextStyles.titleSmall),
              const SizedBox(height: 4),
              if (health.status == _Status.online)
                Text(
                  'Latency: ${health.latencyMs} ms',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                )
              else
                Text(
                  health.error?.split('\n').first ?? 'Unreachable',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
