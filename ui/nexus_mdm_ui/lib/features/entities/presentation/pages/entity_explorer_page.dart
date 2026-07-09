import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../shared/models/entity.dart';
import '../../../../shared/models/api_responses.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/trust_score_bar.dart';
import '../../../../shared/widgets/entity_avatar.dart';
import '../../../../shared/widgets/loading_shimmer.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../entities/data/entity_repository.dart' show EntityRepository, EntityPage;

class EntityExplorerPage extends StatefulWidget {
  final bool isCreateMode;

  const EntityExplorerPage({super.key, this.isCreateMode = false});

  @override
  State<EntityExplorerPage> createState() => _EntityExplorerPageState();
}

class _EntityExplorerPageState extends State<EntityExplorerPage> {
  late final EntityRepository _repository;
  final _searchController = TextEditingController();
  final _aiQueryController = TextEditingController();
  Timer? _searchDebounce;
  bool _isLoading = true;
  List<CanonicalEntity> _filteredEntities = [];

  String? _selectedType;
  String? _selectedStatus;
  String? _selectedSource;
  Set<String> _selectedIds = {};
  int _currentPage = 1;
  static const int _pageSize = AppConstants.defaultPageSize;
  bool _isAiQuerying = false;
  final Set<String> _hiddenColumns = {};
  EntityPage? _lastEntityPage;

  // Sort state â€” column key matches backend allowlist + asc/desc toggle
  String _sortBy  = 'created_at';
  bool   _sortAsc = false; // false = DESC (newest first default)

  // BL-044: Steward-scoped type filter
  List<String>? _stewardEntityTypes; // null = no restriction, [] = error/empty

  // Role â€” used to show/hide governance actions
  String? _userRole;
  bool _isBulkActioning = false;

  @override
  void initState() {
    super.initState();
    _repository = EntityRepository(ApiClient());
    _initRoleAndTypes();
  }

  Future<void> _initRoleAndTypes() async {
    final role = await AuthManager.getUserRole();
    if (mounted) setState(() => _userRole = role?.toLowerCase());
    if (role?.toLowerCase() == 'steward') {
      await _loadStewardTypes();
    }
    _loadEntities();
  }

  bool get _canApproveEntities =>
      _userRole == 'admin' ||
      _userRole == 'business_admin' ||
      _userRole == 'steward';

  Future<void> _loadStewardTypes() async {
    final types = await AuthManager.getAssignedEntityTypes();
    if (!mounted) return;
    setState(() {
      _stewardEntityTypes = types;
      // Auto-select the sole type so the first query is already scoped
      if (types.length == 1) _selectedType = types.first;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _aiQueryController.dispose();
    super.dispose();
  }

  Future<void> _loadEntities() async {
    setState(() => _isLoading = true);

    // Steward scope: if no explicit type chosen and steward has exactly one type,
    // enforce it on the query so the backend never returns out-of-scope records.
    final effectiveType = _selectedType?.toLowerCase() ??
        (_stewardEntityTypes?.length == 1
            ? _stewardEntityTypes!.first.toLowerCase()
            : null);

    final result = await _repository.getEntities(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      type: effectiveType,
      status: _selectedStatus?.toLowerCase(),
      sourceSystem: _selectedSource,
      sortBy:  _sortBy,
      sortDir: _sortAsc ? 'asc' : 'desc',
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      switch (result) {
        case Success<EntityPage>(:final data):
          var items = data.items;
          // Safety net for multi-type stewards when "All" is selected:
          // backend has no multi-type param so we filter client-side.
          if (_stewardEntityTypes != null &&
              _stewardEntityTypes!.length > 1 &&
              _selectedType == null) {
            final allowed =
                _stewardEntityTypes!.map((t) => t.toLowerCase()).toSet();
            items = items
                .where((e) => allowed.contains(e.type.name.toLowerCase()))
                .toList();
          }
          _filteredEntities = items;
          _lastEntityPage = data;
        case Failure<EntityPage>(:final exception):
          _filteredEntities = [];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to load entities: ${exception.message}'),
                backgroundColor: AppColors.error,
              ));
            }
          });
      }
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _applyFilters);
  }

  void _applyFilters() {
    setState(() => _currentPage = 1);
    _loadEntities();
  }

  Future<void> _submitAiQuery() async {
    final query = _aiQueryController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isAiQuerying = true);
    try {
      final client = ApiClient();
      final resp = await client.post<Map<String, dynamic>>(
        '/v1/prism',
        data: {
          'message': 'Extract entity search filters from this query as JSON with '
              'optional keys: type (one of ${AppConstants.entityTypes.join(", ")}), '
              'status (active/inactive/pending/merged), search (keyword). '
              'Query: "$query". Respond with JSON only.',
        },
      );
      if (!mounted) return;
      final answer = resp.data?['answer'] as String? ?? '';
      // Best-effort type extraction from AI response
      final lowerAnswer = answer.toLowerCase();
      String? inferredType;
      final searchableTypes = (_stewardEntityTypes?.isNotEmpty == true)
          ? _stewardEntityTypes!
          : AppConstants.entityTypes;
      for (final t in searchableTypes) {
        if (lowerAnswer.contains(t.toLowerCase())) {
          inferredType = t;
          break;
        }
      }
      setState(() {
        _isAiQuerying = false;
        if (inferredType != null) _selectedType = inferredType;
      });
      _loadEntities();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('AI filtered results for: "$query"'),
        backgroundColor: AppColors.elevatedCard,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAiQuerying = false);
      _loadEntities();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToCreateEntity,
        icon: const Icon(Icons.add),
        label: const Text('New Entity'),
      ).animate(delay: 400.ms).fadeIn().scaleXY(begin: 0.8, end: 1.0),
      body: Column(
        children: [
          _buildToolbar(),
          _buildFilterRow(),
          if (_selectedIds.isNotEmpty) _buildBulkActionBar(),
          Expanded(
            child: _buildEntityTable(),
          ),
          _buildAiQueryBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search entities by name, ID, or attribute...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilters();
                        },
                      )
                    : null,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _exportToCsv(_filteredEntities),
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Export'),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showColumnDialog,
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Columns'),
          ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    // BL-044: restrict type chips to steward's assigned types when available
    final allowedTypes = _stewardEntityTypes;
    final baseTypes = allowedTypes != null && allowedTypes.isNotEmpty
        ? allowedTypes
        : AppConstants.entityTypes;
    // Single-type stewards don't need an "All Types" chip â€” it's redundant.
    final types = (_stewardEntityTypes?.length == 1)
        ? baseTypes.map<String?>((t) => t).toList()
        : [null, ...baseTypes];
    final statuses = [null, ...AppConstants.entityStatuses];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('Filter:', style: AppTextStyles.labelMedium.copyWith(color: AppColors.secondaryText)),
            const SizedBox(width: 12),

            // Type filter
            ...types.map((type) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(type ?? 'All Types'),
                    selected: _selectedType == type,
                    onSelected: (_) {
                      setState(() => _selectedType = type);
                      _applyFilters();
                    },
                    selectedColor: AppColors.darkGreen.withValues(alpha:0.3),
                    checkmarkColor: AppColors.primary,
                    labelStyle: AppTextStyles.chipLabel.copyWith(
                      color: _selectedType == type
                          ? AppColors.primary
                          : AppColors.secondaryText,
                    ),
                  ),
                )),

            Container(width: 1, height: 20, color: AppColors.divider),
            const SizedBox(width: 8),

            // Status filter
            ...statuses.take(4).map((status) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status ?? 'All Status'),
                    selected: _selectedStatus == status,
                    onSelected: (_) {
                      setState(() => _selectedStatus = status);
                      _applyFilters();
                    },
                    selectedColor: AppColors.darkGreen.withValues(alpha:0.3),
                    checkmarkColor: AppColors.primary,
                    labelStyle: AppTextStyles.chipLabel.copyWith(
                      color: _selectedStatus == status
                          ? AppColors.primary
                          : AppColors.secondaryText,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedIds.length} selected',
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          if (_canApproveEntities) ...[
            TextButton.icon(
              onPressed: _isBulkActioning ? null : _bulkApprove,
              icon: _isBulkActioning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
              label: const Text('Approve All'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
            ),
            TextButton.icon(
              onPressed: _isBulkActioning ? null : _bulkReject,
              icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
              label: const Text('Reject All'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            onPressed: _mergeTwoSelected,
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('Merge'),
          ),
          TextButton.icon(
            onPressed: _showTagDialog,
            icon: const Icon(Icons.label_outline, size: 16),
            label: const Text('Tag'),
          ),
          TextButton.icon(
            onPressed: () => _exportToCsv(
              _filteredEntities.where((e) => _selectedIds.contains(e.id)).toList(),
            ),
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Export'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text('Clear selection'),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkApprove() async {
    final ids = _selectedIds.toList();
    setState(() => _isBulkActioning = true);
    try {
      final result = await _repository.bulkApproveEntities(ids);
      if (!mounted) return;
      final succeeded = (result['succeeded'] as List?)?.length ?? 0;
      final skipped   = (result['skipped']   as List?)?.length ?? 0;
      final failed    = (result['failed']    as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Approved $succeeded, skipped $skipped'
            '${failed > 0 ? ', $failed failed' : ''}'),
        backgroundColor: failed > 0 ? AppColors.warning : AppColors.success,
      ));
      setState(() => _selectedIds.clear());
      _loadEntities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bulk approve failed: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _isBulkActioning = false);
    }
  }

  Future<void> _bulkReject() async {
    final ids = _selectedIds.toList();
    // Confirm before rejecting
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Reject selected entities'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Reviewer notes (optional)',
              hintText: 'Reason for rejectionâ€¦',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Reject All'),
            ),
          ],
        );
      },
    );
    if (notes == null || !mounted) return; // cancelled

    setState(() => _isBulkActioning = true);
    try {
      final result = await _repository.bulkRejectEntities(ids, reviewerNotes: notes);
      if (!mounted) return;
      final succeeded = (result['succeeded'] as List?)?.length ?? 0;
      final skipped   = (result['skipped']   as List?)?.length ?? 0;
      final failed    = (result['failed']    as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rejected $succeeded, skipped $skipped'
            '${failed > 0 ? ', $failed failed' : ''}'),
        backgroundColor: failed > 0 ? AppColors.warning : AppColors.error,
      ));
      setState(() => _selectedIds.clear());
      _loadEntities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bulk reject failed: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _isBulkActioning = false);
    }
  }

  Widget _buildEntityTable() {
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: const EntityListShimmer(count: 8),
      );
    }

    if (_filteredEntities.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No entities found',
        description: _searchController.text.isNotEmpty
            ? 'No entities match your search. Try different keywords.'
            : 'No entities yet. Create your first entity to get started.',
        actionLabel: 'Create Entity',
        onAction: _navigateToCreateEntity,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Header
          _buildTableHeader(),
          const Divider(color: AppColors.divider, height: 1),
          // Rows
          Expanded(
            child: ListView.separated(
              itemCount: _filteredEntities.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, i) =>
                  _buildEntityRow(_filteredEntities[i], i),
            ),
          ),
          // Pagination
          _buildPagination(),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  // â”€â”€ Sortable column header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Tapping a header column toggles direction if already active, or activates
  // it ascending.  Columns without a backend sort key (source) are non-sortable.

  Widget _sortHeader(String label, String? sortKey, {int flex = 2}) {
    final isActive = sortKey != null && _sortBy == sortKey;
    return Expanded(
      flex: flex,
      child: sortKey == null
          ? Text(label, style: AppTextStyles.tableHeader)
          : InkWell(
              onTap: () {
                setState(() {
                  if (_sortBy == sortKey) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortBy  = sortKey;
                    _sortAsc = false; // default DESC for a new column
                  }
                });
                _loadEntities();
              },
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.tableHeader.copyWith(
                      color: isActive ? AppColors.primary : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isActive
                        ? (_sortAsc
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded)
                        : Icons.unfold_more_rounded,
                    size: 14,
                    color: isActive
                        ? AppColors.primary
                        : AppColors.secondaryText,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Checkbox(
              value: _selectedIds.length == _filteredEntities.length &&
                  _filteredEntities.isNotEmpty,
              tristate: _selectedIds.isNotEmpty &&
                  _selectedIds.length < _filteredEntities.length,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIds =
                        _filteredEntities.map((e) => e.id).toSet();
                  } else {
                    _selectedIds.clear();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // NAME sorts by created_at (best server-side proxy without a name index)
          _sortHeader('NAME / ID', 'created_at', flex: 3),
          if (_colVisible('type'))
            _sortHeader('TYPE', 'entity_type'),
          if (_colVisible('status'))
            _sortHeader('STATUS', 'status'),
          if (_colVisible('trust'))
            _sortHeader('TRUST SCORE', 'trust_score', flex: 3),
          if (_colVisible('source'))
            _sortHeader('SOURCE', null), // source_system not in allowlist
          if (_colVisible('updated'))
            _sortHeader('UPDATED', 'updated_at'),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildEntityRow(CanonicalEntity entity, int index) {
    final isSelected = _selectedIds.contains(entity.id);

    return InkWell(
      onTap: () => context.go('/dashboard/entities/${entity.id}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppColors.primary.withValues(alpha:0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(entity.id);
                    } else {
                      _selectedIds.remove(entity.id);
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  EntityAvatar(
                    type: entity.type,
                    size: 36,
                    showGoldenRing: entity.isGolden,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entity.displayName,
                          style: AppTextStyles.tableCell.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          entity.id,
                          style: AppTextStyles.timestamp,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_colVisible('type'))
              Expanded(
                flex: 2,
                child: Text(entity.typeDisplayName, style: AppTextStyles.tableCell),
              ),
            if (_colVisible('status'))
              Expanded(flex: 2, child: StatusBadge(status: entity.status)),
            if (_colVisible('trust'))
              Expanded(flex: 3, child: TrustScoreBar(score: entity.trustScore)),
            if (_colVisible('source'))
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.primarySource,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primaryText),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entity.sourceSystems.length > 1)
                      Text('+${entity.sourceSystems.length - 1} more', style: AppTextStyles.timestamp),
                  ],
                ),
              ),
            if (_colVisible('updated'))
              Expanded(
                flex: 2,
                child: Text(_formatRelativeTime(entity.updatedAt), style: AppTextStyles.bodySmall),
              ),
            // Actions
            SizedBox(
              width: 40,
              child: PopupMenuButton<String>(
                onSelected: (value) =>
                    _handleRowAction(value, entity),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Text('View details'),
                  ),
                  const PopupMenuItem(
                    value: 'lineage',
                    child: Text('View lineage'),
                  ),
                  const PopupMenuItem(
                    value: 'match',
                    child: Text('Find matches'),
                  ),
                  const PopupMenuDivider(),
                  if (entity.status == EntityStatus.pending)
                    const PopupMenuItem(
                      value: 'submit_review',
                      child: Text('Submit for Review'),
                    ),
                  const PopupMenuItem(
                    value: 'merge',
                    child: Text('Merge'),
                  ),
                ],
                child: const Icon(Icons.more_vert,
                    size: 18, color: AppColors.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = _lastEntityPage?.totalPages ?? 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'Showing ${_filteredEntities.length} entities',
            style: AppTextStyles.bodySmall,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _currentPage > 1
                ? () { setState(() => _currentPage--); _loadEntities(); }
                : null,
            iconSize: 20,
          ),
          for (int i = 1; i <= totalPages.clamp(1, 5); i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildPageButton(i),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _currentPage < totalPages
                ? () { setState(() => _currentPage++); _loadEntities(); }
                : null,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(int page) {
    final isActive = page == _currentPage;
    return InkWell(
      onTap: () { setState(() => _currentPage = page); _loadEntities(); },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? null
              : Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text(
            '$page',
            style: AppTextStyles.labelMedium.copyWith(
              color: isActive
                  ? AppColors.navyBackground
                  : AppColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAiQueryBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppColors.purpleGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _aiQueryController,
              onSubmitted: (_) => _submitAiQuery(),
              decoration: InputDecoration(
                hintText:
                    'Ask AI: "Show me high-trust person entities from Salesforce with no conflicts"',
                hintStyle: AppTextStyles.inputHint.copyWith(fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              style: AppTextStyles.inputText.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          if (_isAiQuerying)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.aiPurple,
              ),
            )
          else
            IconButton(
              onPressed: _submitAiQuery,
              icon: const Icon(Icons.send_rounded,
                  size: 18, color: AppColors.aiPurple),
              tooltip: 'Submit AI query',
            ),
        ],
      ),
    );
  }

  void _handleRowAction(String action, CanonicalEntity entity) {
    switch (action) {
      case 'view':
        context.go('/dashboard/entities/${entity.id}');
        break;
      case 'lineage':
        context.go('/dashboard/lineage/${entity.id}');
        break;
      case 'match':
        context.go('/dashboard/match-queue');
        break;
      case 'merge':
        context.go('/dashboard/merge/${entity.id}/select');
        break;
      case 'submit_review':
        _submitForReview(entity);
        break;
    }
  }

  Future<void> _submitForReview(CanonicalEntity entity) async {
    try {
      final client = ApiClient();
      await client.post<Map<String, dynamic>>(
        '/v1/entities/${entity.id}/submit-for-review',
        data: {},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Entity submitted for review'),
        backgroundColor: AppColors.success,
      ));
      _loadEntities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to submit for review: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _navigateToCreateEntity() async {
    final created = await context.push<bool>('/dashboard/entities/create');
    if (created == true && mounted) {
      _loadEntities();
    }
  }

  bool _colVisible(String col) => !_hiddenColumns.contains(col);

  void _exportToCsv(List<CanonicalEntity> entities) {
    final buf = StringBuffer();
    buf.writeln('ID,Name,Type,Status,Trust Score,Primary Source,Updated');
    for (final e in entities) {
      final name = e.displayName.replaceAll('"', '""');
      buf.writeln('"${e.id}","$name","${e.type}","${e.status.name}",'
          '"${e.trustScore.toStringAsFixed(2)}","${e.primarySource}",'
          '"${e.updatedAt.toIso8601String()}"');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('CSV copied to clipboard'),
      backgroundColor: AppColors.success,
    ));
  }

  void _showColumnDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Column Visibility'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in const [
                ('type', 'Type'),
                ('status', 'Status'),
                ('trust', 'Trust Score'),
                ('source', 'Source'),
                ('updated', 'Updated'),
              ])
                CheckboxListTile(
                  title: Text(entry.$2),
                  value: _colVisible(entry.$1),
                  onChanged: (v) {
                    setLocal(() {});
                    setState(() {
                      if (v == true) {
                        _hiddenColumns.remove(entry.$1);
                      } else {
                        _hiddenColumns.add(entry.$1);
                      }
                    });
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _mergeTwoSelected() {
    if (_selectedIds.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select exactly 2 entities to merge'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    final ids = _selectedIds.toList();
    context.go('/dashboard/merge/${ids[0]}/${ids[1]}');
  }

  void _showTagDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Tag ${_selectedIds.length} entit${_selectedIds.length == 1 ? 'y' : 'ies'}',
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag value',
            hintText: 'e.g. priority, needs-review...',
          ),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            _applyTagToSelected(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _applyTagToSelected(ctrl.text.trim());
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyTagToSelected(String tag) async {
    if (tag.isEmpty) return;
    final client = ApiClient();
    int success = 0;
    for (final id in List<String>.from(_selectedIds)) {
      try {
        await client.patch<Map<String, dynamic>>(
          '${AppConstants.entitiesPath}/$id',
          data: {
            'attributes': [
              {'key': 'tag', 'value': tag},
            ],
          },
        );
        success++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Tagged $success/${_selectedIds.length} entities with "$tag"'),
      backgroundColor: success > 0 ? AppColors.success : AppColors.error,
    ));
    setState(() => _selectedIds.clear());
    _loadEntities();
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
