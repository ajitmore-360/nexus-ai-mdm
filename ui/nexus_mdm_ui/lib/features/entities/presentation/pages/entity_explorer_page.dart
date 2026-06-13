import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
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
import '../../../entities/data/entity_repository.dart';

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

  @override
  void initState() {
    super.initState();
    _repository = EntityRepository(ApiClient());
    _loadEntities();
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

    final result = await _repository.getEntities(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      type: _selectedType?.toLowerCase(),
      status: _selectedStatus?.toLowerCase(),
      sourceSystem: _selectedSource,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      switch (result) {
        case Success<EntityPage>(:final data):
          _filteredEntities = data.items;
        case Failure<EntityPage>():
          _filteredEntities = CanonicalEntity.demoList;
      }
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _applyFilters);
  }

  void _applyFilters() {
    // Re-fetch from repository with current filters (search debounced)
    _loadEntities();
  }

  Future<void> _submitAiQuery() async {
    if (_aiQueryController.text.trim().isEmpty) return;
    setState(() => _isAiQuerying = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _isAiQuerying = false;
      // In production, apply AI query results
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'AI found ${_filteredEntities.length} results for: "${_aiQueryController.text}"'),
          backgroundColor: AppColors.elevatedCard,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateEntityDialog,
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
            onPressed: () {},
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Export'),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Columns'),
          ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    final types = [null, ...AppConstants.entityTypes];
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
        color: AppColors.primary.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedIds.length} selected',
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('Merge'),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.label_outline, size: 16),
            label: const Text('Tag'),
          ),
          TextButton.icon(
            onPressed: () {},
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
        onAction: _showCreateEntityDialog,
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
          Expanded(
            flex: 3,
            child: Text('NAME / ID', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('TYPE', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('STATUS', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 3,
            child: Text('TRUST SCORE', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('SOURCE', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('UPDATED', style: AppTextStyles.tableHeader),
          ),
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
            // Type
            Expanded(
              flex: 2,
              child: Text(
                entity.typeDisplayName,
                style: AppTextStyles.tableCell,
              ),
            ),
            // Status
            Expanded(
              flex: 2,
              child: StatusBadge(status: entity.status),
            ),
            // Trust score
            Expanded(
              flex: 3,
              child: TrustScoreBar(score: entity.trustScore),
            ),
            // Source
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entity.primarySource,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryText),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entity.sourceSystems.length > 1)
                    Text(
                      '+${entity.sourceSystems.length - 1} more',
                      style: AppTextStyles.timestamp,
                    ),
                ],
              ),
            ),
            // Updated
            Expanded(
              flex: 2,
              child: Text(
                _formatRelativeTime(entity.updatedAt),
                style: AppTextStyles.bodySmall,
              ),
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
    final totalPages =
        (_filteredEntities.length / _pageSize).ceil().clamp(1, 999);

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
                ? () => setState(() => _currentPage--)
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
                ? () => setState(() => _currentPage++)
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
      onTap: () => setState(() => _currentPage = page),
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
    }
  }

  void _showCreateEntityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Entity'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Entity Type'),
                items: AppConstants.entityTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Source System'),
                items: AppConstants.dataSources
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
