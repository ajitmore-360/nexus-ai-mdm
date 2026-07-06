import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/models/api_responses.dart';
import '../../data/governance_repository.dart';

class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({super.key});

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage> {
  final _apiClient = ApiClient();
  late final GovernanceRepository _repo;

  bool _loading = true;
  String? _error;
  List<PendingApproval> _items = [];

  @override
  void initState() {
    super.initState();
    _repo = GovernanceRepository(_apiClient);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.listPendingApprovals();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Success<List<PendingApproval>>) {
        _items = result.data;
      } else if (result is Failure<List<PendingApproval>>) {
        _error = result.exception.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(children: [
          Text('Pending Approvals', style: AppTextStyles.titleMedium),
          if (_items.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_items.length}',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.warning),
              ),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _items.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('Failed to load approvals', style: AppTextStyles.bodyLarge),
        const SizedBox(height: 4),
        Text(_error!,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline,
            size: 56, color: AppColors.success),
        const SizedBox(height: 16),
        Text('All caught up!', style: AppTextStyles.titleSmall),
        const SizedBox(height: 4),
        Text('No entities pending approval.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText)),
      ]),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ApprovalCard(
        item: _items[i],
        onApprove: () => _approve(_items[i]),
        onReject: () => _showRejectDialog(_items[i]),
      ),
    );
  }

  Future<void> _approve(PendingApproval item) async {
    final result = await _repo.approveEntity(item.entityId);
    if (!mounted) return;
    if (result is Success<bool>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${item.entityTypeCode} record approved and published.'),
        backgroundColor: AppColors.success,
      ));
      _load();
    } else if (result is Failure<bool>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.exception.message),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _showRejectDialog(PendingApproval item) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Reject & Return to Steward',
            style: AppTextStyles.titleSmall),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Provide feedback so the Steward can revise the record.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Rejection notes…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: AppColors.surface,
            ),
            style: AppTextStyles.bodyMedium,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final result =
        await _repo.rejectEntity(item.entityId, ctrl.text.trim());
    if (!mounted) return;
    if (result is Success<bool>) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Record returned to Steward for revision.'),
        backgroundColor: Colors.grey,
      ));
      _load();
    } else if (result is Failure<bool>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.exception.message),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

// ── Approval card ─────────────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  final PendingApproval item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final submittedStr = _formatDate(item.submittedAt);

    return Card(
      color: AppColors.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.entityTypeCode,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.warning),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Pending Review',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.primary),
                ),
              ),
              const Spacer(),
              Text(submittedStr,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.secondaryText),
              const SizedBox(width: 4),
              Text('Submitted by: ${item.submitterDisplay}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ]),
            if (item.changeSummary != null &&
                item.changeSummary!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_outlined,
                        size: 14, color: AppColors.secondaryText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.changeSummary!,
                          style: AppTextStyles.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve & Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.navyBackground,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

