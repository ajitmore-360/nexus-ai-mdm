import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/admin_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class TenantDetailPage extends StatefulWidget {
  final String tenantId;
  const TenantDetailPage({super.key, required this.tenantId});

  @override
  State<TenantDetailPage> createState() => _TenantDetailPageState();
}

class _TenantDetailPageState extends State<TenantDetailPage> {
  final _repo = GetIt.instance<AdminRepository>();

  bool _loadingTenants = true;
  bool _loadingUsers   = true;
  TenantModel? _tenant;
  List<TenantUserModel> _users = [];
  String? _tenantError;
  String? _usersError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTenant(), _loadUsers()]);
  }

  Future<void> _loadTenant() async {
    setState(() { _loadingTenants = true; _tenantError = null; });
    final result = await _repo.listTenants();
    if (!mounted) return;
    switch (result) {
      case Success<List<TenantModel>>(:final data):
        final match = data.where((t) => t.id == widget.tenantId).firstOrNull;
        setState(() {
          _tenant = match;
          _loadingTenants = false;
          if (match == null) _tenantError = 'Tenant not found';
        });
      case Failure<List<TenantModel>>(:final exception):
        setState(() { _tenantError = exception.message; _loadingTenants = false; });
    }
  }

  Future<void> _loadUsers() async {
    setState(() { _loadingUsers = true; _usersError = null; });
    final result = await _repo.listUsers(widget.tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<TenantUserModel>>(:final data):
        setState(() { _users = data; _loadingUsers = false; });
      case Failure<List<TenantUserModel>>(:final exception):
        setState(() { _usersError = exception.message; _loadingUsers = false; _users = []; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.pageHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumb(context),
          const SizedBox(height: 16),
          if (_loadingTenants)
            _shimmer(double.infinity, 120)
          else if (_tenantError != null)
            _buildError(_tenantError!, _loadTenant)
          else if (_tenant != null) ...[
            _buildTenantHeader(_tenant!),
            const SizedBox(height: 24),
            _buildMetricRow(_tenant!),
            const SizedBox(height: 24),
          ],
          _buildUsersSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => context.go('/dashboard/admin/tenants'),
          borderRadius: BorderRadius.circular(4),
          child: Text('Tenants',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('/', style: TextStyle(color: AppColors.mutedText)),
        ),
        Text(
          _tenant?.name ?? widget.tenantId,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildTenantHeader(TenantModel t) {
    final isActive = t.status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                t.name.isNotEmpty ? t.name[0].toUpperCase() : '?',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(t.name, style: AppTextStyles.titleMedium),
                    const SizedBox(width: 10),
                    AdminStatusChip(status: t.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.subdomain}.nexusmdm.io  ·  ${t.region}  ·  ID: ${t.id}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AdminPlanChip(plan: t.plan),
              const SizedBox(height: 8),
              Text(
                'Created ${_formatDate(t.createdAt)}',
                style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedText, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            offset: const Offset(0, 40),
            color: AppColors.elevatedCard,
            tooltip: 'Actions',
            icon: const Icon(Icons.more_vert,
                size: 18, color: AppColors.secondaryText),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy_id',
                child: Row(children: [
                  const Icon(Icons.copy, size: 14, color: AppColors.secondaryText),
                  const SizedBox(width: 8),
                  Text('Copy tenant ID', style: AppTextStyles.bodySmall),
                ]),
              ),
              if (isActive)
                PopupMenuItem(
                  value: 'suspend',
                  child: Row(children: [
                    const Icon(Icons.pause_circle_outline,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Text('Suspend',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.warning)),
                  ]),
                ),
            ],
            onSelected: (v) async {
              if (v == 'copy_id') {
                await Clipboard.setData(ClipboardData(text: t.id));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Tenant ID copied'),
                    duration: Duration(seconds: 2),
                  ));
                }
              }
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMetricRow(TenantModel t) {
    final cards = [
      _MetricTile(label: 'Max Users',     value: '${t.maxUsers}',    icon: Icons.people_outlined,    color: AppColors.primary),
      _MetricTile(label: 'Active Users',  value: '${_users.length}', icon: Icons.person_rounded,     color: AppColors.success),
      _MetricTile(label: 'Max Entities',  value: _compact(t.maxEntities), icon: Icons.category_outlined, color: AppColors.aiPurple),
      _MetricTile(label: 'Plan',          value: t.plan,             icon: Icons.vpn_key_outlined,   color: AppColors.cyan),
    ];

    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      mainAxisExtent: 90,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards.asMap().entries.map((e) =>
        e.value.animate(delay: (e.key * 60).ms).fadeIn(duration: 280.ms),
      ).toList(),
    );
  }

  Widget _buildUsersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Users', style: AppTextStyles.titleSmall),
            const SizedBox(width: 8),
            if (!_loadingUsers)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_users.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary)),
              ),
            const Spacer(),
            AdminGradientButton(
              label: '+ Invite User',
              onTap: () => _showInviteDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingUsers)
          _shimmer(double.infinity, 200)
        else if (_usersError != null)
          _buildError(_usersError!, _loadUsers)
        else if (_users.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Center(
              child: Text('No users yet. Invite the first one.',
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText)),
            ),
          )
        else
          _buildUsersTable(),
      ],
    );
  }

  Widget _buildUsersTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: AdminTableHeader(label: 'USER')),
                Expanded(flex: 2, child: AdminTableHeader(label: 'ROLE')),
                Expanded(flex: 2, child: AdminTableHeader(label: 'STATUS')),
                Expanded(flex: 2, child: AdminTableHeader(label: 'LAST LOGIN')),
                SizedBox(width: 40),
              ],
            ),
          ),
          ..._users.asMap().entries.map((e) => _buildUserRow(e.value, e.key)),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn(duration: 280.ms);
  }

  Widget _buildUserRow(TenantUserModel u, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: index < _users.length - 1
            ? const Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))
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
                    _initials(u.fullName.isNotEmpty ? u.fullName : u.email),
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.fullName.isNotEmpty ? u.fullName : u.email,
                          style: AppTextStyles.tableCell
                              .copyWith(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                      if (u.fullName.isNotEmpty)
                        Text(u.email,
                            style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _RoleChip(role: u.role),
          ),
          Expanded(
            flex: 2,
            child: AdminStatusChip(status: u.status),
          ),
          Expanded(
            flex: 2,
            child: Text(
              u.lastLoginAt != null ? _formatDate(u.lastLoginAt!) : 'Never',
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.secondaryText),
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
                _loadUsers();
              }
            },
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
        tenantId: widget.tenantId,
        onInvited: _loadUsers,
      ),
    );
  }

  Widget _buildError(String msg, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 32),
          const SizedBox(height: 8),
          Text(msg, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _shimmer(double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(12),
    ),
  );

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

// ─── Invite user dialog ────────────────────────────────────────────────────────

class _InviteUserDialog extends StatefulWidget {
  final String tenantId;
  final VoidCallback onInvited;
  const _InviteUserDialog({required this.tenantId, required this.onInvited});

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final _repo = GetIt.instance<AdminRepository>();
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _nameCtrl     = TextEditingController();
  String _role = 'steward';
  bool _submitting = false;
  String? _inviteToken;

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
      email:    _emailCtrl.text.trim(),
      fullName: _nameCtrl.text.trim(),
      role:     _role,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success<String>(:final data):
        setState(() => _inviteToken = data);
        widget.onInvited();
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _inviteToken != null
              ? _buildTokenView(_inviteToken!)
              : _buildForm(),
        ),
      ),
    );
  }

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
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            children: [
              AdminFormField(
                label: 'FULL NAME',
                controller: _nameCtrl,
                hint: 'Alex Chen',
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              AdminFormField(
                label: 'EMAIL ADDRESS',
                controller: _emailCtrl,
                hint: 'alex@company.com',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AdminDropdownField<String>(
                label: 'ROLE',
                value: _role,
                items: const ['admin', 'steward', 'viewer'],
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
            AdminGradientButton(
              label: 'Send Invite',
              loading: _submitting,
              onTap: _submit,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTokenView(String token) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              SizedBox(width: 8),
              Text('Invite created!',
                  style: TextStyle(color: AppColors.success, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Share this token with the user:',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.navyBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  token.isNotEmpty ? token : '(no token returned)',
                  style: AppTextStyles.labelSmall.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.cyan,
                  ),
                ),
              ),
              if (token.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy, size: 14, color: AppColors.mutedText),
                  onPressed: () => Clipboard.setData(ClipboardData(text: token)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: AdminGradientButton(
            label: 'Done',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

// ─── Small widgets ─────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: AppTextStyles.titleSmall.copyWith(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(label,
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.secondaryText),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role.toLowerCase()) {
      'admin'          => AppColors.primary,
      'business_admin' => const Color(0xFF6366F1),
      'steward'        => AppColors.cyan,
      'analyst'        => AppColors.warning,
      _                => AppColors.mutedText,
    };
    final label = switch (role.toLowerCase()) {
      'business_admin' => 'Business Admin',
      'super_admin'    => 'Product Admin',
      _                => role.isEmpty ? 'unknown' : role,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}
