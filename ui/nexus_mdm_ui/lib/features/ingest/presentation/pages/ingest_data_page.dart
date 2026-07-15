import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/network/api_client.dart' hide ApiException;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/ingest_repository.dart';

class IngestDataPage extends StatefulWidget {
  const IngestDataPage({super.key});

  @override
  State<IngestDataPage> createState() => _IngestDataPageState();
}

class _IngestDataPageState extends State<IngestDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _apiClient = ApiClient();
  late final IngestRepository _ingestRepo;

  String _selectedEntityType = 'Customer';
  String _sourceSystem = 'Manual';
  bool _isLoading = false;
  String? _resultMessage;
  bool _resultIsError = false;
  String? _lastJobId;

  List<IngestJob> _recentJobs = [];
  bool _jobsLoading = false;

  // ── File upload state ─────────────────────────────────────────────────────
  String?     _pickedFileName;
  List<int>?  _pickedFileBytes;
  double?     _uploadSendProgress;  // 0.0–1.0 upload progress
  String?     _activeJobId;         // job being polled
  IngestJob?  _activeJob;           // latest polled job state
  Timer?      _pollTimer;

  final _csvController = TextEditingController(text: _kSampleCsv);
  final _jsonController = TextEditingController(text: _kSampleJson);

  static const _kSampleCsv = 'name,email,phone,city\n'
      'Alice Johnson,alice@example.com,555-0101,New York\n'
      'Bob Smith,bob@example.com,555-0102,Chicago\n'
      'Carol White,carol@example.com,555-0103,San Francisco';

  static const _kSampleJson = '{\n'
      '  "records": [\n'
      '    { "name": "Alice Johnson", "email": "alice@example.com", "city": "New York" },\n'
      '    { "name": "Bob Smith",     "email": "bob@example.com",   "city": "Chicago"  }\n'
      '  ]\n'
      '}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _ingestRepo = IngestRepository(_apiClient);
    _loadRecentJobs();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _csvController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentJobs() async {
    final tenantId = await AuthManager.getTenantId() ?? '';
    if (!mounted) return;
    setState(() => _jobsLoading = true);
    try {
      final jobs = await _ingestRepo.listJobs(tenantId: tenantId);
      if (mounted) setState(() { _recentJobs = jobs; _jobsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _jobsLoading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final tenantId =
          await AuthManager.getTenantId() ?? '';

      if (_tabController.index == 2) {
        _setResult('Use the Upload & Ingest button in the File Upload tab.', isError: true);
        return;
      }

      if (_tabController.index == 0) {
        final csv = _csvController.text.trim();
        if (csv.isEmpty) {
          _setResult('Paste CSV data before importing.', isError: true);
          return;
        }
        final response = await _apiClient.post<Map<String, dynamic>>(
          AppConstants.ingestCsvPath,
          data: {
            'tenant_id':     tenantId,
            'source_system': _sourceSystem,
            'entity_type':   _selectedEntityType,
            'csv_data':      csv,
          },
        );
        _handleResponse(response.data);
      } else {
        final raw = _jsonController.text.trim();
        if (raw.isEmpty) {
          _setResult('Paste JSON data before importing.', isError: true);
          return;
        }
        late Map<String, dynamic> payload;
        try {
          payload = Map<String, dynamic>.from(
              jsonDecode(raw) as Map<dynamic, dynamic>);
        } catch (_) {
          _setResult('Invalid JSON — check the format and try again.', isError: true);
          return;
        }
        payload.putIfAbsent('tenant_id',     () => tenantId);
        payload.putIfAbsent('source_system', () => _sourceSystem);
        payload.putIfAbsent('entity_type',   () => _selectedEntityType);

        final response = await _apiClient.post<Map<String, dynamic>>(
          AppConstants.ingestEntitiesPath,
          data: payload,
        );
        _handleResponse(response.data);
      }
    } catch (e) {
      _setResult('Error: $e', isError: true);
    }
  }

  void _handleResponse(Map<String, dynamic>? data) {
    final ok     = data?['success'] as bool? ?? false;
    final result = data?['result']  as Map<String, dynamic>? ?? {};
    final jobId  = data?['job_id']  as String?;
    if (ok) {
      final processed = result['processed'] as int? ?? 0;
      final failed    = result['failed']    as int? ?? 0;
      _lastJobId = jobId;
      _setResult(
        'Imported $processed record${processed == 1 ? '' : 's'}'
        '${failed > 0 ? ' ($failed failed)' : ''}.'
        '${jobId != null ? '  Job: ${jobId.substring(0, 8)}…' : ''}',
        isError: false,
      );
      _loadRecentJobs();
    } else {
      _setResult(data?['error']?.toString() ?? 'Import failed.', isError: true);
    }
  }

  void _setResult(String msg, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _resultMessage = msg;
      _resultIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildOptions(),
            const SizedBox(height: 20),
            _buildTabs(),
            const SizedBox(height: 16),
            _buildTabContent(),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _tabController,
              builder: (_, __) => _buildActions(),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 16),
              _buildResult(),
            ],
            const SizedBox(height: 28),
            _buildRecentJobs(),
          ]
              .animate(interval: 60.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.04, end: 0),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ingest Data', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 6),
        Text(
          'Import entity records via CSV paste, JSON batch, or large file upload (async, millions of records).',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Entity Type',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.mutedText)),
                const SizedBox(height: 6),
                _styledDropdown(
                  value: _selectedEntityType,
                  items: AppConstants.entityTypes,
                  onChanged: (v) => setState(() => _selectedEntityType = v!),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Source System',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.mutedText)),
                const SizedBox(height: 6),
                TextField(
                  decoration: _inputDecoration('e.g. SAP ERP'),
                  style: AppTextStyles.bodyMedium,
                  onChanged: (v) =>
                      _sourceSystem = v.trim().isEmpty ? 'Manual' : v.trim(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.mutedText,
      indicatorColor: AppColors.primary,
      tabs: const [
        Tab(icon: Icon(Icons.table_chart_outlined, size: 18), text: 'CSV Import'),
        Tab(icon: Icon(Icons.data_object_outlined, size: 18), text: 'JSON Batch'),
        Tab(icon: Icon(Icons.upload_file_outlined, size: 18), text: 'File Upload'),
      ],
    );
  }

  Widget _buildTabContent() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, __) => IndexedStack(
        index: _tabController.index,
        children: [
          _buildCsvTab(),
          _buildJsonTab(),
          _buildFileUploadTab(),
        ],
      ),
    );
  }

  Widget _buildCsvTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste CSV — first row must be column headers. '
          'Column names become entity attribute keys.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 10),
        _codeTextArea(_csvController, hint: 'name,email,phone\nAlice,...'),
      ],
    );
  }

  Widget _buildJsonTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Provide a JSON object with a "records" array. '
          '"tenant_id", "source_system", and "entity_type" are auto-filled from the options above.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 10),
        _codeTextArea(_jsonController, hint: '{ "records": [...] }'),
      ],
    );
  }

  Widget _buildActions() {
    // File Upload tab manages its own actions inline
    if (_tabController.index == 2) return const SizedBox.shrink();
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.upload_rounded, size: 18),
          label: Text(_isLoading ? 'Importing…' : 'Import Records'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () {
            if (_tabController.index == 0) {
              _csvController.text = _kSampleCsv;
            } else {
              _jsonController.text = _kSampleJson;
            }
            setState(() => _resultMessage = null);
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Reset to Sample'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.mutedText,
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // ── File Upload tab ────────────────────────────────────────────────────────

  Widget _buildFileUploadTab() {
    final job = _activeJob;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload a large CSV file (up to millions of records). '
          'The file is split into chunks and processed asynchronously. '
          'Track progress below — you can navigate away and return.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 16),

        // File picker row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _uploadSendProgress != null ? null : _pickFile,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Choose CSV File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _pickedFileName ?? 'No file selected',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _pickedFileName != null
                        ? AppColors.secondaryText
                        : AppColors.mutedText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_pickedFileName != null && _uploadSendProgress == null && _activeJobId == null)
                ElevatedButton.icon(
                  onPressed: _uploadFile,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('Upload & Ingest'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        ),

        // Upload send progress
        if (_uploadSendProgress != null) ...[
          const SizedBox(height: 16),
          _buildProgressCard(
            icon: Icons.upload_rounded,
            label: 'Uploading file…',
            fraction: _uploadSendProgress!,
            subtitle: '${(_uploadSendProgress! * 100).toStringAsFixed(0)}% sent',
            color: AppColors.primary,
          ),
        ],

        // Async job progress
        if (job != null) ...[
          const SizedBox(height: 16),
          _buildProgressCard(
            icon: job.status == 'completed'
                ? Icons.check_circle_outline
                : job.status == 'failed'
                    ? Icons.error_outline
                    : Icons.sync_rounded,
            label: job.status == 'completed'
                ? 'Ingest complete'
                : job.status == 'failed'
                    ? 'Ingest failed'
                    : 'Processing chunks…',
            fraction: job.progressFraction,
            subtitle: job.isAsync
                ? '${job.chunksDone}/${job.chunksTotal} chunks — '
                  '${job.processed} processed, ${job.failed} failed'
                : '${job.processed}/${job.totalRecords} records',
            color: job.status == 'completed'
                ? AppColors.success
                : job.status == 'failed'
                    ? AppColors.error
                    : AppColors.primary,
          ),
          if (job.status == 'completed' || job.status == 'failed') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _pickedFileName    = null;
                _pickedFileBytes   = null;
                _uploadSendProgress = null;
                _activeJobId       = null;
                _activeJob         = null;
                _pollTimer?.cancel();
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Upload Another File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.mutedText,
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildProgressCard({
    required IconData icon,
    required String label,
    required double fraction,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: AppTextStyles.bodyMedium.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    setState(() {
      _pickedFileName  = file.name;
      _pickedFileBytes = file.bytes?.toList();
      _activeJobId     = null;
      _activeJob       = null;
      _uploadSendProgress = null;
    });
  }

  Future<void> _uploadFile() async {
    final bytes = _pickedFileBytes;
    final name  = _pickedFileName;
    if (bytes == null || name == null) return;

    setState(() => _uploadSendProgress = 0.0);

    final result = await _ingestRepo.uploadCsvFile(
      sourceSystem: _sourceSystem,
      entityType:   _selectedEntityType,
      fileName:     name,
      fileBytes:    bytes,
      onProgress:   (sent, total) {
        if (!mounted || total == 0) return;
        setState(() => _uploadSendProgress = sent / total);
      },
    );

    if (!mounted) return;
    setState(() => _uploadSendProgress = null);

    if (!result.success || result.jobId == null) {
      setState(() {
        _resultIsError  = true;
        _resultMessage  = result.error ?? 'Upload failed';
      });
      return;
    }

    setState(() {
      _activeJobId = result.jobId;
      _activeJob   = null;
    });
    _pollJobProgress(result.jobId!);
    _loadRecentJobs();
  }

  void _pollJobProgress(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final job = await _ingestRepo.getJob(jobId);
      if (!mounted) return;
      setState(() => _activeJob = job);
      if (job != null &&
          (job.status == 'completed' || job.status == 'failed' || job.status == 'partial_success')) {
        _pollTimer?.cancel();
        _loadRecentJobs();
      }
    });
  }

  Widget _buildResult() {
    final color = _resultIsError ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(
            _resultIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _resultMessage!,
              style: AppTextStyles.bodyMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _buildRecentJobs() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Recent Jobs', style: AppTextStyles.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.mutedText),
                onPressed: _loadRecentJobs,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          if (_jobsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_recentJobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No jobs yet — submit an import to see history here.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
              ),
            )
          else
            ...(_recentJobs.map((job) => _buildJobRow(job))),
        ],
      ),
    );
  }

  Widget _buildJobRow(IngestJob job) {
    final statusColor = switch (job.status) {
      'completed'       => AppColors.success,
      'partial_success' => AppColors.warning,
      'failed'          => AppColors.error,
      _                 => AppColors.primary,
    };
    final ago = _formatAgo(job.createdAt);
    final isInProgress = job.isAsync &&
        job.status != 'completed' &&
        job.status != 'failed' &&
        job.status != 'partial_success';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.fileName ?? job.sourceSystem,
                  style: AppTextStyles.tableCell,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${job.processed}/${job.totalRecords}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText)),
              const SizedBox(width: 16),
              SizedBox(
                width: 84,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    job.status.replaceAll('_', ' '),
                    style: AppTextStyles.badgeLabel.copyWith(color: statusColor),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(ago, style: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText)),
            ],
          ),
          if (isInProgress) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: LinearProgressIndicator(
                value: job.progressFraction.clamp(0.0, 1.0),
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(statusColor),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _styledDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: AppColors.cardSurface,
      decoration: _inputDecoration(null),
      style: AppTextStyles.bodyMedium,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _codeTextArea(TextEditingController ctrl, {required String hint}) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.white70,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          contentPadding: const EdgeInsets.all(12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.mutedText),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }
}
