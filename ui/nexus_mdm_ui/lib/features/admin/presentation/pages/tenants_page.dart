import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/admin_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class TenantsPage extends StatefulWidget {
  const TenantsPage({super.key});

  @override
  State<TenantsPage> createState() => _TenantsPageState();
}

class _TenantsPageState extends State<TenantsPage> {
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

  int get _activeCount =>
      _tenants.where((t) => t.status.toLowerCase() == 'active').length;

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
              Text('Tenants Â· $_activeCount active',
                  style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('Manage platform tenants and their configurations',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ New Tenant',
            onTap: () => _openCreateDialog(context),
          ),
        ],
      ),
    );
  }

  void _openCreateDialog(BuildContext context) {
    context.go('/dashboard/admin/tenants/create');
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_tenants.isEmpty) {
      return Center(
        child: Text('No tenants yet. Create the first one.',
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
                _tenants.length, (i) => _buildTableRow(_tenants[i], i)),
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
          Expanded(flex: 3, child: AdminTableHeader(label: 'TENANT NAME')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'SUBDOMAIN')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'PLAN')),
          Expanded(flex: 1, child: AdminTableHeader(label: 'USERS')),
          Expanded(flex: 1, child: AdminTableHeader(label: 'ENTITIES')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'STATUS')),
          Expanded(flex: 2, child: AdminTableHeader(label: 'REGION')),
        ],
      ),
    );
  }

  Widget _buildTableRow(TenantModel t, int index) {
    return InkWell(
      onTap: () => context.go('/dashboard/admin/tenants/${t.id}'),
      child: Container(
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
                Row(
                  children: [
                    Text(t.name,
                        style: AppTextStyles.tableCell
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded,
                        size: 14, color: AppColors.mutedText),
                  ],
                ),
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
                  .copyWith(color: AppColors.cyan, fontSize: 13),
            ),
          ),
          Expanded(flex: 2, child: AdminPlanChip(plan: t.plan)),
          Expanded(
              flex: 1,
              child:
                  Text(t.maxUsers.toString(), style: AppTextStyles.tableCell)),
          Expanded(
              flex: 1,
              child: Text(t.maxEntities.toString(),
                  style: AppTextStyles.tableCell)),
          Expanded(flex: 2, child: AdminStatusChip(status: t.status)),
          Expanded(
              flex: 2,
              child: Text(t.region, style: AppTextStyles.tableCell)),
        ],
      ),
    ),
    );
  }
}
