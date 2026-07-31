import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

class IngestJob {
  final String jobId;
  final String batchId;
  final String sourceSystem;
  final String status;
  final int totalRecords;
  final int processed;
  final int failed;
  final int chunksTotal;
  final int chunksDone;
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
    required this.chunksTotal,
    required this.chunksDone,
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
      chunksTotal:  json['chunks_total']  as int? ?? 0,
      chunksDone:   json['chunks_done']   as int? ?? 0,
      durationMs:   json['duration_ms']   as int? ?? 0,
      fileName:     json['file_name']     as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isAsync => chunksTotal > 0;

  double get progressFraction {
    if (!isAsync || chunksTotal == 0) return processed > 0 ? 1.0 : 0.0;
    return chunksDone / chunksTotal;
  }
}

class IngestUploadResult {
  final bool success;
  final String? jobId;
  final int totalRecords;
  final int chunksQueued;
  final String? error;
  final String? message;
  final bool configurationRequired;
  final List<String> missingConfiguration;
  final String? affectedEntityType;

  const IngestUploadResult({
    required this.success,
    this.jobId,
    this.totalRecords = 0,
    this.chunksQueued = 0,
    this.error,
    this.message,
    this.configurationRequired = false,
    this.missingConfiguration = const [],
    this.affectedEntityType,
  });
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

  /// Upload a large CSV file using multipart/form-data.
  /// The server enqueues the file as async chunks and returns a job_id
  /// immediately (HTTP 202 Accepted). Progress is polled via [getJob].
  Future<IngestUploadResult> uploadCsvFile({
    required String sourceSystem,
    required String entityType,
    required String fileName,
    required List<int> fileBytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'source_system': sourceSystem,
        'entity_type':   entityType,
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
          contentType: DioMediaType('text', 'csv'),
        ),
      });

      final response = await _client.post<Map<String, dynamic>>(
        '/v1/ingest/csv/upload',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
        onSendProgress: onProgress,
      );

      final body = response.data ?? {};
      return IngestUploadResult(
        success:      body['success'] as bool? ?? false,
        jobId:        body['job_id']  as String?,
        totalRecords: body['total_records'] as int? ?? 0,
        chunksQueued: body['chunks_queued'] as int? ?? 0,
        message:      body['message'] as String?,
        error:        body['error']   as String?,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['configuration_required'] == true) {
        return IngestUploadResult(
          success: false,
          configurationRequired: true,
          missingConfiguration:
              (body['missing'] as List<dynamic>? ?? []).cast<String>(),
          affectedEntityType: body['entity_type'] as String?,
          error: 'System not configured for ingest',
        );
      }
      final errorMsg = (body is Map ? body['error']?.toString() : null)
          ?? e.message
          ?? 'Upload failed';
      return IngestUploadResult(success: false, error: errorMsg);
    } catch (e) {
      return IngestUploadResult(success: false, error: e.toString());
    }
  }

  Future<IngestJob?> getJob(String jobId) async {
    final response = await _client.get<Map<String, dynamic>>('/v1/ingest/jobs/$jobId');
    final data = response.data;
    if (data == null || data['success'] != true) return null;
    return IngestJob.fromJson(data['job'] as Map<String, dynamic>);
  }
}
