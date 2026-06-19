import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/distribution_repository.dart' show DistributionRepository, DistributionJob;

// ──────────────────────────────────────────────────────────────────────────────
// Domain models
// ──────────────────────────────────────────────────────────────────────────────

enum _JobStatus { pending, running, completed, failed, cancelled }

extension _JobStatusMeta on _JobStatus {
  String get label {
    switch (this) {
      case _JobStatus.pending:   return 'Pending';
      case _JobStatus.running:   return 'Running';
      case _JobStatus.completed: return 'Completed';
      case _JobStatus.failed:    return 'Failed';
      case _JobStatus.cancelled: return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case _JobStatus.pending:   return AppColors.warning;
      case _JobStatus.running:   return AppColors.info;
      case _JobStatus.completed: return AppColors.primary;
      case _JobStatus.failed:    return AppColors.error;
      case _JobStatus.cancelled: return AppColors.mutedText;
    }
  }

  IconData get icon {
    switch (this) {
      case _JobStatus.pending:   return Icons.hourglass_empty_rounded;
      case _JobStatus.running:   return Icons.sync_rounded;
      case _JobStatus.completed: return Icons.check_circle_rounded;
      case _JobStatus.failed:    return Icons.error_rounded;
      case _JobStatus.cancelled: return Icons.cancel_rounded;
    }
  }
}

class _DistributionJob {
  final String id;
  final _JobStatus status;
  final String connector;
  final String connectorIcon;
  final String entityType;
  final String entityId;
  final String entityName;
  final int progress;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int retryCount;
  final int recordCount;

  const _DistributionJob({
    required this.id,
    required this.status,
    required this.connector,
    required this.connectorIcon,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    required this.progress,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
    this.retryCount = 0,
    required this.recordCount,
  });
}


// ──────────────────────────────────────────────────────────────────────────────
// Page
// ──────────────────────────────────────────────────────────────────────────────

class DistributionMonitorPage extends StatefulWidget {
  const DistributionMonitorPage({super.key});

  @override
  State<DistributionMonitorPage> createState() => _DistributionMonitorPageState();
}

class _DistributionMonitorPageState extends State<DistributionMonitorPage> {
  bool _isLoading = true;
  List<_DistributionJob> _jobs = [];
  String _activeFilter = 'all';
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = GetIt.instance<DistributionRepository>();
    final result = await repo.getJobs();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result case Success(:final data)) {
        _jobs = data.map(_toPageJob).toList();
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    final repo = GetIt.instance<DistributionRepository>();
    final result = await repo.getJobs();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isRefreshing = false;
      if (result case Success(:final data)) {
        _jobs = data.map(_toPageJob).toList();
      }
    });
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Distribution queue refreshed'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.cardSurface,
      ),
    );
  }

  _DistributionJob _toPageJob(DistributionJob job) {
    final status = switch (job.status.toLowerCase()) {
      'running'   => _JobStatus.running,
      'completed' => _JobStatus.completed,
      'failed'    => _JobStatus.failed,
      'cancelled' || 'canceled' => _JobStatus.cancelled,
      _           => _JobStatus.pending,
    };
    final connId = job.connectorId;
    final icon = connId.length >= 3
        ? connId.substring(0, 3).toUpperCase()
        : connId.toUpperCase();
    return _DistributionJob(
      id: job.id,
      status: status,
      connector: connId,
      connectorIcon: icon,
      entityType: job.entityType,
      entityId: job.entityId,
      entityName: job.entityId,
      progress: status == _JobStatus.completed
          ? 100
          : status == _JobStatus.running
              ? 50
              : 0,
      errorMessage: job.errorMessage,
      createdAt: job.createdAt,
      completedAt: job.completedAt,
      retryCount: (job.attempts - 1).clamp(0, 99),
      recordCount: 1,
    );
  }

  void _retryJob(_DistributionJob job) {
    setState(() {
      final idx = _jobs.indexWhere((j) => j.id == job.id);
      if (idx != -1) {
        _jobs[idx] = _DistributionJob(
          id: job.id,
          status: _JobStatus.pending,
          connector: job.connector,
          connectorIcon: job.connectorIcon,
          entityType: job.entityType,
          entityId: job.entityId,
          entityName: job.entityName,
          progress: 0,
          createdAt: job.createdAt,
          retryCount: job.retryCount + 1,
          recordCount: job.recordCount,
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Job ${job.id} queued for retry'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.cardSurface,
      ),
    );
  }

  void _cancelJob(_DistributionJob job) {
    setState(() {
      final idx = _jobs.indexWhere((j) => j.id == job.id);
      if (idx != -1) {
        _jobs[idx] = _DistributionJob(
          id: job.id,
          status: _JobStatus.cancelled,
          connector: job.connector,
          connectorIcon: job.connectorIcon,
          entityType: job.entityType,
          entityId: job.entityId,
          entityName: job.entityName,
          progress: 0,
          createdAt: job.createdAt,
          retryCount: job.retryCount,
          recordCount: job.recordCount,
        );
      }
    });
  }

  List<_DistributionJob> get _filtered {
    if (_activeFilter == 'all') return _jobs;
    final status = switch (_activeFilter) {
      'running'   => _JobStatus.running,
      'pending'   => _JobStatus.pending,
      'completed' => _JobStatus.completed,
      'failed'    => _JobStatus.failed,
      _           => null,
    };
    if (status == null) return _jobs;
    return _jobs.where((j) => j.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pending   = _jobs.where((j) => j.status == _JobStatus.pending).length;
    final running   = _jobs.where((j) => j.status == _JobStatus.running).length;
    final completed = _jobs.where((j) => j.status == _JobStatus.completed).length;
    final failed    = _jobs.where((j) => j.status == _JobStatus.failed).length;
    final filtered  = _filtered;

    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildKpiBar(pending, running, completed, failed),
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? _buildShimmer()
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.send_outlined,
                        title: 'No distribution jobs',
                        description: 'No jobs match the current filter.',
                      )
                    : _buildList(filtered),
          ),
        ],
      ),
    );
  }

  // ── KPI Bar ──────────────────────────────────────────────────────────────────

  Widget _buildKpiBar(int pending, int running, int completed, int failed) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          _StatTile(label: 'Pending', value: '$pending', color: AppColors.warning, icon: Icons.hourglass_empty_rounded)
              .animate().fadeIn(duration: 300.ms),
          const SizedBox(width: 12),
          _StatTile(label: 'Running', value: '$running', color: AppColors.info, icon: Icons.sync_rounded)
              .animate(delay: 60.ms).fadeIn(duration: 300.ms),
          const SizedBox(width: 12),
          _StatTile(label: 'Completed Today', value: '$completed', color: AppColors.primary, icon: Icons.check_circle_rounded)
              .animate(delay: 120.ms).fadeIn(duration: 300.ms),
          const SizedBox(width: 12),
          _StatTile(label: 'Failed Today', value: '$failed', color: AppColors.error, icon: Icons.error_rounded)
              .animate(delay: 180.ms).fadeIn(duration: 300.ms),
          const Spacer(),
          // Refresh button
          OutlinedButton.icon(
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_isRefreshing ? 'Refreshing…' : 'Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondaryText,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: AppTextStyles.buttonSmall,
            ),
          ).animate(delay: 240.ms).fadeIn(duration: 300.ms),
        ],
      ),
    );
  }

  // ── Filter Bar ───────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    final filters = <(String, String)>[
      ('All',       'all'),
      ('Running',   'running'),
      ('Pending',   'pending'),
      ('Completed', 'completed'),
      ('Failed',    'failed'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          ...filters.map((f) {
            final isActive = _activeFilter == f.$2;
            final count = f.$2 == 'all'
                ? _jobs.length
                : _jobs.where((j) => j.status.name == f.$2).length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => setState(() => _activeFilter = f.$2),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.elevatedCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? AppColors.primary.withValues(alpha: 0.35) : AppColors.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.$1,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isActive ? AppColors.primary : AppColors.secondaryText,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count',
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: isActive ? AppColors.primary : AppColors.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── List ─────────────────────────────────────────────────────────────────────

  Widget _buildList(List<_DistributionJob> jobs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildJobCard(jobs[i], i),
    );
  }

  Widget _buildJobCard(_DistributionJob job, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: job.status == _JobStatus.failed
              ? AppColors.error.withValues(alpha: 0.3)
              : job.status == _JobStatus.running
                  ? AppColors.info.withValues(alpha: 0.25)
                  : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Connector badge
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Center(
                  child: Text(
                    job.connectorIcon,
                    style: AppTextStyles.badgeLabel.copyWith(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Job info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(job.connector, style: AppTextStyles.titleSmall),
                        const SizedBox(width: 8),
                        _StatusChip(status: job.status),
                        if (job.retryCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Retry ${job.retryCount}',
                              style: AppTextStyles.badgeLabel.copyWith(
                                color: AppColors.warning,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          job.entityName,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.primaryText),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·  ${job.entityType}',
                          style: AppTextStyles.bodySmall,
                        ),
                        if (job.recordCount > 1) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(${job.recordCount} records)',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Timestamp + ID
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(job.id, style: AppTextStyles.timestamp.copyWith(color: AppColors.mutedText)),
                  const SizedBox(height: 2),
                  Text(
                    _relativeTime(job.createdAt),
                    style: AppTextStyles.timestamp,
                  ),
                ],
              ),
            ],
          ),

          // Progress bar (running only)
          if (job.status == _JobStatus.running) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: (job.progress / 100).clamp(0.0, 1.0),
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            gradient: AppColors.blueGradient,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.info.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${job.progress}%',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.info),
                ),
              ],
            ),
          ],

          // Error message (failed only)
          if (job.status == _JobStatus.failed && job.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.errorMessage!,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Actions (failed → retry; pending/running → cancel)
          if (job.status == _JobStatus.failed || job.status == _JobStatus.pending || job.status == _JobStatus.running) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (job.status == _JobStatus.failed)
                  ElevatedButton.icon(
                    onPressed: () => _retryJob(job),
                    icon: const Icon(Icons.replay_rounded, size: 14),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning.withValues(alpha: 0.12),
                      foregroundColor: AppColors.warning,
                      elevation: 0,
                      side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      textStyle: AppTextStyles.buttonSmall,
                    ),
                  ),
                if (job.status == _JobStatus.pending || job.status == _JobStatus.running) ...[
                  TextButton.icon(
                    onPressed: () => _cancelJob(job),
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      textStyle: AppTextStyles.buttonSmall,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    )
        .animate(delay: (index * 55).ms)
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.04, end: 0, duration: 350.ms);
  }

  Widget _buildShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => LoadingShimmer(
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Supporting Widgets
// ──────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppTextStyles.titleSmall.copyWith(color: color)),
              Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _JobStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == _JobStatus.running)
            const _SpinningIcon()
          else
            Icon(status.icon, size: 10, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label.toUpperCase(),
            style: AppTextStyles.badgeLabel.copyWith(color: status.color, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon();

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: const Icon(Icons.sync_rounded, size: 10, color: AppColors.info),
    );
  }
}
