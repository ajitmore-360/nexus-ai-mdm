import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter — this app is web-only.
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ── Status options ────────────────────────────────────────────────────────────

const _kStatuses = ['Active', 'Review', 'Merged', 'Inactive'];
const _kFormats = ['csv', 'json'];

// ─────────────────────────────────────────────────────────────────────────────

class BulkOperationsPage extends StatefulWidget {
  const BulkOperationsPage({super.key});

  @override
  State<BulkOperationsPage> createState() => _BulkOperationsPageState();
}

class _BulkOperationsPageState extends State<BulkOperationsPage> {
  late final ApiClient _api;

  // Entity-type list
  List<String> _entityTypes = [];
  bool _entityTypesLoading = true;

  // ── Bulk Status Update state ────────────────────────────────────────────────
  final _statusIdsCtrl = TextEditingController();
  String _selectedStatus = 'Active';
  bool _statusUpdating = false;

  // ── Bulk Tag state ──────────────────────────────────────────────────────────
  final _tagIdsCtrl = TextEditingController();
  final _tagNameCtrl = TextEditingController();
  bool _tagging = false;

  // ── Bulk Export state ───────────────────────────────────────────────────────
  String? _selectedEntityType;
  String _exportFormat = 'csv';
  String _exportStatus = '';
  String _exportSourceSystem = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _loadEntityTypes();
  }

  @override
  void dispose() {
    _statusIdsCtrl.dispose();
    _tagIdsCtrl.dispose();
    _tagNameCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadEntityTypes() async {
    setState(() => _entityTypesLoading = true);
    try {
      final resp =
          await _api.get<dynamic>('/v1/entity-types');
      final raw = resp.data;
      List<dynamic> items = [];
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = (raw['items'] ?? raw['data'] ?? raw['entity_types'] ??
            []) as List<dynamic>;
      }
      if (!mounted) return;
      setState(() {
        _entityTypes = items
            .map((e) =>
                (e is Map ? (e['name'] ?? e['code'] ?? '') : e).toString())
            .where((s) => s.isNotEmpty)
            .toList();
        if (_entityTypes.isNotEmpty) _selectedEntityType = _entityTypes.first;
        _entityTypesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _entityTypesLoading = false);
    }
  }

  // ── Parse IDs helper ────────────────────────────────────────────────────────

  List<String> _parseIds(String raw) {
    return raw
        .split(RegExp(r'[,\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Bulk status update ──────────────────────────────────────────────────────

  Future<void> _updateStatus() async {
    final ids = _parseIds(_statusIdsCtrl.text);
    if (ids.isEmpty) {
      _showSnack('Enter at least one entity ID', isError: true);
      return;
    }
    setState(() => _statusUpdating = true);
    try {
      final resp = await _api.post<Map<String, dynamic>>(
        '/v1/entities/bulk/status',
        data: {'entity_ids': ids, 'new_status': _selectedStatus},
      );
      if (!mounted) return;
      final updated = resp.data?['updated_count'] as int? ?? ids.length;
      _showSnack('Updated $updated entities');
      _statusIdsCtrl.clear();
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.response?.data?['message'] as String? ?? 'Status update failed',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Status update failed', isError: true);
    } finally {
      if (mounted) setState(() => _statusUpdating = false);
    }
  }

  // ── Bulk tag ────────────────────────────────────────────────────────────────

  Future<void> _applyTag() async {
    final ids = _parseIds(_tagIdsCtrl.text);
    final tag = _tagNameCtrl.text.trim();
    if (ids.isEmpty) {
      _showSnack('Enter at least one entity ID', isError: true);
      return;
    }
    if (tag.isEmpty) {
      _showSnack('Enter a tag name', isError: true);
      return;
    }
    setState(() => _tagging = true);
    try {
      await _api.post<dynamic>(
        '/v1/entities/bulk/tag',
        data: {'entity_ids': ids, 'tag': tag},
      );
      if (!mounted) return;
      _showSnack('Tag "$tag" applied to ${ids.length} entities');
      _tagIdsCtrl.clear();
      _tagNameCtrl.clear();
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.response?.data?['message'] as String? ?? 'Tagging failed',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Tagging failed', isError: true);
    } finally {
      if (mounted) setState(() => _tagging = false);
    }
  }

  // ── Bulk export ─────────────────────────────────────────────────────────────

  Future<void> _export() async {
    if (_selectedEntityType == null) {
      _showSnack('Select an entity type', isError: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final filters = <String, dynamic>{};
      if (_exportStatus.isNotEmpty) filters['status'] = _exportStatus;
      if (_exportSourceSystem.isNotEmpty) {
        filters['source_system'] = _exportSourceSystem;
      }

      final resp = await _api.post<dynamic>(
        '/v1/entities/bulk/export',
        data: {
          'entity_type': _selectedEntityType,
          'format': _exportFormat,
          'filters': filters,
        },
      );
      if (!mounted) return;

      // Trigger a browser download.
      final content = resp.data is String
          ? resp.data as String
          : jsonEncode(resp.data);
      final mime = _exportFormat == 'csv' ? 'text/csv' : 'application/json';
      final filename =
          'export_${_selectedEntityType}_${DateTime.now().millisecondsSinceEpoch}.$_exportFormat';

      if (kIsWeb) {
        final bytes = utf8.encode(content);
        final blob = html.Blob([bytes], mime);
        final url = html.Url.createObjectUrlFromBlob(blob);
        (html.AnchorElement(href: url)
              ..setAttribute('download', filename)
              ..click())
            .remove();
        html.Url.revokeObjectUrl(url);
      }

      _showSnack('Export complete — $filename');
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(
        e.response?.data?['message'] as String? ?? 'Export failed',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Export failed', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

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
        title: Text('Bulk Operations', style: AppTextStyles.titleMedium),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page description ──────────────────────────────────────────────
            Text(
              'Perform operations on multiple entities at once.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 28),

            // ── Bulk Status Update ────────────────────────────────────────────
            _BulkCard(
              title: 'Bulk Status Update',
              icon: Icons.sync_alt_rounded,
              child: _buildStatusSection(),
            ),
            const SizedBox(height: 20),

            // ── Bulk Tag ──────────────────────────────────────────────────────
            _BulkCard(
              title: 'Bulk Tag',
              icon: Icons.label_outline_rounded,
              child: _buildTagSection(),
            ),
            const SizedBox(height: 20),

            // ── Bulk Export ───────────────────────────────────────────────────
            _BulkCard(
              title: 'Bulk Export',
              icon: Icons.download_rounded,
              child: _buildExportSection(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status section ──────────────────────────────────────────────────────────

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdsField(
          controller: _statusIdsCtrl,
          label: 'Entity IDs',
          hint: 'One per line, or comma-separated',
        ),
        const SizedBox(height: 14),
        _DropdownRow(
          label: 'New Status',
          value: _selectedStatus,
          items: _kStatuses,
          onChanged: (v) => setState(() => _selectedStatus = v!),
          itemColor: _statusColor,
        ),
        const SizedBox(height: 18),
        _ActionButton(
          label: 'Update Status',
          loadingLabel: 'Updating…',
          icon: Icons.sync_alt_rounded,
          loading: _statusUpdating,
          color: AppColors.primary,
          onPressed: _updateStatus,
        ),
      ],
    );
  }

  // ── Tag section ─────────────────────────────────────────────────────────────

  Widget _buildTagSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdsField(
          controller: _tagIdsCtrl,
          label: 'Entity IDs',
          hint: 'One per line, or comma-separated',
        ),
        const SizedBox(height: 14),
        _TextField(
          controller: _tagNameCtrl,
          label: 'Tag Name',
          hint: 'e.g. VIP_Customer',
        ),
        const SizedBox(height: 18),
        _ActionButton(
          label: 'Apply Tag',
          loadingLabel: 'Applying…',
          icon: Icons.label_outline_rounded,
          loading: _tagging,
          color: AppColors.primary,
          onPressed: _applyTag,
        ),
      ],
    );
  }

  // ── Export section ──────────────────────────────────────────────────────────

  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Entity type dropdown
        if (_entityTypesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          _DropdownRow(
            label: 'Entity Type',
            value: _selectedEntityType ?? '',
            items: _entityTypes.isEmpty ? ['(no types)'] : _entityTypes,
            onChanged: _entityTypes.isEmpty
                ? null
                : (v) => setState(() => _selectedEntityType = v),
          ),
        const SizedBox(height: 14),

        // Format selector
        _DropdownRow(
          label: 'Format',
          value: _exportFormat,
          items: _kFormats,
          onChanged: (v) => setState(() => _exportFormat = v!),
        ),
        const SizedBox(height: 14),

        // Optional filters
        Text('Filters (optional)',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TextField(
                controller: null,
                initialValue: _exportStatus,
                label: 'Status',
                hint: 'e.g. Active',
                onChanged: (v) => _exportStatus = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TextField(
                controller: null,
                initialValue: _exportSourceSystem,
                label: 'Source System',
                hint: 'e.g. Salesforce',
                onChanged: (v) => _exportSourceSystem = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ActionButton(
          label: 'Export',
          loadingLabel: 'Exporting…',
          icon: Icons.download_rounded,
          loading: _exporting,
          color: AppColors.cyan,
          onPressed: _export,
        ),
      ],
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Active':
        return AppColors.statusActive;
      case 'Review':
        return AppColors.statusReview;
      case 'Merged':
        return AppColors.statusMerged;
      case 'Inactive':
        return AppColors.statusInactive;
      default:
        return AppColors.secondaryText;
    }
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _BulkCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _BulkCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  State<_BulkCard> createState() => _BulkCardState();
}

class _BulkCardState extends State<_BulkCard> {
  bool _expanded = true;

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
          // Header / toggle
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.title,
                        style: AppTextStyles.titleSmall),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.secondaryText,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.all(18),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

class _IdsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _IdsField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelMedium),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: 5,
          style: AppTextStyles.codeStyle.copyWith(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.inputHint,
            isDense: true,
            filled: true,
            fillColor: AppColors.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _TextField({
    required this.controller,
    this.initialValue,
    required this.label,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      onChanged: onChanged,
      style: AppTextStyles.inputText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: AppTextStyles.inputHint,
        isDense: true,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final Color Function(String)? itemColor;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: AppTextStyles.labelMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : items.first,
                isExpanded: true,
                dropdownColor: AppColors.elevatedCard,
                style: AppTextStyles.bodyMedium,
                iconEnabledColor: AppColors.secondaryText,
                items: items
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: itemColor != null
                                  ? itemColor!(s)
                                  : AppColors.primaryText,
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String loadingLabel;
  final IconData icon;
  final bool loading;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.loadingLabel,
    required this.icon,
    required this.loading,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 17, color: Colors.white),
        label: Text(
          loading ? loadingLabel : label,
          style:
              AppTextStyles.buttonMedium.copyWith(color: Colors.white),
        ),
        onPressed: loading ? null : onPressed,
      ),
    );
  }
}
