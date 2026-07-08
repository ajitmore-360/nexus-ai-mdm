import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EntityHierarchyPage extends StatefulWidget {
  final String entityId;
  final String entityName;
  const EntityHierarchyPage({
    super.key,
    required this.entityId,
    required this.entityName,
  });

  @override
  State<EntityHierarchyPage> createState() => _EntityHierarchyPageState();
}

class _EntityHierarchyPageState extends State<EntityHierarchyPage> {
  final _apiClient = ApiClient();
  List<Map<String, dynamic>> _ancestors = [];
  List<Map<String, dynamic>> _children = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final results = await Future.wait([
        _apiClient.get<Map<String, dynamic>>('/v1/entities/${widget.entityId}/ancestors'),
        _apiClient.get<Map<String, dynamic>>('/v1/entities/${widget.entityId}/children'),
      ]);
      setState(() {
        _ancestors = (results[0].data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _children = (results[1].data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setParent() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    String? selectedId;
    String? selectedName;

    final parentId = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Set Parent Entity', style: AppTextStyles.titleMedium),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search entity name…',
                    hintStyle: AppTextStyles.inputHint,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty) return;
                    try {
                      final resp = await _apiClient.get<Map<String, dynamic>>(
                        '/v1/entities',
                        queryParameters: {'search': v.trim(), 'page_size': 10},
                      );
                      setDialogState(() {
                        results = (resp.data?['items'] as List? ?? [])
                            .cast<Map<String, dynamic>>();
                      });
                    } catch (_) {}
                  },
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (ctx, i) {
                        final e = results[i];
                        final id = e['id'] as String? ?? '';
                        final name = (e['attributes'] as Map?)?['name'] as String? ?? id;
                        final isSelected = selectedId == id;
                        return ListTile(
                          title: Text(name, style: AppTextStyles.bodyMedium),
                          subtitle: Text(e['entity_type'] as String? ?? '',
                              style: AppTextStyles.bodySmall),
                          selected: isSelected,
                          selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                          onTap: () => setDialogState(() {
                            selectedId = id;
                            selectedName = name;
                          }),
                        );
                      },
                    ),
                  ),
                ],
                if (selectedName != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Selected: $selectedName',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            if (selectedId != null && selectedId != widget.entityId)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selectedId),
                child: const Text('Set Parent'),
              ),
          ],
        ),
      ),
    );

    if (parentId == null) return;
    if (_isAncestor(parentId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot set — would create circular reference'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    try {
      await _apiClient.patch<void>(
        '/v1/entities/${widget.entityId}/parent',
        data: {'parent_id': parentId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parent updated')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  bool _isAncestor(String id) => _ancestors.any((a) => a['id'] == id);

  Future<void> _removeParent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove from Hierarchy?', style: AppTextStyles.titleMedium),
        content: Text('This entity will become a root node.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _apiClient.patch<void>(
          '/v1/entities/${widget.entityId}/parent',
          data: {'parent_id': null},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Removed from hierarchy')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Hierarchy', style: AppTextStyles.titleLarge),
        actions: [
          TextButton.icon(
            onPressed: _setParent,
            icon: Icon(Icons.add_link, color: AppColors.primary),
            label: Text('Set Parent', style: TextStyle(color: AppColors.primary)),
          ),
          if (_ancestors.isNotEmpty)
            TextButton.icon(
              onPressed: _removeParent,
              icon: Icon(Icons.link_off, color: AppColors.error),
              label: Text('Remove', style: TextStyle(color: AppColors.error)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 8),
          Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAncestorsSection(),
          const SizedBox(height: 32),
          _buildCurrentNode(),
          const SizedBox(height: 32),
          _buildChildrenSection(),
        ],
      ),
    );
  }

  Widget _buildAncestorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ANCESTORS', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 12),
        if (_ancestors.isEmpty)
          Text('No ancestors — this is a root node', style: AppTextStyles.bodySmall)
        else
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _ancestors.expand((a) {
              final name = (a['attributes'] as Map?)?['name'] as String?
                  ?? a['id'] as String? ?? '—';
              return [
                ActionChip(
                  label: Text(name, style: AppTextStyles.labelMedium),
                  backgroundColor: AppColors.cardSurface,
                  onPressed: () {},
                ),
                const Icon(Icons.chevron_right, size: 16, color: Colors.white54),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildCurrentNode() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_tree, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.entityName, style: AppTextStyles.titleMedium),
                Text('Current entity', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          Text('${_children.length} children', style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _buildChildrenSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CHILDREN (${_children.length})',
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 12),
        if (_children.isEmpty)
          Text('No children entities', style: AppTextStyles.bodySmall)
        else
          ..._children.map((child) {
            final name = (child['attributes'] as Map?)?['name'] as String?
                ?? child['id'] as String? ?? '—';
            final type = child['entity_type'] as String? ?? '';
            final childCount = child['child_count'] as int? ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      color: AppColors.secondaryText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTextStyles.labelLarge),
                        Text(type, style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                  if (childCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$childCount sub',
                          style: TextStyle(color: AppColors.primary, fontSize: 11)),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
