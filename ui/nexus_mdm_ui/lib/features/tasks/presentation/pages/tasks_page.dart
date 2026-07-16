import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ── Models ───────────────────────────────────────────────────────────────────

enum TaskPriority { high, medium, low }
enum TaskStatus { pending, inProgress, completed }

class TaskModel {
  final String id;
  final String title;
  final String description;
  final TaskPriority priority;
  final TaskStatus status;
  final String? assignee;
  final String? entityId;
  final DateTime? dueAt;
  final bool slaBreached;

  const TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    this.assignee,
    this.entityId,
    this.dueAt,
    this.slaBreached = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    TaskPriority parsePriority(dynamic raw) {
      // Backend stores priority as i16: 3=High, 2=Medium, 1=Low
      final n = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      switch (n) {
        case 3: return TaskPriority.high;
        case 2: return TaskPriority.medium;
        default: return TaskPriority.low;
      }
    }

    TaskStatus parseStatus(String? s) {
      switch (s) {
        case 'InProgress':  return TaskStatus.inProgress;
        case 'Completed':   return TaskStatus.completed;
        default:            return TaskStatus.pending;
      }
    }

    return TaskModel(
      id:          json['id']?.toString() ?? '',
      title:       json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      priority:    parsePriority(json['priority']),
      status:      parseStatus(json['status']?.toString()),
      assignee:    json['assignee']?.toString(),
      entityId:    json['entity_id']?.toString(),
      dueAt:       json['due_at'] != null
          ? DateTime.tryParse(json['due_at'].toString())
          : null,
      slaBreached: json['sla_breached'] == true,
    );
  }
}

// ── Filter model ─────────────────────────────────────────────────────────────

class _TaskFilter {
  final String label;
  final String? status;
  final String? priority;
  final bool slaBreached;

  const _TaskFilter({
    required this.label,
    this.status,
    this.priority,
    this.slaBreached = false,
  });
}

// ── Entity suggestion (for search dropdown) ───────────────────────────────────

class _EntitySuggestion {
  final String entityId;
  final String displayName;
  final String entityType;

  const _EntitySuggestion({
    required this.entityId,
    required this.displayName,
    required this.entityType,
  });
}

// ── Page ─────────────────────────────────────────────────────────────────────

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final ApiClient _api;

  bool _loading = true;
  String? _error;
  String _userId = '';

  List<TaskModel> _tasks = [];
  int _selectedFilterIndex = 0;

  static const List<_TaskFilter> _filters = [
    _TaskFilter(label: 'My Tasks'),
    _TaskFilter(label: 'All Tasks'),
    _TaskFilter(label: 'Pending',         status: 'Pending'),
    _TaskFilter(label: 'In Progress',     status: 'InProgress'),
    _TaskFilter(label: 'Completed',       status: 'Completed'),
    _TaskFilter(label: 'High Priority',   priority: 'High'),
    _TaskFilter(label: 'Medium Priority', priority: 'Medium'),
    _TaskFilter(label: 'Low Priority',    priority: 'Low'),
    _TaskFilter(label: 'SLA Breached',    slaBreached: true),
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _init();
  }

  Future<void> _init() async {
    _userId = await AuthManager.getUserId() ?? '';
    await _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() { _loading = true; _error = null; });
    try {
      final filter = _filters[_selectedFilterIndex];
      final params = <String, dynamic>{};
      if (filter.priority != null) params['priority'] = filter.priority;
      if (filter.slaBreached)      params['sla_breached'] = 'true';
      if (filter.status != null)   params['status'] = filter.status;
      if (_selectedFilterIndex == 0 && _userId.isNotEmpty) {
        params['assignee_id'] = _userId;
      }

      final response = await _api.get<Map<String, dynamic>>(
        '/v1/tasks',
        queryParameters: params.isEmpty ? null : params,
      );
      if (!mounted) return;

      final data = response.data;
      final rawList = (data?['tasks'] ?? data?['data'] ?? []) as List<dynamic>? ?? [];
      setState(() {
        _loading = false;
        _tasks = rawList
            .whereType<Map<String, dynamic>>()
            .map(TaskModel.fromJson)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load tasks';
      });
    }
  }

  Future<void> _updateTaskStatus(TaskModel task, TaskStatus newStatus) async {
    final statusStr = _statusApiString(newStatus);
    try {
      await _api.patch<dynamic>(
        '/v1/tasks/${task.id}',
        data: {'status': statusStr},
      );
      if (!mounted) return;
      await _loadTasks();
      _showSnack('Task status updated');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to update status', isError: true);
    }
  }

  int _priorityToInt(String p) {
    switch (p) {
      case 'High':   return 3;
      case 'Medium': return 2;
      default:       return 1;
    }
  }

  Future<void> _createTask({
    required String title,
    required String description,
    required String priority,
    String? entityId,
    DateTime? dueAt,
  }) async {
    try {
      final body = <String, dynamic>{
        'title':       title,
        'description': description,
        'priority':    _priorityToInt(priority),
      };
      if (entityId != null && entityId.isNotEmpty) body['entity_id'] = entityId;
      if (dueAt != null) body['due_at'] = dueAt.toIso8601String();

      await _api.post<dynamic>('/v1/tasks', data: body);
      if (!mounted) return;
      await _loadTasks();
      _showSnack('Task created');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to create task', isError: true);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _statusApiString(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:    return 'Pending';
      case TaskStatus.inProgress: return 'InProgress';
      case TaskStatus.completed:  return 'Completed';
    }
  }

  TaskStatus? _nextStatus(TaskStatus current) {
    switch (current) {
      case TaskStatus.pending:    return TaskStatus.inProgress;
      case TaskStatus.inProgress: return TaskStatus.completed;
      case TaskStatus.completed:  return null;
    }
  }

  String _nextStatusLabel(TaskStatus current) {
    switch (current) {
      case TaskStatus.pending:    return 'Start';
      case TaskStatus.inProgress: return 'Complete';
      case TaskStatus.completed:  return '';
    }
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:   return AppColors.error;
      case TaskPriority.medium: return AppColors.warning;
      case TaskPriority.low:    return AppColors.success;
    }
  }

  String _priorityLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:   return 'High';
      case TaskPriority.medium: return 'Medium';
      case TaskPriority.low:    return 'Low';
    }
  }

  Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:    return AppColors.secondaryText;
      case TaskStatus.inProgress: return AppColors.warning;
      case TaskStatus.completed:  return AppColors.success;
    }
  }

  String _statusLabel(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:    return 'Pending';
      case TaskStatus.inProgress: return 'In Progress';
      case TaskStatus.completed:  return 'Completed';
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  // ── Create task dialog ───────────────────────────────────────────────────────

  void _showCreateTaskDialog() {
    final titleCtrl    = TextEditingController();
    final descCtrl     = TextEditingController();
    final formKey      = GlobalKey<FormState>();
    String selectedPri = 'Medium';
    DateTime? dueAt;
    String? selectedEntityId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('New Task', style: AppTextStyles.titleMedium),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(titleCtrl, 'Title',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  _field(descCtrl, 'Description', maxLines: 3),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPri,
                    dropdownColor: AppColors.surface,
                    decoration: InputDecoration(
                      labelText: 'Priority',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    items: ['High', 'Medium', 'Low']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setDlg(() => selectedPri = v ?? 'Medium'),
                  ),
                  const SizedBox(height: 12),
                  _EntitySearchField(
                    api: _api,
                    onChanged: (s) => selectedEntityId = s?.entityId,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppColors.primary,
                              surface: AppColors.surface,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      setDlg(() => dueAt = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 16,
                              color: AppColors.secondaryText),
                          const SizedBox(width: 8),
                          Text(
                            dueAt != null
                                ? '${dueAt!.year}-${dueAt!.month.toString().padLeft(2, '0')}-${dueAt!.day.toString().padLeft(2, '0')}'
                                : 'Due date (optional)',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: dueAt != null
                                  ? AppColors.primaryText
                                  : AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                await _createTask(
                  title:       titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority:    selectedPri,
                  entityId:    selectedEntityId,
                  dueAt:       dueAt,
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTaskDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('New Task',
            style: AppTextStyles.buttonMedium.copyWith(color: Colors.white)),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: _buildMain()),
        ],
      ),
    );
  }

  // ── Sidebar ─────────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text('Filters', style: AppTextStyles.titleSmall),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _filters.length,
              itemBuilder: (ctx, i) {
                final f = _filters[i];
                final selected = _selectedFilterIndex == i;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                  leading: Icon(
                    _filterIcon(i),
                    size: 18,
                    color: selected ? AppColors.primary : AppColors.secondaryText,
                  ),
                  title: Text(
                    f.label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: selected ? AppColors.primary : AppColors.primaryText,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    setState(() => _selectedFilterIndex = i);
                    _loadTasks();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _filterIcon(int index) {
    switch (index) {
      case 0: return Icons.person_outline;
      case 1: return Icons.list_outlined;
      case 2: return Icons.radio_button_unchecked;
      case 3: return Icons.play_circle_outline;
      case 4: return Icons.check_circle_outline;
      case 5: return Icons.priority_high;
      case 6: return Icons.remove_circle_outline;
      case 7: return Icons.arrow_downward_outlined;
      case 8: return Icons.warning_amber_outlined;
      default: return Icons.filter_list;
    }
  }

  // ── Main content ─────────────────────────────────────────────────────────────

  Widget _buildMain() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadTasks, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.task_outlined, size: 56, color: AppColors.mutedText),
            const SizedBox(height: 16),
            Text('No tasks found', style: AppTextStyles.titleSmall.copyWith(color: AppColors.mutedText)),
            const SizedBox(height: 8),
            Text('Create a new task to get started.',
                style: AppTextStyles.bodySmall),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Text(
                _filters[_selectedFilterIndex].label,
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_tasks.length}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_outlined, size: 20),
                color: AppColors.secondaryText,
                tooltip: 'Refresh',
                onPressed: _loadTasks,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _tasks.length,
            itemBuilder: (ctx, i) => _buildTaskCard(_tasks[i]),
          ),
        ),
      ],
    );
  }

  // ── Task card ────────────────────────────────────────────────────────────────

  Widget _buildTaskCard(TaskModel task) {
    final priColor   = _priorityColor(task.priority);
    final nextStatus = _nextStatus(task.status);
    final nextLabel  = _nextStatusLabel(task.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: task.slaBreached
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(task.title, style: AppTextStyles.titleSmall),
                ),
                if (task.slaBreached) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.error),
                        const SizedBox(width: 4),
                        Text('SLA Breached',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Description
            if (task.description.isNotEmpty)
              Text(
                task.description,
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 12),
            // Chips row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Priority chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: priColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _priorityLabel(task.priority),
                    style: AppTextStyles.labelSmall.copyWith(color: priColor),
                  ),
                ),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(task.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _statusLabel(task.status),
                    style: AppTextStyles.labelSmall
                        .copyWith(color: _statusColor(task.status)),
                  ),
                ),
                // Assignee
                if (task.assignee != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline, size: 13, color: AppColors.secondaryText),
                      const SizedBox(width: 4),
                      Text(task.assignee!,
                          style: AppTextStyles.labelSmall),
                    ],
                  ),
                // Due date
                if (task.dueAt != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_outlined, size: 13,
                          color: AppColors.secondaryText),
                      const SizedBox(width: 4),
                      Text(
                        '${task.dueAt!.year}-${task.dueAt!.month.toString().padLeft(2, '0')}-${task.dueAt!.day.toString().padLeft(2, '0')}',
                        style: AppTextStyles.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
            // Action
            if (nextStatus != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: Icon(
                    nextStatus == TaskStatus.inProgress
                        ? Icons.play_arrow_outlined
                        : Icons.check_circle_outline,
                    size: 16,
                  ),
                  label: Text(nextLabel, style: AppTextStyles.buttonSmall),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _updateTaskStatus(task, nextStatus),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Form helper ──────────────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      maxLines: maxLines,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

// ── Entity search field ───────────────────────────────────────────────────────

class _EntitySearchField extends StatefulWidget {
  final ApiClient api;
  final void Function(_EntitySuggestion?) onChanged;

  const _EntitySearchField({required this.api, required this.onChanged});

  @override
  State<_EntitySearchField> createState() => _EntitySearchFieldState();
}

class _EntitySearchFieldState extends State<_EntitySearchField> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<_EntitySuggestion> _suggestions = [];
  _EntitySuggestion? _selected;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final response = await widget.api.get<Map<String, dynamic>>(
        '/v1/entities',
        queryParameters: {'search': query, 'page_size': '10'},
      );
      if (!mounted) return;
      final items = (response.data?['items'] as List<dynamic>?) ?? [];
      setState(() {
        _suggestions = items
            .whereType<Map<String, dynamic>>()
            .map((e) => _EntitySuggestion(
                  entityId:    e['entity_id']?.toString() ?? '',
                  displayName: e['display_name']?.toString() ??
                      e['entity_type']?.toString() ?? 'Unknown',
                  entityType:  e['entity_type']?.toString() ?? '',
                ))
            .where((s) => s.entityId.isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _suggestions = []; _loading = false; });
    }
  }

  void _select(_EntitySuggestion s) {
    setState(() {
      _selected = s;
      _ctrl.text = s.displayName;
      _suggestions = [];
    });
    widget.onChanged(s);
  }

  void _clear() {
    setState(() {
      _selected = null;
      _ctrl.clear();
      _suggestions = [];
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _ctrl,
          readOnly: _selected != null,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Entity (optional)',
            hintText: 'Type to search...',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            suffixIcon: _selected != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clear,
                  )
                : _loading
                    ? const SizedBox.square(
                        dimension: 36,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
          ),
          onChanged: (q) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => _search(q),
            );
          },
        ),
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (_, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(s.displayName, style: AppTextStyles.bodyMedium),
                  subtitle: Text(
                    s.entityType,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText),
                  ),
                  onTap: () => _select(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
