import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../shared/models/api_responses.dart';
import '../../data/admin_repository.dart';
import '../../data/entity_type_repository.dart';
import '../../data/governance_repository.dart';

class DataGovernancePage extends StatefulWidget {
  const DataGovernancePage({super.key});

  @override
  State<DataGovernancePage> createState() => _DataGovernancePageState();
}

class _DataGovernancePageState extends State<DataGovernancePage> {
  final _apiClient = ApiClient();
  late final GovernanceRepository _governanceRepo;
  late final EntityTypeRepository _entityTypeRepo;
  late final AdminRepository _adminRepo;

  bool _loading = true;
  String? _error;
  String _typeFilter = '';

  List<GovernanceAssignment> _assignments = [];
  List<EntityTypeModel> _entityTypes = [];
  List<TenantUserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _governanceRepo = GovernanceRepository(_apiClient);
    _entityTypeRepo = EntityTypeRepository(_apiClient);
    _adminRepo = AdminRepository(_apiClient);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = await AuthManager.getTenantId() ?? '';

      final r0 = await _governanceRepo.listAssignments();
      final r1 = await _entityTypeRepo.listEntityTypes(tenantId);
      final r2 = await _adminRepo.listUsers(tenantId);

      if (!mounted) return;
      setState(() {
        _assignments = r0 is Success<List<GovernanceAssignment>>
            ? r0.data
            : [];
        _entityTypes = r1 is Success<List<EntityTypeModel>>
            ? r1.data
            : [];
        _users = r2 is Success<List<TenantUserModel>>
            ? r2.data
            : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  GovernanceAssignment? _ownerForType(String code) => _assignments
      .where((a) => a.entityTypeCode == code && a.assignmentType == 'owner')
      .firstOrNull;

  List<GovernanceAssignment> _stewardsForType(String code) => _assignments
      .where((a) => a.entityTypeCode == code && a.assignmentType == 'steward')
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Data Governance', style: AppTextStyles.titleMedium),
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
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('Failed to load governance data', style: AppTextStyles.bodyLarge),
        const SizedBox(height: 4),
        Text(_error!,
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildContent() {
    if (_entityTypes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.category_outlined, size: 48, color: AppColors.secondaryText),
          const SizedBox(height: 12),
          Text('No entity types defined yet.', style: AppTextStyles.bodyLarge),
          const SizedBox(height: 4),
          Text('Create entity types first under Org Setup → Entity Types.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
        ]),
      );
    }

    final filtered = _typeFilter.isEmpty
        ? _entityTypes
        : _entityTypes
            .where((et) =>
                et.name.toLowerCase().contains(_typeFilter.toLowerCase()) ||
                et.code.toLowerCase().contains(_typeFilter.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Filter entity types…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _typeFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _typeFilter = ''),
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: AppColors.cardSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text('No entity types match "$_typeFilter".',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final et = filtered[i];
                return _EntityTypeCard(
                  entityTypeName: et.name,
                  entityTypeCode: et.code,
                  owner: _ownerForType(et.code),
                  stewards: _stewardsForType(et.code),
                  users: _users,
                  onAdd: (identityId, assignmentType) =>
                      _addAssignment(et.code, identityId, assignmentType),
                  onRemove: _removeAssignment,
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _addAssignment(
    String entityTypeCode,
    String identityId,
    String assignmentType,
  ) async {
    final result = await _governanceRepo.createAssignment(
      identityId: identityId,
      entityTypeCode: entityTypeCode,
      assignmentType: assignmentType,
    );
    if (!mounted) return;
    if (result is Success<String>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${assignmentType == 'owner' ? 'Data Owner' : 'Steward'} assigned.'),
        backgroundColor: AppColors.success,
      ));
      _load();
    } else if (result is Failure<String>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.exception.message),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _removeAssignment(String assignmentId) async {
    final result = await _governanceRepo.deleteAssignment(assignmentId);
    if (!mounted) return;
    if (result is Success<bool>) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Assignment removed.'),
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

// ─────────────────────────────────────────────────────────────────────────────

class _EntityTypeCard extends StatelessWidget {
  final String entityTypeName;
  final String entityTypeCode;
  final GovernanceAssignment? owner;
  final List<GovernanceAssignment> stewards;
  final List<TenantUserModel> users;
  final Future<void> Function(String identityId, String assignmentType) onAdd;
  final Future<void> Function(String assignmentId) onRemove;

  const _EntityTypeCard({
    required this.entityTypeName,
    required this.entityTypeCode,
    required this.owner,
    required this.stewards,
    required this.users,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
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
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(entityTypeCode,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.primary)),
              ),
              const SizedBox(width: 10),
              Text(entityTypeName, style: AppTextStyles.titleSmall),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 16),

            // Data Owner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.person_pin_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text('Data Owner',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.warning)),
                ]),
                if (owner == null)
                  _AddButton(
                    label: 'Assign Owner',
                    users: users,
                    excludeIds: const [],
                    onSelected: (id) => onAdd(id, 'owner'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (owner != null)
              _AssignmentChip(
                assignment: owner!,
                isOwner: true,
                onRemove: () => onRemove(owner!.assignmentId),
              )
            else
              Text('No Data Owner assigned',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),

            const SizedBox(height: 16),

            // Stewards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.manage_accounts_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Stewards',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.primary)),
                ]),
                _AddButton(
                  label: 'Add Steward',
                  users: users,
                  excludeIds: stewards.map((s) => s.identityId).toList(),
                  onSelected: (id) => onAdd(id, 'steward'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (stewards.isEmpty)
              Text('No stewards assigned',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stewards
                    .map((s) => _AssignmentChip(
                          assignment: s,
                          isOwner: false,
                          onRemove: () => onRemove(s.assignmentId),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentChip extends StatelessWidget {
  final GovernanceAssignment assignment;
  final bool isOwner;
  final VoidCallback onRemove;

  const _AssignmentChip({
    required this.assignment,
    required this.isOwner,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = assignment.displayLabel;
    return Chip(
      backgroundColor: isOwner
          ? AppColors.warning.withValues(alpha: 0.12)
          : AppColors.primary.withValues(alpha: 0.1),
      side: BorderSide(
        color: isOwner
            ? AppColors.warning.withValues(alpha: 0.4)
            : AppColors.primary.withValues(alpha: 0.3),
      ),
      avatar: CircleAvatar(
        backgroundColor: isOwner ? AppColors.warning : AppColors.primary,
        radius: 10,
        child: Text(
          label.substring(0, 1).toUpperCase(),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold),
        ),
      ),
      label: Text(label, style: AppTextStyles.labelSmall),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onRemove,
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final List<TenantUserModel> users;
  final List<String> excludeIds;
  final void Function(String identityId) onSelected;

  const _AddButton({
    required this.label,
    required this.users,
    required this.excludeIds,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showPicker(context),
      icon: const Icon(Icons.add, size: 14),
      label: Text(label, style: AppTextStyles.labelSmall),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final available = users.where((u) => !excludeIds.contains(u.id)).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Select User', style: AppTextStyles.titleSmall),
        content: SizedBox(
          width: 320,
          child: available.isEmpty
              ? Text('No available users.', style: AppTextStyles.bodySmall)
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final u = available[i];
                    final display =
                        u.fullName.isNotEmpty ? u.fullName : u.email;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        radius: 16,
                        child: Text(
                          display.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                              color: AppColors.primary, fontSize: 12),
                        ),
                      ),
                      title: Text(display, style: AppTextStyles.bodyMedium),
                      subtitle: u.fullName.isNotEmpty
                          ? Text(u.email, style: AppTextStyles.bodySmall)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onSelected(u.id);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

