import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/admin_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';
import '../../../../core/validation/validators.dart';

class TenantCreatePage extends StatefulWidget {
  const TenantCreatePage({super.key});

  @override
  State<TenantCreatePage> createState() => _TenantCreatePageState();
}

class _TenantCreatePageState extends State<TenantCreatePage> {
  final _repo = GetIt.instance<AdminRepository>();

  int _step = 1;
  bool _submitting = false;

  // Step 1
  final _nameCtrl = TextEditingController();
  final _subdomainCtrl = TextEditingController();
  final _maxUsersCtrl = TextEditingController(text: '50');
  final _maxEntitiesCtrl = TextEditingController(text: '10000');
  String _plan = 'Starter';
  String _region = 'us-east-1';
  final _step1Key = GlobalKey<FormState>();

  // Step 2
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _step2Key = GlobalKey<FormState>();

  TenantModel? _createdTenant;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subdomainCtrl.dispose();
    _maxUsersCtrl.dispose();
    _maxEntitiesCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _autoGeneratePassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$';
    final rng = Random.secure();
    final pwd =
        List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
    setState(() => _passwordCtrl.text = pwd);
  }

  Future<void> _goToStep2() async {
    if (_step1Key.currentState == null || !_step1Key.currentState!.validate()) return;
    setState(() => _submitting = true);

    final result = await _repo.createTenant(
      name: _nameCtrl.text.trim(),
      subdomain: _subdomainCtrl.text.trim(),
      plan: _plan,
      maxUsers: int.tryParse(_maxUsersCtrl.text) ?? 50,
      maxEntities: int.tryParse(_maxEntitiesCtrl.text) ?? 10000,
      region: _region,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case Success<TenantModel>(:final data):
        setState(() {
          _createdTenant = data;
          _step = 2;
        });
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        ));
    }
  }

  Future<void> _submitStep2() async {
    if (_step2Key.currentState == null || !_step2Key.currentState!.validate()) return;
    if (_createdTenant == null) return;
    setState(() => _submitting = true);

    final result = await _repo.createAdminUser(
      _createdTenant!.id,
      email: _emailCtrl.text.trim(),
      fullName: '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
      tempPassword: _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(
              'Tenant "${_createdTenant!.name}" created successfully.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success)),
        ));
        context.go('/dashboard/admin/tenants');
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
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildStepIndicator(),
                  const SizedBox(height: 24),
                  if (_step == 1) _buildStep1(),
                  if (_step == 2) _buildStep2(),
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.domain_add_outlined,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Tenant', style: AppTextStyles.titleMedium),
            Text(
              _step == 1
                  ? 'Step 1 of 2 Â· Tenant details'
                  : 'Step 2 of 2 Â· Admin user',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close,
              size: 18, color: AppColors.secondaryText),
          onPressed: () => context.go('/dashboard/admin/tenants'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _StepDot(number: 1, active: _step == 1, done: _step > 1, label: 'Tenant'),
        Expanded(
          child: Container(
            height: 1,
            color: _step > 1 ? AppColors.primary : AppColors.divider,
          ),
        ),
        _StepDot(number: 2, active: _step == 2, done: false, label: 'Admin User'),
      ],
    );
  }

  Widget _buildStep1() {
    return Form(
      key: _step1Key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminFormField(
            label: 'TENANT NAME',
            controller: _nameCtrl,
            hint: 'Acme Corporation',
            validator: Validators.required('Tenant name'),
          ),
          const SizedBox(height: 16),
          AdminFormField(
            label: 'SUBDOMAIN',
            controller: _subdomainCtrl,
            hint: 'acme',
            suffixText: '.azilemdm.io',
            validator: Validators.subdomain,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AdminDropdownField<String>(
                  label: 'PLAN',
                  value: _plan,
                  items: const ['Starter', 'Pro', 'Enterprise'],
                  onChanged: (v) => setState(() => _plan = v!),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminDropdownField<String>(
                  label: 'REGION',
                  value: _region,
                  items: const [
                    'us-east-1',
                    'us-west-2',
                    'eu-west-1',
                    'eu-central-1',
                    'ap-southeast-1',
                  ],
                  onChanged: (v) => setState(() => _region = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AdminFormField(
                  label: 'MAX USERS',
                  controller: _maxUsersCtrl,
                  keyboardType: TextInputType.number,
                  validator: Validators.number(min: 1, label: 'Max users'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminFormField(
                  label: 'MAX ENTITIES',
                  controller: _maxEntitiesCtrl,
                  keyboardType: TextInputType.number,
                  validator: Validators.number(min: 1, label: 'Max entities'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _step2Key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AdminFormField(
                  label: 'FIRST NAME',
                  controller: _firstNameCtrl,
                  hint: 'Alex',
                  validator: Validators.required('First name'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminFormField(
                  label: 'LAST NAME',
                  controller: _lastNameCtrl,
                  hint: 'Chen',
                  validator: Validators.required('Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AdminFormField(
            label: 'EMAIL',
            controller: _emailCtrl,
            hint: 'admin@acme.com',
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          AdminFormField(
            label: 'TEMPORARY PASSWORD',
            controller: _passwordCtrl,
            hint: 'Auto-generated if empty',
            obscureText: true,
            suffix: TextButton(
              onPressed: _autoGeneratePassword,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(
                'Auto-generate',
                style: AppTextStyles.buttonSmall
                    .copyWith(color: AppColors.violetLight),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 8) ? 'At least 8 characters' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => context.go('/dashboard/admin/tenants'),
          child: Text('Cancel',
              style: AppTextStyles.buttonMedium
                  .copyWith(color: AppColors.secondaryText)),
        ),
        if (_step == 2) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _step = 1),
            child: Text('Back',
                style: AppTextStyles.buttonMedium
                    .copyWith(color: AppColors.secondaryText)),
          ),
        ],
        const SizedBox(width: 12),
        _submitting
            ? const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            : AdminGradientButton(
                label: _step == 1 ? 'Next â†’' : 'Create Tenant',
                onTap: _step == 1 ? _goToStep2 : _submitStep2,
              ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Step dot indicator
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StepDot extends StatelessWidget {
  final int number;
  final bool active;
  final bool done;
  final String label;
  const _StepDot(
      {required this.number,
      required this.active,
      required this.done,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final Color c = done
        ? AppColors.success
        : (active ? AppColors.primary : AppColors.mutedText);
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 1.5),
          ),
          child: Center(
            child: done
                ? Icon(Icons.check, size: 14, color: c)
                : Text('$number',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: c, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: AppTextStyles.labelSmall.copyWith(
                color: active ? AppColors.primaryText : AppColors.mutedText,
                fontSize: 10)),
      ],
    );
  }
}
