import '../../../core/network/api_client.dart';

class IngestJob {
  final String jobId;
  final String batchId;
  final String sourceSystem;
  final String status;
  final int totalRecords;
  final int processed;
  final int failed;
  final int durationMs;
  final String? fileName;
  final DateTime createdAt;

  const IngestJob({
    required this.jobId,
    required this.batchId,
    required this.sourceSystem,
    required this.status,
    required this.totalRecords,
    required this.processed,
    required this.failed,
    required this.durationMs,
    this.fileName,
    required this.createdAt,
  });

  factory IngestJob.fromJson(Map<String, dynamic> json) {
    return IngestJob(
      jobId:        json['job_id']        as String? ?? '',
      batchId:      json['batch_id']      as String? ?? '',
      sourceSystem: json['source_system'] as String? ?? '',
      status:       json['status']        as String? ?? '',
      totalRecords: json['total_records'] as int? ?? 0,
      processed:    json['processed']     as int? ?? 0,
      failed:       json['failed']        as int? ?? 0,
      durationMs:   json['duration_ms']   as int? ?? 0,
      fileName:     json['file_name']     as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class IngestRepository {
  final ApiClient _client;

  IngestRepository(this._client);

  Future<List<IngestJob>> listJobs({
    required String tenantId,
    int page = 1,
    int pageSize = 10,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/v1/ingest/jobs',
      queryParameters: {
        'tenant_id': tenantId,
        'page':      page,
        'page_size': pageSize,
      },
    );

    final data  = response.data!;
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items
        .map((e) => IngestJob.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
