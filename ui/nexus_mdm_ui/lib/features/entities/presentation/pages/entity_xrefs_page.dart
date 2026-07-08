import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class _Xref {
  final String xrefId;
  final String sourceSystem;
  final String externalId;
  final String xrefType;
  final String createdAt;

  const _Xref({
    required this.xrefId,
    required this.sourceSystem,
    required this.externalId,
    required this.xrefType,
    required this.createdAt,
  });

  factory _Xref.fromJson(Map<String, dynamic> j) => _Xref(
        xrefId: j['xref_id'] as String? ?? '',
        sourceSystem: j['source_system'] as String? ?? '',
        externalId: j['external_id'] as String? ?? '',
        xrefType: j['xref_type'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class EntityXrefsPage extends StatefulWidget {
  final String entityId;

  const EntityXrefsPage({super.key, required this.entityId});

  @override
  State<EntityXrefsPage> createState() => _EntityXrefsPageState();
}

class _EntityXrefsPageState extends State<EntityXrefsPage> {
  late final ApiClient _api;

  bool _loading = true;
  String? _error;
  List<_Xref> _xrefs = [];

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _load();
  }

  // ── API ────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.get<Map<String, dynamic>>(
        '/v1/entities/${widget.entityId}/xrefs',
      );
      final items = (resp.data?['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _xrefs = items.map(_Xref.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load cross-references';
        _loading = false;
      });
    }
  }

  Future<void> _create({
    required String sourceSystem,
    required String externalId,
    required String xrefType,
  }) async {
    try {
      await _api.post<dynamic>(
        '/v1/entities/${widget.entityId}/xrefs',
        data: {
          'source_system': sourceSystem,
          'external_id': externalId,
          'xref_type': xrefType,
        },
      );
      if (!mounted) return;
      _showSnack('Cross-reference added');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to add cross-reference', isError: true);
    }
  }

  Future<void> _delete(_Xref xref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Cross-Reference', style: AppTextStyles.titleMedium),
        content: Text(
          'Remove ${xref.sourceSystem} / ${xref.externalId}?',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.delete<dynamic>(
        '/v1/entities/${widget.entityId}/xrefs/${xref.xrefId}',
      );
      if (!mounted) return;
      _showSnack('Cross-reference deleted');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to delete cross-reference', isError: true);
    }
  }

  // ── Dialog ─────────────────────────────────────────────────────────────────

  void _showAddDialog() {
    final sourceCtrl = TextEditingController();
    final extIdCtrl = TextEditingController();
    String selectedType = 'primary';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: AppColors.surface,
          title:
              Text('Add Cross-Reference', style: AppTextStyles.titleMedium),
          content: SizedBox(
            width: 380,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(sourceCtrl, 'Source System',
                      hint: 'e.g. SAP, Salesforce',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  _field(extIdCtrl, 'External ID',
                      hint: 'e.g. C-123456',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Xref Type',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                      filled: true,
                      fillColor: AppColors.inputFill,
                    ),
                    dropdownColor: AppColors.elevatedCard,
                    items: const [
                      DropdownMenuItem(value: 'primary', child: Text('Primary')),
                      DropdownMenuItem(
                          value: 'secondary', child: Text('Secondary')),
                      DropdownMenuItem(value: 'legacy', child: Text('Legacy')),
                    ],
                    onChanged: (v) => setDs(() => selectedType = v ?? 'primary'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                await _create(
                  sourceSystem: sourceCtrl.text.trim(),
                  externalId: extIdCtrl.text.trim(),
                  xrefType: selectedType,
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      style: AppTextStyles.inputText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.inputFill,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'primary':
        return AppColors.success;
      case 'secondary':
        return AppColors.cyan;
      case 'legacy':
        return AppColors.warning;
      default:
        return AppColors.secondaryText;
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_link),
        label: const Text('Add Xref'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _xrefs.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.compare_arrows, size: 56, color: AppColors.mutedText),
          const SizedBox(height: 16),
          Text(
            'No cross-references found.',
            style: AppTextStyles.titleSmall
                .copyWith(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 6),
          Text(
            'Add external IDs from source systems.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('SOURCE SYSTEM',
                      style: AppTextStyles.tableHeader)),
              Expanded(
                  flex: 4,
                  child:
                      Text('EXTERNAL ID', style: AppTextStyles.tableHeader)),
              Expanded(
                  flex: 2,
                  child: Text('TYPE', style: AppTextStyles.tableHeader)),
              Expanded(
                  flex: 2,
                  child: Text('ADDED', style: AppTextStyles.tableHeader)),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _xrefs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (ctx, i) {
              final x = _xrefs[i];
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                x.sourceSystem.isNotEmpty
                                    ? x.sourceSystem[0].toUpperCase()
                                    : '?',
                                style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                x.sourceSystem,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(
                                        fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          x.externalId,
                          style: AppTextStyles.codeStyle,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _typeColor(x.xrefType)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            x.xrefType.toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: _typeColor(x.xrefType),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatDate(x.createdAt),
                          style: AppTextStyles.timestamp,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Delete',
                        color: AppColors.mutedText,
                        hoverColor: AppColors.error.withValues(alpha: 0.1),
                        onPressed: () => _delete(x),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
