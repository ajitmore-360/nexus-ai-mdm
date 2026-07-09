import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/admin_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class LicenseManagementPage extends StatefulWidget {
  const LicenseManagementPage({super.key});

  @override
  State<LicenseManagementPage> createState() => _LicenseManagementPageState();
}

class _LicenseManagementPageState extends State<LicenseManagementPage> {
  final _repo = GetIt.instance<AdminRepository>();

  List<TenantModel> _tenants = [];
  bool _loading = true;
  String? _error;

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
    final result = await _repo.listTenants();
    if (!mounted) return;
    switch (result) {
      case Success<List<TenantModel>>(:final data):
        setState(() {
          _tenants = data;
          _loading = false;
        });
      case Failure<List<TenantModel>>(:final exception):
        setState(() {
          _error = exception.message;
          _loading = false;
        });
    }
  }

  int get _licensedCount =>
      _tenants.where((t) => t.plan.toLowerCase() != 'starter').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
              Text('License Manager', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${_tenants.length} tenants  Â·  $_licensedCount with paid plans',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.secondaryText, size: 20),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
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

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryRow(),
          const SizedBox(height: 24),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final expired = _tenants
        .where((t) => t.status.toLowerCase() == 'suspended')
        .length;
    final active = _tenants
        .where((t) => t.status.toLowerCase() == 'active')
        .length;

    final cards = [
      _SummaryCard(
        icon: Icons.domain_rounded,
        label: 'Total Tenants',
        value: '${_tenants.length}',
        color: AppColors.primary,
      ),
      _SummaryCard(
        icon: Icons.check_circle_outline_rounded,
        label: 'Active',
        value: '$active',
        color: AppColors.success,
      ),
      _SummaryCard(
        icon: Icons.workspace_premium_outlined,
        label: 'Paid Plans',
        value: '$_licensedCount',
        color: AppColors.cyan,
      ),
      _SummaryCard(
        icon: Icons.pause_circle_outline_rounded,
        label: 'Suspended',
        value: '$expired',
        color: AppColors.error,
      ),
    ];

    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: c,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildTable() {
    if (_tenants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text('No tenants found.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.secondaryText)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          ...List.generate(
              _tenants.length, (i) => _buildTableRow(_tenants[i], i)),
        ],
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
          Expanded(flex: 3, child: AdminTableHeader(label: 'TENANT')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'SUBDOMAIN')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'PLAN')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'STATUS')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'REGION')),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTableRow(TenantModel t, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: index < _tenants.length - 1
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    style: AppTextStyles.tableCell
                        .copyWith(fontWeight: FontWeight.w500)),
                Text(t.id,
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${t.subdomain}.azilemdm.io',
              style: AppTextStyles.tableCell
                  .copyWith(color: AppColors.cyan, fontSize: 12),
            ),
          ),
          Expanded(flex: 2, child: AdminPlanChip(plan: t.plan)),
          Expanded(flex: 2, child: AdminStatusChip(status: t.status)),
          Expanded(
            flex: 2,
            child: Text(t.region,
                style: AppTextStyles.tableCell
                    .copyWith(color: AppColors.secondaryText)),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 32),
            color: AppColors.elevatedCard,
            icon: const Icon(Icons.more_horiz,
                size: 16, color: AppColors.secondaryText),
            itemBuilder: (_) => [
              for (final tier in ['Starter', 'Pro', 'Enterprise'])
                if (tier != t.plan)
                  PopupMenuItem(
                    value: 'license:$tier',
                    child: Row(
                      children: [
                        Icon(Icons.workspace_premium_outlined,
                            size: 14,
                            color: _planColor(tier)),
                        const SizedBox(width: 8),
                        Text('Change to $tier',
                            style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'custom',
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined,
                        size: 14, color: AppColors.secondaryText),
                    const SizedBox(width: 8),
                    Text('Customâ€¦', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
            onSelected: (v) {
              if (v.startsWith('license:')) {
                final tier = v.substring(8);
                _confirmAndApply(t, tier);
              } else if (v == 'custom') {
                _showCustomDialog(t);
              }
            },
          ),
        ],
      ),
    );
  }

  Color _planColor(String plan) {
    return switch (plan.toLowerCase()) {
      'enterprise' => AppColors.aiPurple,
      'pro' => AppColors.cyan,
      _ => AppColors.secondaryText,
    };
  }

  Future<void> _confirmAndApply(TenantModel t, String tier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _ConfirmLicenseDialog(tenant: t, newTier: tier),
    );
    if (confirmed != true || !mounted) return;
    await _applyLicense(t.id, tier, null);
  }

  Future<void> _showCustomDialog(TenantModel t) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _CustomLicenseDialog(tenant: t),
    );
    if (result == null || !mounted) return;
    await _applyLicense(t.id, result['tier']!, result['notes']);
  }

  Future<void> _applyLicense(
      String tenantId, String tier, String? notes) async {
    final result = await _repo.updateTenantLicense(
      tenantId,
      tier: tier,
      notes: notes,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(
            'License updated to $tier.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success),
          ),
        ));
        _load();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(
            exception.message,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ));
    }
  }
}

// â”€â”€â”€ Summary card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: AppTextStyles.titleSmall
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 22)),
              Text(label,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Confirm dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ConfirmLicenseDialog extends StatelessWidget {
  final TenantModel tenant;
  final String newTier;
  const _ConfirmLicenseDialog({required this.tenant, required this.newTier});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change License', style: AppTextStyles.titleMedium),
              const SizedBox(height: 12),
              Text(
                'Update "${tenant.name}" from ${tenant.plan} to $newTier?',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel',
                        style: AppTextStyles.buttonMedium
                            .copyWith(color: AppColors.secondaryText)),
                  ),
                  const SizedBox(width: 12),
                  AdminGradientButton(
                    label: 'Confirm',
                    onTap: () => Navigator.of(context).pop(true),
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

// â”€â”€â”€ Custom license dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CustomLicenseDialog extends StatefulWidget {
  final TenantModel tenant;
  const _CustomLicenseDialog({required this.tenant});

  @override
  State<_CustomLicenseDialog> createState() => _CustomLicenseDialogState();
}

class _CustomLicenseDialogState extends State<_CustomLicenseDialog> {
  String _tier = 'Pro';
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
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
                  Text('Issue License', style: AppTextStyles.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.secondaryText),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.tenant.name,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 20),
              AdminDropdownField<String>(
                label: 'PLAN TIER',
                value: _tier,
                items: const ['Starter', 'Pro', 'Enterprise'],
                onChanged: (v) => setState(() => _tier = v!),
              ),
              const SizedBox(height: 14),
              AdminFormField(
                label: 'NOTES (OPTIONAL)',
                controller: _notesCtrl,
                hint: 'e.g. Annual contract renewal',
                maxLines: 2,
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
                    label: 'Apply',
                    onTap: () => Navigator.of(context).pop({
                      'tier': _tier,
                      'notes': _notesCtrl.text.trim(),
                    }),
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
