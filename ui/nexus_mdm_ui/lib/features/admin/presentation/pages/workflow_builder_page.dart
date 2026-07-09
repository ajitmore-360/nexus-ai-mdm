import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class WorkflowBuilderPage extends StatefulWidget {
  const WorkflowBuilderPage({super.key});

  @override
  State<WorkflowBuilderPage> createState() => _WorkflowBuilderPageState();
}

class _WorkflowBuilderPageState extends State<WorkflowBuilderPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();

  List<Map<String, dynamic>> _workflows = [];
  List<Map<String, dynamic>> _stepTypes = [];
  bool _loading = true;
  String _error = '';
  String? _selectedWorkflowId;

  // Builder state
  final List<Map<String, dynamic>> _steps = [];
  String _wfName = '';
  String _wfDescription = '';
  String _triggerType = 'manual';
  bool _isActive = true;

  late TabController _tabCtrl;

  static const _triggerOptions = [
    ('manual', 'Manual'),
    ('entity_create', 'Entity Created'),
    ('entity_update', 'Entity Updated'),
    ('entity_merge', 'Entity Merged'),
    ('schedule', 'Schedule'),
    ('webhook', 'Webhook'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final results = await Future.wait([
        _api.get<Map<String, dynamic>>('/workflows'),
        _api.get<Map<String, dynamic>>('/workflow-step-types'),
      ]);
      final wfData = results[0].data?['data'] as List? ?? [];
      final stData = results[1].data?['data'] as List? ?? [];
      setState(() {
        _workflows = wfData.cast<Map<String, dynamic>>();
        _stepTypes = stData.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _loadWorkflowIntoBuilder(Map<String, dynamic> wf) {
    final steps = (wf['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _selectedWorkflowId = wf['workflow_id'] as String?;
      _wfName = wf['name'] as String? ?? '';
      _wfDescription = wf['description'] as String? ?? '';
      _triggerType = wf['trigger_type'] as String? ?? 'manual';
      _isActive = wf['is_active'] as bool? ?? true;
      _steps
        ..clear()
        ..addAll(steps);
    });
    _tabCtrl.animateTo(1);
  }

  void _newWorkflow() {
    setState(() {
      _selectedWorkflowId = null;
      _wfName = '';
      _wfDescription = '';
      _triggerType = 'manual';
      _isActive = true;
      _steps.clear();
    });
    _tabCtrl.animateTo(1);
  }

  void _addStep(Map<String, dynamic> stepType) {
    setState(() {
      _steps.add({
        'step_type_code': stepType['step_type_code'],
        'display_name': stepType['display_name'],
        'config': <String, dynamic>{},
      });
    });
  }

  void _removeStep(int index) {
    setState(() { _steps.removeAt(index); });
  }

  void _reorderStep(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (_wfName.trim().isEmpty) {
      _showSnack('Workflow name is required', isError: true);
      return;
    }
    final body = {
      'name': _wfName.trim(),
      'description': _wfDescription.trim().isEmpty ? null : _wfDescription.trim(),
      'trigger_type': _triggerType,
      'trigger_config': <String, dynamic>{},
      'steps': _steps,
      'is_active': _isActive,
    };
    try {
      if (_selectedWorkflowId == null) {
        await _api.post<Map<String, dynamic>>('/workflows', data: body);
        _showSnack('Workflow created');
      } else {
        await _api.put<Map<String, dynamic>>('/workflows/$_selectedWorkflowId', data: body);
        _showSnack('Workflow updated');
      }
      await _loadData();
      _tabCtrl.animateTo(0);
    } catch (e) {
      _showSnack('Save failed: $e', isError: true);
    }
  }

  Future<void> _toggleWorkflow(String id, bool current) async {
    try {
      await _api.put<Map<String, dynamic>>('/workflows/$id/toggle', data: {});
      await _loadData();
    } catch (e) {
      _showSnack('Toggle failed: $e', isError: true);
    }
  }

  Future<void> _deleteWorkflow(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Delete Workflow', style: AppTextStyles.titleMedium),
        content: Text('This action cannot be undone.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete<void>('/workflows/$id');
      await _loadData();
    } catch (e) {
      _showSnack('Delete failed: $e', isError: true);
    }
  }

  Future<void> _triggerRun(String id) async {
    try {
      await _api.post<Map<String, dynamic>>('/workflows/$id/trigger', data: {});
      _showSnack('Workflow triggered');
    } catch (e) {
      _showSnack('Trigger failed: $e', isError: true);
    }
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
    return Column(
      children: [
        _buildHeader(),
        TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.secondaryText,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Workflows'),
            Tab(text: 'Builder'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? _buildError()
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [_buildList(), _buildBuilder()],
                    ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Visual Workflow Engine', style: AppTextStyles.titleMedium),
              Text('Automate MDM processes with no-code workflows',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: _newWorkflow,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Workflow'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        const SizedBox(height: 12),
        Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        const SizedBox(height: 12),
        TextButton(onPressed: _loadData, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildList() {
    if (_workflows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_tree_outlined, size: 64, color: AppColors.secondaryText),
          const SizedBox(height: 16),
          Text('No workflows yet', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text('Create your first workflow to automate MDM processes.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _newWorkflow,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Create Workflow'),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _workflows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _workflowCard(_workflows[i]),
    );
  }

  Widget _workflowCard(Map<String, dynamic> wf) {
    final id = wf['workflow_id'] as String? ?? '';
    final isActive = wf['is_active'] as bool? ?? false;
    final trigger = wf['trigger_type'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.success.withValues(alpha: 0.15)
                : AppColors.secondaryText.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.account_tree_outlined,
            color: isActive ? AppColors.success : AppColors.secondaryText,
            size: 20,
          ),
        ),
        title: Text(wf['name'] as String? ?? '', style: AppTextStyles.titleSmall),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((wf['description'] as String?)?.isNotEmpty == true)
            Text(wf['description'] as String,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            _chip(_triggerLabel(trigger), AppColors.cyan.withValues(alpha: 0.15), AppColors.cyan),
            _chip(isActive ? 'Active' : 'Inactive',
                isActive ? AppColors.success.withValues(alpha: 0.15) : AppColors.secondaryText.withValues(alpha: 0.15),
                isActive ? AppColors.success : AppColors.secondaryText),
            _chip('v${wf['version'] ?? 1}', AppColors.primary.withValues(alpha: 0.1), AppColors.primary),
          ]),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                color: AppColors.primary),
            tooltip: isActive ? 'Deactivate' : 'Activate',
            onPressed: () => _toggleWorkflow(id, isActive),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow_outlined, color: AppColors.success),
            tooltip: 'Trigger now',
            onPressed: () => _triggerRun(id),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.secondaryText),
            tooltip: 'Edit',
            onPressed: () => _loadWorkflowIntoBuilder(wf),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.error),
            tooltip: 'Delete',
            onPressed: () => _deleteWorkflow(id),
          ),
        ]),
      ),
    );
  }

  Widget _buildBuilder() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Step palette
      Container(
        width: 220,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.divider)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Step Types', style: AppTextStyles.labelLarge),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: _buildPaletteGroups(),
            ),
          ),
        ]),
      ),
      // Canvas + config
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildWorkflowConfig(),
            const SizedBox(height: 16),
            _buildCanvas(),
            const SizedBox(height: 16),
            _buildSaveButton(),
          ]),
        ),
      ),
    ]);
  }

  List<Widget> _buildPaletteGroups() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final st in _stepTypes) {
      final cat = st['category'] as String? ?? 'Other';
      grouped.putIfAbsent(cat, () => []).add(st);
    }
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(entry.key.toUpperCase(),
            style: AppTextStyles.labelMedium
                .copyWith(color: AppColors.secondaryText, letterSpacing: 0.8)),
      ));
      for (final st in entry.value) {
        widgets.add(_paletteTile(st));
      }
    }
    return widgets;
  }

  Widget _paletteTile(Map<String, dynamic> st) {
    return Draggable<Map<String, dynamic>>(
      data: st,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(st['display_name'] as String? ?? '',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white)),
        ),
      ),
      child: InkWell(
        onTap: () => _addStep(st),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            const Icon(Icons.drag_indicator, size: 14, color: AppColors.secondaryText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(st['display_name'] as String? ?? '',
                  style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildWorkflowConfig() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Workflow Settings', style: AppTextStyles.titleSmall),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Name *',
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.divider)),
              ),
              controller: TextEditingController(text: _wfName)
                ..selection = TextSelection.collapsed(offset: _wfName.length),
              onChanged: (v) => _wfName = v,
              style: AppTextStyles.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _triggerType,
              decoration: InputDecoration(
                labelText: 'Trigger',
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.divider)),
              ),
              items: _triggerOptions.map((t) =>
                  DropdownMenuItem(value: t.$1, child: Text(t.$2))).toList(),
              onChanged: (v) => setState(() => _triggerType = v ?? 'manual'),
              dropdownColor: AppColors.surface,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primaryText),
            ),
          ),
          const SizedBox(width: 12),
          Row(children: [
            Text('Active', style: AppTextStyles.bodyMedium),
            Switch(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: AppColors.success,
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: 'Description',
            filled: true,
            fillColor: AppColors.inputFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider)),
          ),
          controller: TextEditingController(text: _wfDescription)
            ..selection = TextSelection.collapsed(offset: _wfDescription.length),
          onChanged: (v) => _wfDescription = v,
          style: AppTextStyles.bodyMedium,
        ),
      ]),
    );
  }

  Widget _buildCanvas() {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Steps', style: AppTextStyles.titleSmall),
          const Spacer(),
          Text('${_steps.length} step${_steps.length == 1 ? '' : 's'}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
        ]),
        const SizedBox(height: 12),
        if (_steps.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_box_outlined, size: 40, color: AppColors.secondaryText),
                const SizedBox(height: 8),
                Text('Drag steps from the palette or click a step type to add',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText)),
              ]),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _steps.length,
            onReorder: _reorderStep,
            itemBuilder: (_, i) => _stepCard(_steps[i], i, key: ValueKey(i)),
          ),
      ]),
    );
  }

  Widget _stepCard(Map<String, dynamic> step, int index, {required Key key}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text('${index + 1}',
                style: AppTextStyles.labelMedium.copyWith(color: Colors.white, fontSize: 11)),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.drag_handle, size: 16, color: AppColors.secondaryText),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step['display_name'] as String? ?? step['step_type_code'] as String? ?? '',
                style: AppTextStyles.bodyMedium),
            Text(step['step_type_code'] as String? ?? '',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 16, color: AppColors.error),
          onPressed: () => _removeStep(index),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
        ),
      ]),
    );
  }

  Widget _buildSaveButton() {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      OutlinedButton(
        onPressed: () => _tabCtrl.animateTo(0),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondaryText,
          side: BorderSide(color: AppColors.divider),
        ),
        child: const Text('Cancel'),
      ),
      const SizedBox(width: 12),
      ElevatedButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: Text(_selectedWorkflowId == null ? 'Create Workflow' : 'Save Changes'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    ]);
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: AppTextStyles.chipLabel.copyWith(color: fg)),
    );
  }

  String _triggerLabel(String code) {
    return _triggerOptions.firstWhere((t) => t.$1 == code,
        orElse: () => (code, code)).cast<String>()[1];
  }
}

extension on (String, String) {
  List<String> cast<T>() => [this.$1, this.$2];
}
