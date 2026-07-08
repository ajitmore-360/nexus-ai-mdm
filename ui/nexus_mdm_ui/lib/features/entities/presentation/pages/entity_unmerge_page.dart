import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EntityUnmergePage extends StatefulWidget {
  final String entityId;

  const EntityUnmergePage({super.key, required this.entityId});

  @override
  State<EntityUnmergePage> createState() => _EntityUnmergePageState();
}

class _EntityUnmergePageState extends State<EntityUnmergePage> {
  late final ApiClient _api;
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _historyLoading = true;
  String? _historyError;
  List<_UnmergeEvent> _history = [];

  bool _unmerging = false;
  List<String> _restoredIds = [];
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _loadHistory();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final resp = await _api.get<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/unmerge-history',
      );
      final items = (resp.data?['items'] as List<dynamic>?) ?? [];
      if (!mounted) return;
      setState(() {
        _history = items
            .map((e) => _UnmergeEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        _historyLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.response?.data?['message'] as String? ??
            'Failed to load unmerge history';
        _historyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Failed to load unmerge history';
        _historyLoading = false;
      });
    }
  }

  Future<void> _performUnmerge() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await _showConfirmDialog();
    if (!confirmed || !mounted) return;

    setState(() => _unmerging = true);

    try {
      final resp = await _api.post<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/unmerge',
        data: {'reason': _reasonController.text.trim()},
      );
      if (!mounted) return;
      final data = resp.data ?? {};
      final restored =
          (data['restored_entity_ids'] as List<dynamic>? ?? [])
              .cast<String>();
      setState(() {
        _unmerging = false;
        _restoredIds = restored;
        _showSuccess = true;
      });
      _reasonController.clear();
      await _loadHistory();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _unmerging = false);
      _showSnack(
        e.response?.data?['message'] as String? ?? 'Unmerge failed',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _unmerging = false);
      _showSnack('Unmerge failed', isError: true);
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 22),
                const SizedBox(width: 8),
                Text('Confirm Unmerge',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: AppColors.error)),
              ],
            ),
            content: Text(
              'This will restore the merged records as independent entities. '
              'This action is difficult to reverse. Are you sure?',
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Unmerge Entity'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppColors.primaryText,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Entity Unmerge / Split',
            style: AppTextStyles.titleMedium),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWarningBanner(),
            const SizedBox(height: 28),
            _buildHistorySection(),
            const SizedBox(height: 28),
            if (_showSuccess) ...[
              _buildSuccessCard(),
              const SizedBox(height: 28),
            ],
            _buildPerformSection(),
          ],
        ),
      ),
    );
  }

  // ── Warning banner ──────────────────────────────────────────────────────────

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.error.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Unmerging restores previously merged entities to independent '
              'records. This action cannot be easily undone.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ── Merge history ───────────────────────────────────────────────────────────

  Widget _buildHistorySection() {
    return _SectionCard(
      title: 'Merge History',
      icon: Icons.history_rounded,
      child: _historyLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _historyError != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Text(_historyError!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.error)),
                    ],
                  ),
                )
              : _history.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No previous unmerge events.',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.secondaryText)),
                    )
                  : Column(
                      children: _history
                          .map((e) => _buildHistoryTile(e))
                          .toList(),
                    ),
    );
  }

  Widget _buildHistoryTile(_UnmergeEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_rounded,
                  size: 15, color: AppColors.violetLight),
              const SizedBox(width: 6),
              Text('Unmerge Event',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.violetLight)),
              const Spacer(),
              Text(_formatDate(event.createdAt),
                  style: AppTextStyles.timestamp),
            ],
          ),
          const SizedBox(height: 8),
          if (event.reason.isNotEmpty) ...[
            Text('Reason: ${event.reason}',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              const Icon(Icons.people_outline,
                  size: 13, color: AppColors.secondaryText),
              const SizedBox(width: 4),
              Text(
                '${event.restoredEntityIds.length} entities restored',
                style: AppTextStyles.labelSmall,
              ),
              const SizedBox(width: 16),
              const Icon(Icons.person_outline,
                  size: 13, color: AppColors.secondaryText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Actor: ${event.actorId}',
                  style: AppTextStyles.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Success card ────────────────────────────────────────────────────────────

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Unmerge Successful — ${_restoredIds.length} entities restored',
                style: AppTextStyles.titleSmall
                    .copyWith(color: AppColors.success),
              ),
            ],
          ),
          if (_restoredIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _restoredIds
                  .map((id) => _EntityIdChip(entityId: id))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Perform unmerge ─────────────────────────────────────────────────────────

  Widget _buildPerformSection() {
    return _SectionCard(
      title: 'Perform Unmerge',
      icon: Icons.call_split_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Provide a reason for the unmerge. This will be recorded in the audit log.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                labelText: 'Reason *',
                hintText:
                    'e.g. Entities were incorrectly merged — different organisations',
                hintStyle: AppTextStyles.inputHint,
                isDense: true,
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.divider, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.divider, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'A reason is required'
                  : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: _unmerging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.call_split_rounded, size: 18),
                label: Text(
                  _unmerging ? 'Unmerging...' : 'Unmerge Entity',
                  style: AppTextStyles.buttonMedium
                      .copyWith(color: Colors.white),
                ),
                onPressed: _unmerging ? null : _performUnmerge,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}  '
          '${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Data model ──────────────────────────────────────────────────────────────

class _UnmergeEvent {
  final String unmergeId;
  final String reason;
  final List<String> restoredEntityIds;
  final String actorId;
  final String createdAt;

  const _UnmergeEvent({
    required this.unmergeId,
    required this.reason,
    required this.restoredEntityIds,
    required this.actorId,
    required this.createdAt,
  });

  factory _UnmergeEvent.fromJson(Map<String, dynamic> j) => _UnmergeEvent(
        unmergeId: j['unmerge_id'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        restoredEntityIds:
            (j['restored_entity_ids'] as List<dynamic>? ?? []).cast<String>(),
        actorId: j['actor_id'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: AppTextStyles.titleSmall),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _EntityIdChip extends StatelessWidget {
  final String entityId;

  const _EntityIdChip({required this.entityId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // Navigate to entity detail if router is available; otherwise no-op.
        // Callers can wrap this page in a GoRouter context and handle routing.
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              entityId.length > 12
                  ? '${entityId.substring(0, 8)}…'
                  : entityId,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.primary, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
