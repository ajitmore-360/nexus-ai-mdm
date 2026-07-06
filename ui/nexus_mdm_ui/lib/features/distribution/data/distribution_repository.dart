import 'package:flutter/foundation.dart';
import '../../../core/auth/auth_manager.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class DistributionJob {
  final String id;
  final String tenantId;
  final String connectorId;
  final String entityId;
  final String entityType;
  final String status;
  final int attempts;
  final String? errorMessage;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  const DistributionJob({
    required this.id,
    required this.tenantId,
    required this.connectorId,
    required this.entityId,
    required this.entityType,
    required this.status,
    required this.attempts,
    this.errorMessage,
    this.scheduledAt,
    this.completedAt,
    required this.createdAt,
  });

  factory DistributionJob.fromJson(Map<String, dynamic> json) => DistributionJob(
        id: (json['job_id'] ?? json['id'] ?? '').toString(),
        tenantId: (json['tenant_id'] ?? '').toString(),
        connectorId: (json['connector_id'] ?? '').toString(),
        entityId: (json['entity_id'] ?? '').toString(),
        entityType: json['entity_type'] as String? ?? 'Unknown',
        status: json['status'] as String? ?? 'pending',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        errorMessage: json['error_message'] as String?,
        scheduledAt: json['scheduled_at'] != null
            ? DateTime.tryParse(json['scheduled_at'] as String)
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.tryParse(json['completed_at'] as String)
            : null,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class DistributionRepository {
  final ApiClient _apiClient;

  DistributionRepository(this._apiClient);

  Future<ApiResult<List<DistributionJob>>> getJobs({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final tenantId = await AuthManager.getTenantId() ?? '';

      final params = <String, dynamic>{
        'tenant_id': tenantId,
        'limit': limit,
        'offset': offset,
        if (status != null) 'status': status,
      };

      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.distributionPath,
        queryParameters: params,
      );

      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }

      // API returns { "success": true, "data": { "items": [...] } }
      final inner = data['data'] as Map<String, dynamic>? ?? data;
      final list = inner['items'] as List<dynamic>? ??
          inner['data'] as List<dynamic>? ??
          [];

      final jobs = list
          .map((e) => DistributionJob.fromJson(e as Map<String, dynamic>))
          .toList();

      return Success(jobs);
    } catch (e) {
      assert(() {
        debugPrint('[DistributionRepository] getJobs error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
