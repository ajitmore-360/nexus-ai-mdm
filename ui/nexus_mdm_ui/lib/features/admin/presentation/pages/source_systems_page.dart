import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/source_systems_repository.dart';
import '../../../../shared/models/api_responses.dart';
import '../widgets/admin_form_widgets.dart';

class SourceSystemsPage extends StatefulWidget {
  const SourceSystemsPage({super.key});

  @override
  State<SourceSystemsPage> createState() => _SourceSystemsPageState();
}

class _SourceSystemsPageState extends State<SourceSystemsPage> {
  final _repo = GetIt.instance<SourceSystemsRepository>();
  List<SourceSystemModel> _sources = [];
  bool _loading = true;
  String? _error;
  final Set<String> _testingIds = {};

  String _tenantId = '';

  @override
  void initState() {
    super.initState();
    _initTenantAndLoad();
  }

  Future<void> _initTenantAndLoad() async {
    _tenantId = await AuthManager.getTenantId() ?? '';
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await _repo.listSourceSystems(_tenantId);
    if (!mounted) return;
    switch (result) {
      case Success<List<SourceSystemModel>>(:final data):
        setState(() { _sources = data; _loading = false; });
      case Failure<List<SourceSystemModel>>(:final exception):
        setState(() { _error = exception.message; _loading = false; });
    }
  }

  Future<void> _testConnection(String id) async {
    setState(() => _testingIds.add(id));
    final result = await _repo.testConnection(id);
    if (!mounted) return;
    setState(() => _testingIds.remove(id));
    final ok = result is Success<bool> && result.data;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.cardSurface,
      content: Text(
        ok ? 'Connection successful!' : 'Connection failed.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: ok ? AppColors.success : AppColors.error,
        ),
      ),
    ));
    if (ok) _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _ConfirmDeleteDialog(),
    );
    if (confirm != true) {
      return;
    }
    await _repo.deleteSourceSystem(id);
    if (!mounted) {
      return;
    }
    _load();
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
                    : _buildGrid(),
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
              Text('Source Systems', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('${_sources.length} connectors configured',
                  style: AppTextStyles.bodySmall),
            ],
          ),
          const Spacer(),
          AdminGradientButton(
            label: '+ Add Source',
            onTap: () => _showAddDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => _AddSourceDialog(
        tenantId: _tenantId,
        onCreated: _load,
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
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_sources.isEmpty) {
      return Center(
        child: Text('No source systems configured yet.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.secondaryText)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 3 : 2;
        final itemWidth =
            (constraints.maxWidth - (crossCount - 1) * 16) / crossCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _sources
              .map((s) => SizedBox(
                    width: itemWidth,
                    child: _SourceCard(
                      source: s,
                      testing: _testingIds.contains(s.id),
                      onTest: () => _testConnection(s.id),
                      onDelete: () => _delete(s.id),
                    ),
                  ))
              .toList(),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source card
// ─────────────────────────────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final SourceSystemModel source;
  final bool testing;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _SourceCard({
    required this.source,
    required this.testing,
    required this.onTest,
    required this.onDelete,
  });

  String get _statusLabel {
    if (!source.isActive) { return 'Inactive'; }
    if (source.isConnected) { return 'Connected'; }
    if (source.lastSyncStatus.isNotEmpty &&
        source.lastSyncStatus != 'success') { return 'Error'; }
    return 'Config needed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: source.isConnected
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Center(
                  child: Text(source.icon,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.name,
                        style: AppTextStyles.titleSmall,
                        overflow: TextOverflow.ellipsis),
                    Text(source.connectorType,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.secondaryText)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.error),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Status + trust weight
          Row(
            children: [
              AdminStatusChip(status: _statusLabel),
              const Spacer(),
              _TrustBadge(weight: source.trustWeight),
            ],
          ),
          const SizedBox(height: 12),

          // Sync mode + last sync
          if (source.lastSyncAt != null)
            Text(
              'Last sync: ${_formatAgo(source.lastSyncAt!)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText),
            ),
          const SizedBox(height: 12),

          // Entity types chips
          if (source.entityTypes.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: source.entityTypes
                  .map((e) => _EntityTypeTag(label: e))
                  .toList(),
            ),
          const SizedBox(height: 16),

          // Test connection button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: testing ? null : onTest,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: source.isConnected
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.primary.withValues(alpha: 0.5),
                ),
                foregroundColor:
                    source.isConnected ? AppColors.success : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  : const Text('Test Connection'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _TrustBadge extends StatelessWidget {
  final double weight;
  const _TrustBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    final pct = (weight * 100).round();
    final color = weight >= 0.7
        ? AppColors.success
        : weight >= 0.4
            ? AppColors.warning
            : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Trust ',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.mutedText)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text('$pct%',
              style: AppTextStyles.badgeLabel.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _EntityTypeTag extends StatelessWidget {
  final String label;
  const _EntityTypeTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.elevatedCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(label,
          style: AppTextStyles.badgeLabel.copyWith(
              color: AppColors.secondaryText, fontSize: 10)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add source dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddSourceDialog extends StatefulWidget {
  final String tenantId;
  final VoidCallback onCreated;
  const _AddSourceDialog(
      {required this.tenantId, required this.onCreated});

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _repo = GetIt.instance<SourceSystemsRepository>();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _connectorType = 'rest_api';
  String _syncMode = 'manual';
  double _trustWeight = 0.7;
  bool _submitting = false;

  /// Per-connector credential controllers, rebuilt when connector type changes.
  Map<String, TextEditingController> _configControllers = {};

  @override
  void initState() {
    super.initState();
    _rebuildConfigControllers('rest_api');
  }

  void _rebuildConfigControllers(String type) {
    for (final c in _configControllers.values) { c.dispose(); }
    final fields = _ConfigField.forConnector(type);
    _configControllers = { for (final f in fields) f.key: TextEditingController() };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _configControllers.values) { c.dispose(); }
    super.dispose();
  }

  Map<String, dynamic> _buildConnectionConfig() {
    final config = <String, dynamic>{};
    for (final entry in _configControllers.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) config[entry.key] = v;
    }
    return config;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final result = await _repo.createSourceSystem(
      tenantId: widget.tenantId,
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      connectorType: _connectorType,
      description: _descCtrl.text.trim(),
      icon: _connectorIcon(_connectorType),
      trustWeight: _trustWeight,
      priority: 1,
      entityTypes: const [],
      syncMode: _syncMode,
      connectionConfig: _buildConnectionConfig(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success():
        widget.onCreated();
        Navigator.of(context).pop();
      case Failure(:final exception):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.cardSurface,
          content: Text(exception.message,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.error)),
        ));
    }
  }

  String _connectorIcon(String type) {
    return switch (type) {
      'salesforce' => '☁️',
      'sap'        => '🏭',
      'oracle'     => '🔶',
      'hubspot'    => '🧡',
      'jdbc'       => '🗄️',
      's3'         => '🪣',
      'kafka'      => '📨',
      'csv'        => '📄',
      'database'   => '🐘',
      _            => '🔌',
    };
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
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Add Source System',
                      style: AppTextStyles.titleMedium),
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
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AdminFormField(
                            label: 'NAME',
                            controller: _nameCtrl,
                            hint: 'Salesforce CRM',
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: AdminFormField(
                            label: 'CODE',
                            controller: _codeCtrl,
                            hint: 'salesforce_crm',
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (!RegExp(r'^[a-z_][a-z0-9_]*$')
                                  .hasMatch(v)) {
                                return 'snake_case only';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AdminDropdownField<String>(
                      label: 'CONNECTOR TYPE',
                      value: _connectorType,
                      items: const [
                        'rest_api', 'salesforce', 'sap', 'oracle',
                        'hubspot', 'jdbc', 's3', 'kafka',
                        'csv', 'database', 'manual', 'custom',
                      ],
                      onChanged: (v) => setState(() {
                        _connectorType = v!;
                        _rebuildConfigControllers(v);
                      }),
                    ),
                    const SizedBox(height: 14),
                    AdminFormField(
                      label: 'DESCRIPTION',
                      controller: _descCtrl,
                      hint: 'Primary CRM source',
                    ),
                    const SizedBox(height: 14),
                    AdminDropdownField<String>(
                      label: 'SYNC MODE',
                      value: _syncMode,
                      items: const ['manual', 'scheduled', 'realtime'],
                      onChanged: (v) => setState(() => _syncMode = v!),
                    ),
                    // ── Connector-specific credential fields ───────────────
                    if (_ConfigField.forConnector(_connectorType).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.divider)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('CONNECTION CREDENTIALS',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.mutedText, letterSpacing: 0.8,
                            )),
                        ),
                        const Expanded(child: Divider(color: AppColors.divider)),
                      ]),
                      const SizedBox(height: 12),
                      ..._ConfigField.forConnector(_connectorType).map((f) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AdminFormField(
                            label: f.label,
                            controller: _configControllers[f.key]!,
                            hint: f.hint,
                            obscureText: f.secret,
                            maxLines: f.multiline ? 4 : 1,
                            validator: f.required
                                ? (v) => (v == null || v.isEmpty) ? 'Required' : null
                                : null,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AdminSectionHeader(label: 'TRUST WEIGHT'),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.elevatedCard,
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: AppColors.divider),
                              ),
                              child: Text(
                                '${(_trustWeight * 100).round()}%',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor:
                                AppColors.primary.withValues(alpha: 0.2),
                            thumbColor: AppColors.primary,
                            overlayColor:
                                AppColors.primary.withValues(alpha: 0.1),
                          ),
                          child: Slider(
                            value: _trustWeight,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            onChanged: (v) =>
                                setState(() => _trustWeight = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                ),
              ),
              const SizedBox(height: 20),
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
                    label: 'Add Source',
                    loading: _submitting,
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

// ─────────────────────────────────────────────────────────────────────────────
// Connection config field definition + per-connector field lists
// ─────────────────────────────────────────────────────────────────────────────

class _ConfigField {
  final String key;
  final String label;
  final String hint;
  final bool secret;
  final bool required;
  final bool multiline;

  const _ConfigField({
    required this.key,
    required this.label,
    required this.hint,
    this.secret = false,
    this.required = false,
    this.multiline = false,
  });

  static const Map<String, List<_ConfigField>> _byConnector = {
    'rest_api': [
      _ConfigField(key: 'base_url',      label: 'BASE URL',          hint: 'https://api.example.com', required: true),
      _ConfigField(key: 'api_key',        label: 'API KEY',           hint: 'sk-...', secret: true),
      _ConfigField(key: 'bearer_token',   label: 'BEARER TOKEN',      hint: 'token value', secret: true),
      _ConfigField(key: 'timeout_secs',   label: 'TIMEOUT (seconds)', hint: '30'),
    ],
    'salesforce': [
      _ConfigField(key: 'instance_url',     label: 'INSTANCE URL',     hint: 'https://myorg.my.salesforce.com', required: true),
      _ConfigField(key: 'consumer_key',     label: 'CONSUMER KEY',     hint: 'Connected app key', required: true, secret: true),
      _ConfigField(key: 'consumer_secret',  label: 'CONSUMER SECRET',  hint: '...', required: true, secret: true),
      _ConfigField(key: 'username',         label: 'USERNAME',         hint: 'admin@company.com'),
      _ConfigField(key: 'password',         label: 'PASSWORD',         hint: '...', secret: true),
    ],
    'sap': [
      _ConfigField(key: 'host',          label: 'HOST',          hint: 'sap.company.com', required: true),
      _ConfigField(key: 'client',        label: 'CLIENT ID',     hint: '100', required: true),
      _ConfigField(key: 'system_number', label: 'SYSTEM NUMBER', hint: '00'),
      _ConfigField(key: 'username',      label: 'USERNAME',      hint: 'RFCUSER', required: true),
      _ConfigField(key: 'password',      label: 'PASSWORD',      hint: '...', required: true, secret: true),
    ],
    'oracle': [
      _ConfigField(key: 'host',         label: 'HOST',         hint: 'oracle.company.com', required: true),
      _ConfigField(key: 'port',         label: 'PORT',         hint: '1521'),
      _ConfigField(key: 'service_name', label: 'SERVICE NAME', hint: 'ORCL', required: true),
      _ConfigField(key: 'username',     label: 'USERNAME',     hint: 'scott', required: true),
      _ConfigField(key: 'password',     label: 'PASSWORD',     hint: '...', required: true, secret: true),
    ],
    'hubspot': [
      _ConfigField(key: 'api_key',   label: 'PRIVATE APP TOKEN', hint: 'pat-na1-...', required: true, secret: true),
      _ConfigField(key: 'portal_id', label: 'PORTAL ID',         hint: '12345678'),
    ],
    'jdbc': [
      _ConfigField(key: 'url',          label: 'JDBC URL',      hint: 'jdbc:postgresql://host:5432/db', required: true),
      _ConfigField(key: 'driver_class', label: 'DRIVER CLASS',  hint: 'org.postgresql.Driver'),
      _ConfigField(key: 'username',     label: 'USERNAME',      hint: 'dbuser', required: true),
      _ConfigField(key: 'password',     label: 'PASSWORD',      hint: '...', required: true, secret: true),
    ],
    's3': [
      _ConfigField(key: 'bucket',            label: 'BUCKET NAME',       hint: 'my-data-bucket', required: true),
      _ConfigField(key: 'region',            label: 'AWS REGION',        hint: 'us-east-1', required: true),
      _ConfigField(key: 'access_key_id',     label: 'ACCESS KEY ID',     hint: 'AKIA...', required: true, secret: true),
      _ConfigField(key: 'secret_access_key', label: 'SECRET ACCESS KEY', hint: '...', required: true, secret: true),
      _ConfigField(key: 'prefix',            label: 'KEY PREFIX',        hint: 'data/exports/'),
    ],
    'kafka': [
      _ConfigField(key: 'bootstrap_servers', label: 'BOOTSTRAP SERVERS', hint: 'broker1:9092,broker2:9092', required: true),
      _ConfigField(key: 'topic',             label: 'TOPIC',             hint: 'entity.updates', required: true),
      _ConfigField(key: 'group_id',          label: 'CONSUMER GROUP',    hint: 'nexus-mdm'),
      _ConfigField(key: 'sasl_username',     label: 'SASL USERNAME',     hint: 'kafka-user', secret: true),
      _ConfigField(key: 'sasl_password',     label: 'SASL PASSWORD',     hint: '...', secret: true),
    ],
    'csv': [
      _ConfigField(key: 'file_url',   label: 'FILE URL / PATH', hint: 'https://... or /mnt/data/', required: true),
      _ConfigField(key: 'delimiter',  label: 'DELIMITER',       hint: ','),
      _ConfigField(key: 'encoding',   label: 'ENCODING',        hint: 'UTF-8'),
      _ConfigField(key: 'has_header', label: 'HAS HEADER ROW',  hint: 'true'),
    ],
    'database': [
      _ConfigField(key: 'host',     label: 'HOST',          hint: 'db.company.com', required: true),
      _ConfigField(key: 'port',     label: 'PORT',          hint: '5432'),
      _ConfigField(key: 'database', label: 'DATABASE NAME', hint: 'production', required: true),
      _ConfigField(key: 'username', label: 'USERNAME',      hint: 'readonly_user', required: true),
      _ConfigField(key: 'password', label: 'PASSWORD',      hint: '...', required: true, secret: true),
      _ConfigField(key: 'db_type',  label: 'DB TYPE',       hint: 'postgresql'),
    ],
    'custom': [
      _ConfigField(key: 'config_json', label: 'CONFIGURATION JSON',
          hint: '{"key": "value"}', multiline: true),
    ],
    'manual': [],
  };

  static List<_ConfigField> forConnector(String type) =>
      _byConnector[type] ?? [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm delete dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 40),
            const SizedBox(height: 12),
            Text('Remove Source System?',
                style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This will remove the connector configuration. '
              'Existing synced data will not be deleted.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel',
                      style: AppTextStyles.buttonMedium
                          .copyWith(color: AppColors.secondaryText)),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.4)),
                    ),
                    child: Text('Remove',
                        style: AppTextStyles.buttonMedium
                            .copyWith(color: AppColors.error)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
