import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/admin_repository.dart';
import '../../data/entity_type_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _repo = GetIt.instance<AdminRepository>();
  List<TenantUserModel> _users = [];
  bool _loading = true;
  String? _error;
  String _tenantId   = '';
  String _tenantName = '';
  String _userRole   = '';
  List<TenantModel> _allTenants = [];

  @override
  void initState() {
    super.initState();
    _initTenantAndLoad();
  }

  Future<void> _initTenantAndLoad() async {
    _tenantId   = await AuthManager.getTenantId()   ?? '';
    _tenantName = await AuthManager.getTenantName() ?? '';
    _userRole   = await AuthManager.getUserRole()   ?? '';
    if (_userRole == 'super_admin') {
      final result = await _repo.listTenants();
      if (result case Success<List<TenantModel>>(:final data)) {
        _allTenants = data;
      }
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.listUsers(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<TenantUserModel>>(:final data):
        setState(() {
          _users = data;
          _loading = false;
        });
      case Failure<List<TenantUserModel>>(:final exception):
        setState(() {
          _error = exception.message;
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _buildTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Users & Roles', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('${_users.length} members in this organisation',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Invite User',
            onTap: () => _showInviteDialog(context),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _InviteUserDialog(
        tenantId:   _tenantId,
        tenantName: _tenantName,
        isITAdmin:  _userRole == 'super_admin',
        tenants:    _allTenants,
        onInvited:  _load,
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_users.isEmpty) {
      return Center(
        child: Text('No users yet. Invite your first team member.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            _buildTableHeader(),
            ...List.generate(
                _users.length, (i) => _buildTableRow(_users[i], i)),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: AdminTableHeader(label: 'USER')),
          Expanded(flex: 3, child: AdminTableHeader(label: 'EMAIL')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'ROLE')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'STATUS')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'LAST LOGIN')),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTableRow(TenantUserModel u, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: index < _users.length - 1
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    u.fullName.isNotEmpty
                        ? u.fullName[0].toUpperCase()
                        : '?',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.fullName.isNotEmpty ? u.fullName : u.email,
                        style: AppTextStyles.tableCell
                            .copyWith(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (u.fullName.isNotEmpty)
                        Text(u.email,
                            style: AppTextStyles.bodySmall
                                .copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(u.email,
                style: AppTextStyles.tableCell
                    .copyWith(color: AppColors.secondaryText),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(flex: 2, child: AdminRoleChip(role: u.role)),
          Expanded(flex: 2, child: AdminStatusChip(status: u.status)),
          Expanded(
            flex: 2,
            child: Text(
              u.lastLoginAt != null ? _formatDate(u.lastLoginAt!) : 'Never',
              style: AppTextStyles.tableCell.copyWith(
                color: u.lastLoginAt != null
                    ? AppColors.secondaryText
                    : AppColors.mutedText,
              ),
            ),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 32),
            color: AppColors.elevatedCard,
            icon: const Icon(Icons.more_horiz,
                size: 16, color: AppColors.secondaryText),
            itemBuilder: (_) => [
              for (final role in ['admin', 'business_admin', 'steward', 'analyst', 'viewer'])
                if (role != u.role.toLowerCase())
                  PopupMenuItem(
                    value: 'role:$role',
                    child: Text('Set as $role',
                        style: AppTextStyles.bodySmall),
                  ),
            ],
            onSelected: (v) async {
              if (v.startsWith('role:')) {
                final newRole = v.substring(5);
                await _repo.updateUserRole(u.id, newRole);
                _load();
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invite dialog
// ─────────────────────────────────────────────────────────────────────────────

class _InviteUserDialog extends StatefulWidget {
  final String tenantId;
  final String tenantName;
  final bool isITAdmin;
  final List<TenantModel> tenants;
  final VoidCallback onInvited;
  const _InviteUserDialog({
    required this.tenantId,
    required this.tenantName,
    required this.onInvited,
    this.isITAdmin = false,
    this.tenants   = const [],
  });

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final _repo      = GetIt.instance<AdminRepository>();
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  // ITAdmin defaults to business_admin; other roles default to viewer.
  late String _role = widget.isITAdmin ? 'business_admin' : 'viewer';
  String? _selectedTenantId;
  bool    _submitting  = false;
  bool    _copied      = false;
  // Non-null once the invite API succeeds; dialog transforms to copy-link state.
  String? _inviteToken;

  // Steward entity type assignment
  List<EntityTypeModel> _availableEntityTypes = [];
  Set<String>           _selectedEntityTypes  = {};
  bool                  _loadingEntityTypes   = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the first tenant so the dropdown has a valid initial value.
    if (widget.isITAdmin && widget.tenants.isNotEmpty) {
      _selectedTenantId = widget.tenants.first.id;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntityTypes() async {
    final tid = widget.isITAdmin ? (_selectedTenantId ?? '') : widget.tenantId;
    if (tid.isEmpty) return;
    setState(() => _loadingEntityTypes = true);
    final result = await GetIt.instance<EntityTypeRepository>().listEntityTypes(tid);
    if (!mounted) return;
    setState(() {
      _loadingEntityTypes = false;
      if (result case Success<List<EntityTypeModel>>(:final data)) {
        _availableEntityTypes = data.where((e) => e.isActive).toList();
      }
    });
  }

  String get _activationLink {
    final token = _inviteToken ?? '';
    if (token.isEmpty) return '';
    return kIsWeb
        ? '${Uri.base.origin}/activate?token=$token'
        : 'activate?token=$token';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'steward' && _selectedEntityTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.cardSurface,
        content: Text(
          'Select at least one entity type for the steward.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
        ),
      ));
      return;
    }
    setState(() => _submitting = true);
    final result = await _repo.inviteUser(
      tenantId:              widget.tenantId,
      email:                 _emailCtrl.text.trim(),
      fullName:              _nameCtrl.text.trim(),
      role:                  _role,
      targetTenantId:        widget.isITAdmin ? _selectedTenantId : null,
      entityTypeAssignments: _role == 'steward' ? _selectedEntityTypes.toList() : null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success(:final data):
        widget.onInvited();
        // Transform dialog in-place — no context juggling needed.
        setState(() => _inviteToken = data);
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _inviteToken != null ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  // ── Success state — shows activation link for copying ──────────────────────

  Widget _buildSuccess() {
    final link     = _activationLink;
    final copyText = link.isNotEmpty ? link : (_inviteToken ?? '');
    final email    = _emailCtrl.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_add_rounded,
                  size: 16, color: AppColors.success),
            ),
            const SizedBox(width: 10),
            Text('User invited', style: AppTextStyles.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.secondaryText),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Send this activation link to $email. '
          'They must open it to set their password.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 4),
        Text(
          'An email was also sent via the notification service.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  copyText.isEmpty
                      ? '(token unavailable — check server logs)'
                      : copyText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _copied ? 'Copied!' : 'Copy link',
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                  color: _copied ? AppColors.success : AppColors.mutedText,
                ),
                onPressed: copyText.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: copyText));
                        setState(() => _copied = true);
                      },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Link expires in 7 days.',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  // ── Form state ─────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Invite User', style: AppTextStyles.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.secondaryText),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (widget.isITAdmin) ...[
          // ITAdmin picks the target tenant from all available tenants.
          Text('Select tenant', style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.secondaryText, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          widget.tenants.isEmpty
              ? Text('No tenants available',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText))
              : DropdownButtonFormField<String>(
                  initialValue: _selectedTenantId,
                  dropdownColor: AppColors.elevatedCard,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                  items: widget.tenants.map((t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(t.name, style: AppTextStyles.bodySmall),
                  )).toList(),
                  onChanged: (v) {
                    setState(() => _selectedTenantId = v);
                    if (_role == 'steward') {
                      setState(() {
                        _selectedEntityTypes.clear();
                        _availableEntityTypes.clear();
                      });
                      _loadEntityTypes();
                    }
                  },
                  validator: (_) => _selectedTenantId == null ? 'Select a tenant' : null,
                ),
        ] else if (widget.tenantName.isNotEmpty) ...[
          Text(
            'Inviting to ${widget.tenantName}',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
          ),
        ],
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            children: [
              AdminFormField(
                label:      'FULL NAME',
                controller: _nameCtrl,
                hint:       'Alex Chen',
                validator:  (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              AdminFormField(
                label:        'EMAIL',
                controller:   _emailCtrl,
                hint:         'alex@company.com',
                keyboardType: TextInputType.emailAddress,
                validator:    (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AdminDropdownField<String>(
                label:     'ROLE',
                value:     _role,
                items:     const ['admin', 'business_admin', 'steward', 'analyst', 'viewer'],
                onChanged: (v) {
                  final prev = _role;
                  setState(() => _role = v!);
                  if (v == 'steward' && prev != 'steward') {
                    _selectedEntityTypes.clear();
                    _loadEntityTypes();
                  } else if (v != 'steward') {
                    setState(() {
                      _selectedEntityTypes.clear();
                      _availableEntityTypes.clear();
                    });
                  }
                },
              ),
              if (_role == 'steward') ...[
                const SizedBox(height: 14),
                Text(
                  'ENTITY TYPE RESPONSIBILITY',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.secondaryText, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                if (_loadingEntityTypes)
                  const SizedBox(
                    height: 36,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    ),
                  )
                else if (_availableEntityTypes.isEmpty)
                  Text(
                    'No active entity types configured for this tenant.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.mutedText),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _availableEntityTypes.map((et) {
                      final sel = _selectedEntityTypes.contains(et.code);
                      return FilterChip(
                        label: Text(et.name),
                        selected: sel,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedEntityTypes.add(et.code);
                          } else {
                            _selectedEntityTypes.remove(et.code);
                          }
                        }),
                        selectedColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        checkmarkColor: AppColors.primary,
                        backgroundColor: AppColors.surface,
                        side: BorderSide(
                          color: sel ? AppColors.primary : AppColors.divider,
                        ),
                        labelStyle: AppTextStyles.labelSmall.copyWith(
                          color: sel
                              ? AppColors.primary
                              : AppColors.secondaryText,
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: AppTextStyles.buttonMedium
                      .copyWith(color: AppColors.secondaryText)),
            ),
            const SizedBox(width: 12),
            _submitting
                ? const SizedBox(
                    width: 32, height: 32,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2),
                  )
                : AdminGradientButton(label: 'Send Invite', onTap: _submit),
          ],
        ),
      ],
    );
  }
}
