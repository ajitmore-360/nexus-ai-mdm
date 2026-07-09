import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_it/get_it.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/validation/validators.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Models
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SourceSystem {
  final String id;
  final String name;
  final String type;
  final String url;
  final String lastSync;
  final double trustScore;
  bool isActive;

  _SourceSystem({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.lastSync = 'â€”',
    required this.trustScore,
    required this.isActive,
  });
}

class _AppUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String lastLogin;

  const _AppUser({
    this.id = '',
    required this.name,
    required this.email,
    required this.role,
    this.lastLogin = '',
  });
}

class _ApiKey {
  final String id;
  final String name;
  final String maskedKey;
  bool revealed = false;

  _ApiKey({
    required this.id,
    required this.name,
    required this.maskedKey,
  });

  String get fullKey => 'nxs_${id}_lk9Xm2vQpR7nTwYsJ4dKfB3hCeZoAuN';
}


// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Helpers
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Color _roleColor(String role) {
  switch (role) {
    case 'admin':
      return AppColors.error;
    case 'steward':
      return AppColors.primary;
    case 'analyst':
      return AppColors.info;
    default:
      return AppColors.mutedText;
  }
}

InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle:
          AppTextStyles.labelMedium.copyWith(color: AppColors.secondaryText),
      hintStyle: AppTextStyles.inputHint,
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

Widget _sectionCard({required String title, String? subtitle, required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.titleSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText)),
        ],
        const Divider(color: AppColors.divider, height: 24),
        child,
      ],
    ),
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Main Page
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _AiConfigTab(),
              _SourceSystemsTab(),
              _AdministrationTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings & Administration',
                      style: AppTextStyles.headlineSmall)
                  .animate()
                  .fadeIn(duration: 400.ms),
              const SizedBox(height: 4),
              Text(
                'AI configuration, source systems, and tenant management',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.secondaryText),
              ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.aiPurple.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.aiPurple.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: AppColors.aiPurple, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Enterprise Plan',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.aiPurple),
                ),
              ],
            ),
          ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'AI Configuration'),
          Tab(text: 'Source Systems'),
          Tab(text: 'Administration'),
        ],
        labelStyle: AppTextStyles.titleSmall,
        unselectedLabelStyle: AppTextStyles.bodyMedium,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        isScrollable: false,
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tab 1 â€“ AI Configuration
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AiConfigTab extends StatefulWidget {
  const _AiConfigTab();

  @override
  State<_AiConfigTab> createState() => _AiConfigTabState();
}

class _AiConfigTabState extends State<_AiConfigTab> {
  String _llmModel = 'Llama 3.2 8B';
  String _embedModel = 'nomic-embed-text';
  final _endpointCtrl =
      TextEditingController(text: 'http://localhost:11434');
  bool _testingConnection = false;

  // AI Feature switches
  bool _aiMatchAssist = true;
  bool _ragPrism = true;
  bool _autoSurvivorship = true;
  bool _anomalyDetection = true;
  bool _adaptiveWeights = false;

  // Thresholds
  double _autoMergeThreshold = 0.95;
  double _reviewThreshold = 0.75;
  double _ambiguityDelta = 0.03;

  final _llmModels = [
    'Llama 3.2 8B',
    'Llama 3.2 3B',
    'Llama 3.1 70B',
  ];
  final _embedModels = [
    'nomic-embed-text',
    'mxbai-embed-large',
  ];

  @override
  void dispose() {
    _endpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final baseUrl = _endpointCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
    if (baseUrl.isEmpty) return;
    setState(() => _testingConnection = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final resp = await dio.get('$baseUrl/api/tags');
      if (!mounted) return;
      final models = (resp.data?['models'] as List?)
              ?.map((m) => m['name'] as String? ?? '')
              .where((n) => n.isNotEmpty)
              .toList() ??
          [];
      setState(() => _testingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(models.isNotEmpty
                    ? 'Connected Â· ${models.length} model${models.length == 1 ? '' : 's'}: ${models.take(3).join(', ')}'
                    : 'Connected to Ollama at $baseUrl'),
              ),
            ],
          ),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _testingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Could not reach Ollama at $baseUrl')),
            ],
          ),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _saveThresholds() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Matching thresholds saved successfully'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Language Model card
            _sectionCard(
              title: 'Language Model',
              subtitle: 'Configure the local LLM powering AI features',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LLM Model',
                                style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.secondaryText)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _llmModel,
                              dropdownColor: AppColors.elevatedCard,
                              style: AppTextStyles.inputText,
                              decoration: _inputDeco(''),
                              items: _llmModels
                                  .map((m) => DropdownMenuItem(
                                      value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _llmModel = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Embedding Model',
                                style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.secondaryText)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _embedModel,
                              dropdownColor: AppColors.elevatedCard,
                              style: AppTextStyles.inputText,
                              decoration: _inputDeco(''),
                              items: _embedModels
                                  .map((m) => DropdownMenuItem(
                                      value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _embedModel = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _endpointCtrl,
                          style: AppTextStyles.inputText,
                          decoration: _inputDeco('Ollama Endpoint',
                              hint: 'http://localhost:11434'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        onPressed:
                            _testingConnection ? null : _testConnection,
                        icon: _testingConnection
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.navyBackground,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering_rounded,
                                size: 16),
                        label: Text(
                          _testingConnection
                              ? 'Testing...'
                              : 'Test Connection',
                          style: AppTextStyles.buttonMedium,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.navyBackground,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),

            const SizedBox(height: 20),

            // AI Features card
            _sectionCard(
              title: 'AI Features',
              subtitle:
                  'Toggle individual AI capabilities for this tenant',
              child: Column(
                children: [
                  _AiFeatureSwitch(
                    title: 'AI Match Assist',
                    subtitle:
                        'Llama resolves ambiguous matches (0.75â€“0.95 score)',
                    value: _aiMatchAssist,
                    icon: Icons.auto_awesome_rounded,
                    onChanged: (v) =>
                        setState(() => _aiMatchAssist = v),
                  ),
                  _AiFeatureSwitch(
                    title: 'RAG Prism',
                    subtitle:
                        'Knowledge-grounded natural language Q&A',
                    value: _ragPrism,
                    icon: Icons.chat_rounded,
                    onChanged: (v) => setState(() => _ragPrism = v),
                  ),
                  _AiFeatureSwitch(
                    title: 'Auto Survivorship',
                    subtitle:
                        'AI suggests survivorship rule winners',
                    value: _autoSurvivorship,
                    icon: Icons.mediation_rounded,
                    onChanged: (v) =>
                        setState(() => _autoSurvivorship = v),
                  ),
                  _AiFeatureSwitch(
                    title: 'Anomaly Detection',
                    subtitle:
                        'Detects data quality issues proactively',
                    value: _anomalyDetection,
                    icon: Icons.troubleshoot_rounded,
                    onChanged: (v) =>
                        setState(() => _anomalyDetection = v),
                  ),
                  _AiFeatureSwitch(
                    title: 'Adaptive Weights',
                    subtitle:
                        'Learn scoring weights from steward decisions',
                    value: _adaptiveWeights,
                    icon: Icons.tune_rounded,
                    onChanged: (v) =>
                        setState(() => _adaptiveWeights = v),
                    isLast: true,
                  ),
                ],
              ),
            )
                .animate(delay: 80.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),

            const SizedBox(height: 20),

            // Matching Thresholds card
            _sectionCard(
              title: 'Matching Thresholds',
              subtitle:
                  'Tune the confidence bands that control merge behavior',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThresholdSlider(
                    label: 'Auto-merge threshold',
                    value: _autoMergeThreshold,
                    min: 0.80,
                    max: 1.0,
                    divisions: 20,
                    color: AppColors.primary,
                    description:
                        'Pairs above this score are merged automatically',
                    onChanged: (v) =>
                        setState(() => _autoMergeThreshold = v),
                  ),
                  const SizedBox(height: 16),
                  _ThresholdSlider(
                    label: 'Review threshold',
                    value: _reviewThreshold,
                    min: 0.50,
                    max: 0.95,
                    divisions: 45,
                    color: AppColors.warning,
                    description:
                        'Pairs above this score enter the review queue',
                    onChanged: (v) =>
                        setState(() => _reviewThreshold = v),
                  ),
                  const SizedBox(height: 16),
                  _ThresholdSlider(
                    label: 'Ambiguity delta',
                    value: _ambiguityDelta,
                    min: 0.01,
                    max: 0.10,
                    divisions: 9,
                    color: AppColors.aiPurple,
                    description:
                        'Score gap triggering AI assist disambiguation',
                    onChanged: (v) =>
                        setState(() => _ambiguityDelta = v),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saveThresholds,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Thresholds'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.navyBackground,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            )
                .animate(delay: 160.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),
          ],
        ),
      ),
    );
  }
}

class _AiFeatureSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _AiFeatureSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: value
                      ? AppColors.primary.withValues(alpha:0.12)
                      : AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon,
                    color:
                        value ? AppColors.primary : AppColors.mutedText,
                    size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleSmall),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.secondaryText)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(color: AppColors.divider, height: 16),
      ],
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final String description;
  final ValueChanged<double> onChanged;

  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.description,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppTextStyles.titleSmall
                    .copyWith(fontSize: 14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha:0.3)),
              ),
              child: Text(
                value.toStringAsFixed(2),
                style: AppTextStyles.labelMedium.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(description,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText)),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: AppColors.divider,
            overlayColor: color.withValues(alpha:0.12),
            trackHeight: 4,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        Row(
          children: [
            Text(min.toStringAsFixed(2),
                style: AppTextStyles.labelSmall),
            const Spacer(),
            Text(max.toStringAsFixed(2),
                style: AppTextStyles.labelSmall),
          ],
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tab 2 â€“ Source Systems
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SourceSystemsTab extends StatefulWidget {
  const _SourceSystemsTab();

  @override
  State<_SourceSystemsTab> createState() => _SourceSystemsTabState();
}

class _SourceSystemsTabState extends State<_SourceSystemsTab> {
  List<_SourceSystem> _sources = [];
  bool _sourcesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final tenantId = await AuthManager.getTenantId();
    if (!mounted) return;
    if (tenantId == null) {
      setState(() => _sourcesLoading = false);
      return;
    }
    try {
      final api = GetIt.instance<ApiClient>();
      final resp = await api.get<Map<String, dynamic>>(
        AppConstants.sourceSystemsPath,
        queryParameters: {'tenant_id': tenantId},
      );
      final data = resp.data;
      if (!mounted) return;
      final list = (data?['data'] as List<dynamic>? ?? []).map((s) {
        final m = s as Map<String, dynamic>;
        return _SourceSystem(
          id: (m['id'] as String?) ?? '',
          name: (m['name'] as String?) ?? 'Unknown',
          type: (m['connector_type'] as String?) ?? 'custom',
          trustScore: (m['trust_weight'] as num?)?.toDouble() ?? 0.5,
          isActive: (m['is_active'] as bool?) ?? false,
        );
      }).toList();
      setState(() { _sources = list; _sourcesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _sourcesLoading = false);
    }
  }

  Future<void> _toggleSource(_SourceSystem s) async {
    setState(() => s.isActive = !s.isActive);
    try {
      final api = GetIt.instance<ApiClient>();
      await api.put<Map<String, dynamic>>(
        '${AppConstants.sourceSystemsPath}/${s.id}',
        data: {'is_active': s.isActive},
      );
    } catch (_) {
      if (mounted) setState(() => s.isActive = !s.isActive);
    }
  }

  void _showAddSourceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddSourceDialog(
        onAdd: (source) => setState(() => _sources.add(source)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Connected Sources',
                    style: AppTextStyles.titleMedium)
                    .animate()
                    .fadeIn(duration: 400.ms),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddSourceDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Source'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.navyBackground,
                  ),
                ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
              ],
            ),
            const SizedBox(height: 16),
            if (_sourcesLoading)
              const Center(child: CircularProgressIndicator())
            else if (_sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No source systems connected yet.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText),
                  ),
                ),
              )
            else
              ..._sources.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _SourceCard(
                    source: s,
                    index: i,
                    onToggle: () => _toggleSource(s),
                    onEdit: () {},
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final _SourceSystem source;
  final int index;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _SourceCard({
    required this.source,
    required this.index,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final trustColor = source.trustScore >= 0.9
        ? AppColors.primary
        : source.trustScore >= 0.8
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: source.isActive
              ? AppColors.divider
              : AppColors.divider.withValues(alpha:0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  source.type == 'CRM'
                      ? Icons.people_alt_rounded
                      : Icons.warehouse_rounded,
                  color: source.isActive
                      ? AppColors.primary
                      : AppColors.mutedText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(source.name,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: source.isActive
                                  ? AppColors.primaryText
                                  : AppColors.mutedText,
                            )),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: source.isActive
                                ? AppColors.primary
                                : AppColors.mutedText,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          source.isActive ? 'Active' : 'Paused',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: source.isActive
                                ? AppColors.primary
                                : AppColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${source.type} Â· Last sync: ${source.lastSync}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              // Action buttons
              if (!source.isActive)
                OutlinedButton.icon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.play_arrow_rounded, size: 14),
                  label: const Text('Resume'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(
                        color: AppColors.primary, width: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  color: AppColors.secondaryText,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline, size: 17),
                  color: AppColors.warning,
                  tooltip: 'Pause',
                  onPressed: onToggle,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Trust Score',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: source.trustScore,
                    backgroundColor: AppColors.divider,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(trustColor),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                source.trustScore.toStringAsFixed(2),
                style: AppTextStyles.labelMedium
                    .copyWith(color: trustColor),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 80 * index))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0);
  }
}

class _AddSourceDialog extends StatefulWidget {
  final void Function(_SourceSystem) onAdd;

  const _AddSourceDialog({required this.onAdd});

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'CRM';
  double _trustScore = 0.80;

  final _types = ['CRM', 'ERP', 'Database', 'API', 'File', 'Streaming'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  Text('Add Source System',
                      style: AppTextStyles.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.secondaryText,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      style: AppTextStyles.inputText,
                      decoration: _inputDeco('Source Name',
                          hint: 'e.g. Salesforce CRM'),
                      validator: Validators.minLength(2, label: 'Source name'),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      dropdownColor: AppColors.elevatedCard,
                      style: AppTextStyles.inputText,
                      decoration: _inputDeco('Source Type'),
                      items: _types
                          .map((t) =>
                              DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _urlCtrl,
                      style: AppTextStyles.inputText,
                      decoration: _inputDeco('Endpoint URL',
                          hint: 'https://...'),
                      validator: Validators.url,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Trust Score',
                            style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.secondaryText)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _trustScore.toStringAsFixed(2),
                            style: AppTextStyles.labelMedium
                                .copyWith(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.primary,
                        thumbColor: AppColors.primary,
                        inactiveTrackColor: AppColors.divider,
                        overlayColor:
                            AppColors.primary.withValues(alpha:0.12),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _trustScore,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: (v) =>
                            setState(() => _trustScore = v),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descCtrl,
                      style: AppTextStyles.inputText,
                      maxLines: 2,
                      decoration: _inputDeco('Description (optional)',
                          hint: 'Brief description of this data source'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: const BorderSide(color: AppColors.divider),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      widget.onAdd(_SourceSystem(
                        id: DateTime.now()
                            .millisecondsSinceEpoch
                            .toString(),
                        name: _nameCtrl.text,
                        type: _type,
                        url: _urlCtrl.text,
                        lastSync: 'Just now',
                        trustScore: _trustScore,
                        isActive: true,
                      ));
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Source'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.navyBackground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tab 3 â€“ Administration
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AdministrationTab extends StatefulWidget {
  const _AdministrationTab();

  @override
  State<_AdministrationTab> createState() => _AdministrationTabState();
}

class _AdministrationTabState extends State<_AdministrationTab> {
  // â”€â”€ Users state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<_AppUser> _users = [];
  bool _usersLoading = true;

  // â”€â”€ Tenant info state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _tenantId   = 'â€”';
  String _tenantName = 'â€”';
  String _planName   = 'Enterprise';
  int    _entityCurrent = 0;
  int    _entityLimit   = 10000000;
  int    _userCurrent   = 0;
  int    _userLimit     = 100;
  bool   _tenantLoading = true;

  // â”€â”€ API keys state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final List<_ApiKey> _apiKeys = [];
  int? _hoveredUserRow;

  // â”€â”€ Change-password state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _pwFormKey    = GlobalKey<FormState>();
  final _curPwCtrl    = TextEditingController();
  final _newPwCtrl    = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _pwSaving      = false;
  bool _obscureCur    = true;
  bool _obscureNew    = true;
  bool _obscureConf   = true;
  String? _pwError;
  bool _pwSuccess     = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadTenantInfo();
  }

  Future<void> _loadTenantInfo() async {
    try {
      final tenantId   = await AuthManager.getTenantId();
      final tenantName = await AuthManager.getTenantName();
      if (!mounted) return;
      setState(() {
        _tenantId   = tenantId   ?? 'â€”';
        _tenantName = tenantName ?? 'â€”';
      });

      // Load quota + plan from license endpoint
      final api  = GetIt.instance<ApiClient>();
      final resp = await api.get<Map<String, dynamic>>('/v1/license');
      if (!mounted) return;
      final data = resp.data?['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _planName       = (data['plan_name'] as String?)             ?? 'Enterprise';
        _entityCurrent  = (data['current_entity_count'] as int?)     ?? 0;
        _entityLimit    = (data['max_entities'] as int?)             ?? 10000000;
        _userCurrent    = (data['current_user_count'] as int?)       ?? 0;
        _userLimit      = (data['max_users'] as int?)                ?? 100;
        _tenantLoading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _tenantLoading = false);
    }
  }

  @override
  void dispose() {
    _curPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final api = GetIt.instance<ApiClient>();
      final resp = await api.get<Map<String, dynamic>>('/v1/users');
      if (!mounted) return;
      final rows = (resp.data?['data'] as List<dynamic>? ?? []);
      final users = rows.map((u) {
        final m = u as Map<String, dynamic>;
        return _AppUser(
          id:    (m['user_id'] as String?) ?? '',
          name:  (m['display_name'] as String?) ?? (m['email'] as String?) ?? 'Unknown',
          email: (m['email']        as String?) ?? '',
          role:  (m['role']         as String?) ?? 'viewer',
        );
      }).toList();
      setState(() { _users = users; _usersLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _inviteUser(String email, String role) async {
    try {
      final api = GetIt.instance<ApiClient>();
      await api.post<Map<String, dynamic>>(
        '/v1/users/invite',
        data: {'email': email, 'role': role},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite sent to $email'),
        backgroundColor: AppColors.success,
      ));
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to send invite. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _changeUserRole(_AppUser user, String newRole) async {
    if (user.id.isEmpty) return;
    try {
      final api = GetIt.instance<ApiClient>();
      await api.patch<Map<String, dynamic>>(
        '/v1/users/${user.id}/role',
        data: {'role': newRole},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${user.name} role updated to $newRole'),
        backgroundColor: AppColors.success,
      ));
      _loadUsers();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to update role. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _showInviteDialog() {
    final emailCtrl = TextEditingController();
    String selectedRole = 'steward';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.cardSurface,
          title: const Text('Invite User'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'user@company.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'admin',   child: Text('Admin')),
                  DropdownMenuItem(value: 'steward', child: Text('Steward')),
                  DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
                  DropdownMenuItem(value: 'viewer',  child: Text('Viewer')),
                ],
                onChanged: (v) => setDlgState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _inviteUser(emailCtrl.text.trim(), selectedRole);
              },
              child: const Text('Send Invite'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeRoleDialog(_AppUser user) {
    String selectedRole = user.role;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.cardSurface,
          title: Text('Change role for ${user.name}'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'admin',   child: Text('Admin')),
              DropdownMenuItem(value: 'steward', child: Text('Steward')),
              DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
              DropdownMenuItem(value: 'viewer',  child: Text('Viewer')),
            ],
            onChanged: (v) => setDlgState(() => selectedRole = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _changeUserRole(user, selectedRole);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_pwFormKey.currentState!.validate()) return;
    setState(() { _pwSaving = true; _pwError = null; _pwSuccess = false; });
    try {
      final api = GetIt.instance<ApiClient>();
      await api.post<Map<String, dynamic>>(
        '/auth/change-password',
        data: {
          'current_password': _curPwCtrl.text,
          'new_password':     _newPwCtrl.text,
        },
      );
      if (!mounted) return;
      _curPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmCtrl.clear();
      setState(() { _pwSaving = false; _pwSuccess = true; });
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg  = body is Map
          ? (body['error'] ?? body['message'])?.toString()
          : null;
      setState(() {
        _pwSaving = false;
        _pwError  = msg ?? 'Failed (${e.response?.statusCode})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _pwSaving = false; _pwError = e.toString(); });
    }
  }

  void _generateKey() {
    final newKey = _ApiKey(
      id: 'new${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      name: 'New API Key ${_apiKeys.length + 1}',
      maskedKey:
          'nxs_new${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}_****',
    );
    setState(() => _apiKeys.insert(0, newKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 16),
            SizedBox(width: 8),
            Text('New API key generated'),
          ],
        ),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _revokeKey(_ApiKey key) {
    setState(() => _apiKeys.remove(key));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${key.name}" revoked'),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleReveal(_ApiKey key) {
    setState(() => key.revealed = !key.revealed);
    if (key.revealed) {
      Clipboard.setData(ClipboardData(text: key.fullKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Key copied to clipboard'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildChangePassword()
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),
            const SizedBox(height: 20),
            _buildTenantInfo()
                .animate(delay: 60.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),
            const SizedBox(height: 20),
            _buildUserManagement()
                .animate(delay: 80.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),
            const SizedBox(height: 20),
            _buildApiKeys()
                .animate(delay: 160.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantInfo() {
    return _sectionCard(
      title: 'Tenant Info',
      subtitle: 'Your organisation and plan details',
      child: _tenantLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Tenant ID',   value: _tenantId),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'Name',         value: _tenantName),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('Plan',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.secondaryText)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: AppColors.purpleGradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_planName,
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: Colors.white)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const _InfoRow(label: 'Status', value: 'Active'),
                    ],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _UsageBar(
                          label:   'Entities',
                          current: _entityCurrent,
                          max:     _entityLimit,
                          unit:    'M',
                          color:   AppColors.primary),
                      const SizedBox(height: 14),
                      _UsageBar(
                          label:   'Users',
                          current: _userCurrent,
                          max:     _userLimit,
                          unit:    '',
                          color:   AppColors.info),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUserManagement() {
    return _sectionCard(
      title: 'User Management',
      subtitle: 'Manage team members and their access levels',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('NAME',
                        style: AppTextStyles.tableHeader)),
                Expanded(
                    flex: 3,
                    child: Text('EMAIL',
                        style: AppTextStyles.tableHeader)),
                Expanded(
                    flex: 2,
                    child: Text('ROLE',
                        style: AppTextStyles.tableHeader)),
                Expanded(
                    flex: 2,
                    child: Text('LAST LOGIN',
                        style: AppTextStyles.tableHeader)),
                SizedBox(
                    width: 80,
                    child: Text('ACTIONS',
                        style: AppTextStyles.tableHeader,
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          if (_usersLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No users found.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText)),
              ),
            )
          else
            ..._users.asMap().entries.map((entry) {
              final i = entry.key;
              final u = entry.value;
              final isHovered = _hoveredUserRow == i;
              return Column(
                children: [
                  MouseRegion(
                    onEnter: (_) =>
                        setState(() => _hoveredUserRow = i),
                    onExit: (_) =>
                        setState(() => _hoveredUserRow = null),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      color: isHovered
                          ? AppColors.elevatedCard.withValues(alpha: 0.5)
                          : Colors.transparent,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: _roleColor(u.role)
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      u.name
                                          .split(' ')
                                          .map((w) => w[0])
                                          .take(2)
                                          .join(),
                                      style: AppTextStyles.labelSmall
                                          .copyWith(
                                        color: _roleColor(u.role),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(u.name,
                                        style: AppTextStyles.tableCell,
                                        overflow:
                                            TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(u.email,
                                  style: AppTextStyles.tableCell
                                      .copyWith(
                                          color:
                                              AppColors.secondaryText),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _roleColor(u.role)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(
                                  u.role,
                                  style: AppTextStyles.labelSmall
                                      .copyWith(
                                          color: _roleColor(u.role)),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                  u.lastLogin.isEmpty ? 'â€”' : u.lastLogin,
                                  style: AppTextStyles.tableCell
                                      .copyWith(
                                          color:
                                              AppColors.secondaryText)),
                            ),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 15),
                                    color: AppColors.secondaryText,
                                    tooltip: 'Change role',
                                    onPressed: () =>
                                        _showChangeRoleDialog(u),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (i < _users.length - 1)
                    const Divider(
                        color: AppColors.divider, height: 1),
                ],
              );
            }),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _showInviteDialog,
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Invite User'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeys() {
    return _sectionCard(
      title: 'API Keys',
      subtitle: 'Manage programmatic access credentials',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._apiKeys.map((key) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key_rounded,
                          color: AppColors.secondaryText, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(key.name,
                                style: AppTextStyles.titleSmall
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              key.revealed
                                  ? key.fullKey
                                  : key.maskedKey,
                              style: AppTextStyles.codeStyle
                                  .copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleReveal(key),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondaryText,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                        ),
                        child: Text(
                          key.revealed ? 'Hide' : 'Reveal',
                          style: AppTextStyles.buttonSmall,
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => _revokeKey(key),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                        ),
                        child: Text('Revoke',
                            style: AppTextStyles.buttonSmall),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            onPressed: _generateKey,
            icon: const Icon(Icons.add_card_rounded, size: 16),
            label: const Text('Generate New Key'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.navyBackground,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Change password section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildChangePassword() {
    return _sectionCard(
      title: 'Security',
      subtitle: 'Update your login password',
      child: Form(
        key: _pwFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_pwSuccess) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Text('Password updated successfully.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.success)),
                  ],
                ),
              ),
            ],
            if (_pwError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_pwError!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _pwField(
                    label: 'CURRENT PASSWORD',
                    controller: _curPwCtrl,
                    obscure: _obscureCur,
                    onToggle: () =>
                        setState(() => _obscureCur = !_obscureCur),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _pwField(
                    label: 'NEW PASSWORD',
                    controller: _newPwCtrl,
                    obscure: _obscureNew,
                    onToggle: () =>
                        setState(() => _obscureNew = !_obscureNew),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'At least 8 characters';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _pwField(
                    label: 'CONFIRM NEW PASSWORD',
                    controller: _confirmCtrl,
                    obscure: _obscureConf,
                    onToggle: () =>
                        setState(() => _obscureConf = !_obscureConf),
                    validator: (v) => v != _newPwCtrl.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _pwSaving ? null : _changePassword,
                icon: _pwSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset_rounded, size: 16),
                label: Text(_pwSaving ? 'Savingâ€¦' : 'Update Password',
                    style: AppTextStyles.buttonSmall
                        .copyWith(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pwField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11,
                color: AppColors.mutedText,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: AppTextStyles.inputText,
          decoration: InputDecoration(
            hintText: 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
            hintStyle: AppTextStyles.inputHint,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.error, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 16,
                color: AppColors.mutedText,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Shared small widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.secondaryText)),
        ),
        Expanded(
          child: Text(value,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primaryText)),
        ),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  final String label;
  final int current;
  final int max;
  final String unit;
  final Color color;

  const _UsageBar({
    required this.label,
    required this.current,
    required this.max,
    required this.unit,
    required this.color,
  });

  String _fmt(int n) {
    if (unit == 'M') return '${(n / 1000000).toStringAsFixed(1)}M';
    if (unit == 'K') return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pct = current / max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.secondaryText)),
            ),
            Text(
              '${_fmt(current)} / ${_fmt(max)}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.primaryText),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              pct > 0.85 ? AppColors.error : color,
            ),
            minHeight: 7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${(pct * 100).toStringAsFixed(1)}% used',
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
  }
}
