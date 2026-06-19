import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/admin_repository.dart';
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

  // In production, derive tenantId from auth context.
  static const _tenantId = '';

  @override
  void initState() {
    super.initState();
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
        tenantId: _tenantId,
        onInvited: _load,
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
                  child: Text(
                    u.fullName,
                    style: AppTextStyles.tableCell
                        .copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
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
  final VoidCallback onInvited;
  const _InviteUserDialog(
      {required this.tenantId, required this.onInvited});

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final _repo = GetIt.instance<AdminRepository>();
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _role = 'viewer';
  bool _submitting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final result = await _repo.inviteUser(
      tenantId: widget.tenantId,
      email: _emailCtrl.text.trim(),
      fullName: _nameCtrl.text.trim(),
      role: _role,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success():
        widget.onInvited();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text('Invitation sent to ${_emailCtrl.text}',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.success)),
        ));
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Invite User', style: AppTextStyles.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.secondaryText),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    AdminFormField(
                      label: 'FULL NAME',
                      controller: _nameCtrl,
                      hint: 'Alex Chen',
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    AdminFormField(
                      label: 'EMAIL',
                      controller: _emailCtrl,
                      hint: 'alex@company.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    AdminDropdownField<String>(
                      label: 'ROLE',
                      value: _role,
                      items: const ['admin', 'steward', 'analyst', 'viewer'],
                      onChanged: (v) => setState(() => _role = v!),
                    ),
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
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        )
                      : AdminGradientButton(
                          label: 'Send Invite',
                          onTap: _submit,
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
