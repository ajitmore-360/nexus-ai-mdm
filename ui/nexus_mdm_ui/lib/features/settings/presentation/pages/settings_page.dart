import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/validation/validators.dart';

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

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
    required this.url,
    required this.lastSync,
    required this.trustScore,
    required this.isActive,
  });
}

class _AppUser {
  final String name;
  final String email;
  final String role;
  final String lastLogin;

  const _AppUser({
    required this.name,
    required this.email,
    required this.role,
    required this.lastLogin,
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

// ─────────────────────────────────────────────
// Demo data
// ─────────────────────────────────────────────

final _demoSources = [
  _SourceSystem(
    id: 's1',
    name: 'Salesforce CRM',
    type: 'CRM',
    url: 'https://mycompany.salesforce.com',
    lastSync: '4 min ago',
    trustScore: 0.94,
    isActive: true,
  ),
  _SourceSystem(
    id: 's2',
    name: 'SAP ERP',
    type: 'ERP',
    url: 'https://sap.internal.corp/api/v2',
    lastSync: '1 hr ago',
    trustScore: 0.88,
    isActive: true,
  ),
  _SourceSystem(
    id: 's3',
    name: 'Oracle CRM',
    type: 'CRM',
    url: 'https://oracle-crm.corp.internal',
    lastSync: '3 days ago',
    trustScore: 0.71,
    isActive: false,
  ),
];

const _demoUsers = [
  _AppUser(
      name: 'Alex Rivera',
      email: 'alex@acme.com',
      role: 'admin',
      lastLogin: '2 min ago'),
  _AppUser(
      name: 'Sarah Chen',
      email: 'sarah@acme.com',
      role: 'steward',
      lastLogin: '1 hr ago'),
  _AppUser(
      name: 'Marcus Webb',
      email: 'marcus@acme.com',
      role: 'steward',
      lastLogin: '3 hrs ago'),
  _AppUser(
      name: 'Priya Sharma',
      email: 'priya@acme.com',
      role: 'analyst',
      lastLogin: 'Yesterday'),
  _AppUser(
      name: 'James Taylor',
      email: 'james@acme.com',
      role: 'viewer',
      lastLogin: '2 days ago'),
];

final _demoApiKeys = [
  _ApiKey(
      id: 'prod001',
      name: 'Production API',
      maskedKey: 'nxs_prod001_****'),
  _ApiKey(
      id: 'ci002',
      name: 'CI/CD Pipeline',
      maskedKey: 'nxs_ci002_****'),
  _ApiKey(
      id: 'int003',
      name: 'Integration Tests',
      maskedKey: 'nxs_int003_****'),
];

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// Main Page
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// Tab 1 – AI Configuration
// ─────────────────────────────────────────────

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
  bool _ragCopilot = true;
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
    setState(() => _testingConnection = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _testingConnection = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 16),
            const SizedBox(width: 8),
            Text(
                'Connected to Ollama at ${_endpointCtrl.text} · Model: $_llmModel'),
          ],
        ),
        backgroundColor: AppColors.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                        'Llama resolves ambiguous matches (0.75–0.95 score)',
                    value: _aiMatchAssist,
                    icon: Icons.auto_awesome_rounded,
                    onChanged: (v) =>
                        setState(() => _aiMatchAssist = v),
                  ),
                  _AiFeatureSwitch(
                    title: 'RAG Copilot',
                    subtitle:
                        'Knowledge-grounded natural language Q&A',
                    value: _ragCopilot,
                    icon: Icons.chat_rounded,
                    onChanged: (v) => setState(() => _ragCopilot = v),
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

// ─────────────────────────────────────────────
// Tab 2 – Source Systems
// ─────────────────────────────────────────────

class _SourceSystemsTab extends StatefulWidget {
  const _SourceSystemsTab();

  @override
  State<_SourceSystemsTab> createState() => _SourceSystemsTabState();
}

class _SourceSystemsTabState extends State<_SourceSystemsTab> {
  final List<_SourceSystem> _sources = List.from(_demoSources);

  void _toggleSource(_SourceSystem s) {
    setState(() => s.isActive = !s.isActive);
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
                      '${source.type} · Last sync: ${source.lastSync}',
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

// ─────────────────────────────────────────────
// Tab 3 – Administration
// ─────────────────────────────────────────────

class _AdministrationTab extends StatefulWidget {
  const _AdministrationTab();

  @override
  State<_AdministrationTab> createState() => _AdministrationTabState();
}

class _AdministrationTabState extends State<_AdministrationTab> {
  final List<_ApiKey> _apiKeys = List.from(_demoApiKeys);
  int? _hoveredUserRow;

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
            _buildTenantInfo()
                .animate()
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
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _InfoRow(label: 'Tenant ID',
                        value: '00000000-0000-0000-0000-000000000001'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Plan',
                            style: AppTextStyles.bodySmall
                                .copyWith(
                                    color: AppColors.secondaryText)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: AppColors.purpleGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Enterprise',
                              style: AppTextStyles.labelSmall
                                  .copyWith(color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const _InfoRow(label: 'Status', value: 'Active'),
                    const SizedBox(height: 10),
                    const _InfoRow(
                        label: 'Created', value: 'Jan 15, 2025'),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UsageBar(
                        label: 'Entities',
                        current: 4200000,
                        max: 10000000,
                        unit: 'M',
                        color: AppColors.primary),
                    SizedBox(height: 14),
                    _UsageBar(
                        label: 'Users',
                        current: 8,
                        max: 100,
                        unit: '',
                        color: AppColors.info),
                    SizedBox(height: 14),
                    _UsageBar(
                        label: 'API calls (this month)',
                        current: 892000,
                        max: 5000000,
                        unit: 'K',
                        color: AppColors.aiPurple),
                  ],
                ),
              ),
            ],
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
          ..._demoUsers.asMap().entries.map((entry) {
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
                        ? AppColors.elevatedCard.withValues(alpha:0.5)
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
                                      .withValues(alpha:0.15),
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
                                    .withValues(alpha:0.12),
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
                            child: Text(u.lastLogin,
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
                                  tooltip: 'Edit',
                                  onPressed: () {},
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 28, minHeight: 28),
                                ),
                                if (u.role != 'admin')
                                  IconButton(
                                    icon: const Icon(
                                        Icons.person_remove_outlined,
                                        size: 15),
                                    color: AppColors.error
                                        .withValues(alpha:0.7),
                                    tooltip: 'Remove',
                                    onPressed: () {},
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
                if (i < _demoUsers.length - 1)
                  const Divider(
                      color: AppColors.divider, height: 1),
              ],
            );
          }),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {},
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
}

// ─────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────

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
