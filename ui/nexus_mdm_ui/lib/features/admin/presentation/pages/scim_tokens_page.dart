import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class ScimTokensPage extends StatefulWidget {
  const ScimTokensPage({super.key});

  @override
  State<ScimTokensPage> createState() => _ScimTokensPageState();
}

class _ScimTokensPageState extends State<ScimTokensPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _tokens = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final resp = await _api.get<Map<String, dynamic>>('/scim/tokens');
      final list = (resp.data?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() { _tokens = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _createToken() async {
    final descCtrl = TextEditingController();
    final expiryCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Create SCIM Token', style: AppTextStyles.titleMedium),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCIM tokens allow your Identity Provider (Okta, Azure AD, etc.) to '
                'provision users automatically via the SCIM 2.0 API.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                style: AppTextStyles.bodyMedium,
                decoration: _inputDecoration('Description (e.g. Okta SCIM integration)'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expiryCtrl,
                style: AppTextStyles.bodyMedium,
                decoration: _inputDecoration('Expiry date (YYYY-MM-DD, optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true || descCtrl.text.isEmpty) return;

    try {
      final body = {
        'description': descCtrl.text.trim(),
      };
      if (expiryCtrl.text.trim().isNotEmpty) {
        body['expires_at'] = '${expiryCtrl.text.trim()}T23:59:59Z';
      }

      final resp = await _api.post<Map<String, dynamic>>('/scim/tokens', data: body);
      final raw = resp.data?['data']?['raw_token'] as String? ?? '';

      if (mounted) {
        await _showRawToken(raw);
        _loadTokens();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showRawToken(String rawToken) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
            const SizedBox(width: 8),
            Text('Token Created', style: AppTextStyles.titleMedium),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Copy this token now â€” it will NOT be shown again.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Bearer Token', style: AppTextStyles.labelSmall),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: SelectableText(
                  rawToken,
                  style: AppTextStyles.bodySmall.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Use this as the Authorization header in your IdP\'s SCIM configuration:\n'
                'Authorization: Bearer <token>',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawToken));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Token copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Token'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(Map<String, dynamic> token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Revoke Token?', style: AppTextStyles.titleMedium),
        content: Text(
          'Revoke "${token['description']}"? Any IdP configured to use this token will immediately lose access.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete<void>('/scim/tokens/${token['token_id']}');
      _loadTokens();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('SCIM 2.0 Provisioning', style: AppTextStyles.titleLarge),
        actions: [
          FilledButton.icon(
            onPressed: _createToken,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Token'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTokens),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoBanner(),
                Expanded(child: _buildTokenList()),
              ],
            ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('SCIM 2.0 Automatic User Provisioning', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'SCIM tokens allow your Identity Provider (Okta, Azure AD, Ping Identity, etc.) to '
            'automatically create, update, and deactivate user accounts in Azile MDM.\n\n'
            'SCIM Base URL: https://your-domain.com/scim/{tenant-id}/v2/',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 8),
          SelectableText(
            'https://your-domain.com/scim/{tenant-id}/v2/',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.cyan, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenList() {
    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)));
    }

    if (_tokens.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.token_outlined, size: 64, color: AppColors.secondaryText),
            const SizedBox(height: 16),
            Text('No SCIM tokens', style: AppTextStyles.titleMedium.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 8),
            Text('Create a token to configure your IdP for SCIM provisioning.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _createToken,
              icon: const Icon(Icons.add),
              label: const Text('Create First Token'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: _tokens.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tokenCard(_tokens[i]),
    );
  }

  Widget _tokenCard(Map<String, dynamic> token) {
    final isActive  = token['is_active'] as bool? ?? true;
    final desc      = token['description'] as String? ?? 'â€”';
    final createdAt = _fmtDate(token['created_at'] as String?);
    final lastUsed  = _fmtDate(token['last_used_at'] as String?);
    final expiresAt = _fmtDate(token['expires_at'] as String?);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.divider : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? AppColors.success : AppColors.error,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(desc, style: AppTextStyles.labelLarge)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Revoked',
                        style: AppTextStyles.chipLabel.copyWith(
                            color: isActive ? AppColors.success : AppColors.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Created $createdAt'
                  '${lastUsed != null ? '  Â·  Last used $lastUsed' : ''}'
                  '${expiresAt != null ? '  Â·  Expires $expiresAt' : ''}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => _revoke(token),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
              ),
              child: const Text('Revoke'),
            ),
          ],
        ],
      ),
    );
  }

  String? _fmtDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
    filled: true,
    fillColor: AppColors.inputFill,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.divider)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.divider)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
  );
}
