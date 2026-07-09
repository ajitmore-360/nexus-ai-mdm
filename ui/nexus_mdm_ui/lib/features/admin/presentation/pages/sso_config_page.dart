import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/auth/auth_manager.dart';

class SsoConfigPage extends StatefulWidget {
  const SsoConfigPage({super.key});

  @override
  State<SsoConfigPage> createState() => _SsoConfigPageState();
}

class _SsoConfigPageState extends State<SsoConfigPage> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String _error = '';

  // Form state
  String _providerType = 'saml';
  bool _isEnabled = false;
  final _idpEntityId    = TextEditingController();
  final _idpSsoUrl      = TextEditingController();
  final _idpSloUrl      = TextEditingController();
  final _idpCert        = TextEditingController();
  final _spEntityId     = TextEditingController();
  final _spAcsUrl       = TextEditingController();
  String _defaultRole   = 'steward';
  bool _autoProvision   = true;
  bool _autoDeprovision = false;

  // Computed from tenant info
  String _tenantId = '';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _idpEntityId.dispose();
    _idpSsoUrl.dispose();
    _idpSloUrl.dispose();
    _idpCert.dispose();
    _spEntityId.dispose();
    _spAcsUrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() { _loading = true; _error = ''; });
    try {
      _tenantId = await AuthManager.getTenantId() ?? '';
      final resp = await _api.get<Map<String, dynamic>>('/sso-configurations');
      final cfg = resp.data?['data'] as Map<String, dynamic>?;
      if (cfg != null) {
        setState(() {
          _providerType    = cfg['provider_type'] as String? ?? 'saml';
          _isEnabled       = cfg['is_enabled'] as bool? ?? false;
          _idpEntityId.text = cfg['idp_entity_id'] as String? ?? '';
          _idpSsoUrl.text  = cfg['idp_sso_url'] as String? ?? '';
          _idpSloUrl.text  = cfg['idp_slo_url'] as String? ?? '';
          _idpCert.text    = cfg['idp_certificate'] as String? ?? '';
          _spEntityId.text = cfg['sp_entity_id'] as String? ?? '';
          _spAcsUrl.text   = cfg['sp_acs_url'] as String? ?? '';
          _defaultRole     = cfg['default_role'] as String? ?? 'steward';
          _autoProvision   = cfg['auto_provision'] as bool? ?? true;
          _autoDeprovision = cfg['auto_deprovision'] as bool? ?? false;
        });
      } else {
        // Populate SP defaults
        setState(() {
          _spEntityId.text = 'https://your-domain.com/saml/$_tenantId/metadata';
          _spAcsUrl.text   = 'https://your-domain.com/saml/$_tenantId/acs';
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = ''; });
    try {
      await _api.put<Map<String, dynamic>>('/sso-configurations', data: {
        'provider_type':  _providerType,
        'is_enabled':     _isEnabled,
        'idp_entity_id':  _idpEntityId.text.trim().isNotEmpty ? _idpEntityId.text.trim() : null,
        'idp_sso_url':    _idpSsoUrl.text.trim().isNotEmpty ? _idpSsoUrl.text.trim() : null,
        'idp_slo_url':    _idpSloUrl.text.trim().isNotEmpty ? _idpSloUrl.text.trim() : null,
        'idp_certificate': _idpCert.text.trim().isNotEmpty ? _idpCert.text.trim() : null,
        'sp_entity_id':   _spEntityId.text.trim().isNotEmpty ? _spEntityId.text.trim() : null,
        'sp_acs_url':     _spAcsUrl.text.trim().isNotEmpty ? _spAcsUrl.text.trim() : null,
        'default_role':   _defaultRole,
        'auto_provision': _autoProvision,
        'auto_deprovision': _autoDeprovision,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSO configuration saved')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete SSO Config', style: AppTextStyles.titleMedium),
        content: Text('Remove $_providerType SSO configuration? This will disable SSO for all users.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete<void>('/sso-configurations/$_providerType');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSO configuration deleted')),
        );
        _loadConfig();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Enterprise SSO', style: AppTextStyles.titleLarge),
        actions: [
          if (!_loading) ...[
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: AppColors.error, size: 18),
              label: Text('Remove', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
            ),
            const SizedBox(width: 8),
            _saving
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(_error, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                      ),
                    _buildCard('General', [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Provider', style: AppTextStyles.labelSmall),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: _providerType,
                                  dropdownColor: AppColors.surface,
                                  decoration: _inputDecoration('Provider Type'),
                                  items: const [
                                    DropdownMenuItem(value: 'saml', child: Text('SAML 2.0')),
                                    DropdownMenuItem(value: 'oidc', child: Text('OpenID Connect')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() => _providerType = v); },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Status', style: AppTextStyles.labelSmall),
                              const SizedBox(height: 4),
                              Switch(
                                value: _isEnabled,
                                onChanged: (v) => setState(() => _isEnabled = v),
                                activeThumbColor: AppColors.primary,
                              ),
                              Text(_isEnabled ? 'Enabled' : 'Disabled',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: _isEnabled ? AppColors.success : AppColors.secondaryText)),
                            ],
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildCard('Identity Provider (IdP) Settings', [
                      _field('IdP Entity ID', _idpEntityId,
                          hint: 'https://accounts.google.com/o/saml2/...'),
                      const SizedBox(height: 12),
                      _field('IdP SSO URL (Redirect Binding)', _idpSsoUrl,
                          hint: 'https://your-idp.com/sso/saml'),
                      const SizedBox(height: 12),
                      _field('IdP SLO URL (Single Logout, optional)', _idpSloUrl,
                          hint: 'https://your-idp.com/slo/saml', required: false),
                      const SizedBox(height: 12),
                      _field('IdP X.509 Certificate (PEM or base64)', _idpCert,
                          hint: 'Paste the certificate from your IdP metadata',
                          maxLines: 6, required: false),
                    ]),
                    const SizedBox(height: 16),
                    _buildCard('Service Provider (SP) Settings', [
                      _readOnlyField('SP Entity ID (Metadata URL)', _spEntityId.text),
                      const SizedBox(height: 12),
                      _readOnlyField('Assertion Consumer Service URL', _spAcsUrl.text),
                      const SizedBox(height: 8),
                      Text(
                        'Download SP metadata to configure in your IdP:',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () {
                          final url = _spEntityId.text;
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Metadata URL copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Metadata URL'),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildCard('Provisioning Policy', [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Default Role for New Users', style: AppTextStyles.labelSmall),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: _defaultRole,
                                  dropdownColor: AppColors.surface,
                                  decoration: _inputDecoration('Default Role'),
                                  items: const [
                                    DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                                    DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
                                    DropdownMenuItem(value: 'steward', child: Text('Data Steward')),
                                    DropdownMenuItem(value: 'business_admin', child: Text('Business Admin')),
                                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() => _defaultRole = v); },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _switchRow('Auto-Provision', 'Create users on first login', _autoProvision, (v) => setState(() => _autoProvision = v)),
                              const SizedBox(height: 8),
                              _switchRow('Auto-Deprovision', 'Deactivate removed users', _autoDeprovision, (v) => setState(() => _autoDeprovision = v)),
                            ],
                          ),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.1)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String hint = '', int maxLines = 1, bool required = true}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      style: AppTextStyles.bodyMedium,
      decoration: _inputDecoration(label).copyWith(hintText: hint),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? '$label is required' : null
          : null,
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(value.isEmpty ? '(saved after first save)' : value,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: value.isEmpty ? AppColors.secondaryText : AppColors.primaryText)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _switchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.labelMedium),
            Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
    filled: true,
    fillColor: AppColors.inputFill,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.divider)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.divider)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.primary, width: 2)),
  );
}
