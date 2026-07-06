import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// QueueMetrics — returned by GET /v1/match/queue-metrics
// ---------------------------------------------------------------------------

class QueueMetrics {
  final int pendingTotal;
  final Map<String, int> pendingByPriority;
  final int slaBreached;
  final double avgAgeHours;

  const QueueMetrics({
    required this.pendingTotal,
    required this.pendingByPriority,
    required this.slaBreached,
    required this.avgAgeHours,
  });

  factory QueueMetrics.fromJson(Map<String, dynamic> json) {
    final raw = json['data'] as Map<String, dynamic>? ?? json;
    final byPriority = raw['pending_by_priority'] as Map<String, dynamic>? ?? {};
    return QueueMetrics(
      pendingTotal: raw['pending_total'] as int? ?? 0,
      pendingByPriority: byPriority.map(
        (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
      ),
      slaBreached: raw['sla_breached'] as int? ?? 0,
      avgAgeHours: (raw['avg_age_hours'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// FieldMatchSummary — lightweight field comparison inside a ReviewItem
// ---------------------------------------------------------------------------

class FieldMatchSummary {
  final String field;
  final String sourceValue;
  final String targetValue;
  final double score;

  const FieldMatchSummary({
    required this.field,
    required this.sourceValue,
    required this.targetValue,
    required this.score,
  });

  factory FieldMatchSummary.fromJson(Map<String, dynamic> json) =>
      FieldMatchSummary(
        field: json['field'] as String? ??
            json['field_name'] as String? ??
            '',
        sourceValue: (json['source_value'] ?? '').toString(),
        targetValue: (json['target_value'] ?? '').toString(),
        score: (json['score'] as num?)?.toDouble() ??
            (json['similarity'] as num?)?.toDouble() ??
            0.0,
      );
}

// ---------------------------------------------------------------------------
// ReviewItem — one entry in the human-review queue
// ---------------------------------------------------------------------------

class ReviewItem {
  final String reviewId;
  final String requestId;
  final String candidateId;
  final String sourceEntityName;
  final String targetEntityName;
  final double overallScore;
  final String priority;
  final String entityType;
  final DateTime createdAt;
  final String? aiExplanation;
  final List<FieldMatchSummary> fieldMatches;

  const ReviewItem({
    required this.reviewId,
    required this.requestId,
    required this.candidateId,
    required this.sourceEntityName,
    required this.targetEntityName,
    required this.overallScore,
    required this.priority,
    required this.entityType,
    required this.createdAt,
    this.aiExplanation,
    this.fieldMatches = const [],
  });

  /// Whether this item has breached the 24-hour SLA window.
  bool get isSlaBreached =>
      DateTime.now().difference(createdAt).inHours >= 24;

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    final fields = json['field_matches'] as List<dynamic>? ?? [];
    return ReviewItem(
      reviewId: json['review_id'] as String? ??
          json['id'] as String? ??
          '',
      requestId: json['request_id'] as String? ??
          json['review_id'] as String? ??
          json['id'] as String? ??
          '',
      candidateId: json['candidate_id'] as String? ?? '',
      sourceEntityName: json['source_entity_name'] as String? ?? '',
      targetEntityName: json['target_entity_name'] as String? ??
          json['candidate_entity_name'] as String? ??
          '',
      overallScore: (json['overall_score'] as num?)?.toDouble() ??
          (json['score'] as num?)?.toDouble() ??
          0.0,
      priority: json['priority'] as String? ?? 'normal',
      entityType: json['entity_type'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      aiExplanation: json['ai_explanation'] as String?,
      fieldMatches: fields
          .map((f) =>
              FieldMatchSummary.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// MatchQueueRepository
// ---------------------------------------------------------------------------

class MatchQueueRepository {
  final ApiClient _client;

  MatchQueueRepository({required ApiClient client}) : _client = client;

  /// GET /v1/match/queue-metrics
  Future<ApiResult<QueueMetrics>> getQueueMetrics({
    required String tenantId,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/v1/match/queue-metrics',
        queryParameters: {'tenant_id': tenantId},
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      return Success(QueueMetrics.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] getQueueMetrics error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// GET /v1/match/review-queue
  Future<ApiResult<List<ReviewItem>>> listQueue({
    required String tenantId,
    String? entityType,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/v1/match/review-queue',
        queryParameters: {
          'tenant_id': tenantId,
          'page': page,
          'page_size': pageSize,
          if (entityType != null && entityType.isNotEmpty)
            'entity_type': entityType,
        },
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      // Support both { items: [] } and { data: { items: [] } } envelopes.
      final envelope = data['data'] as Map<String, dynamic>? ?? data;
      final rawItems = envelope['items'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];
      final items = rawItems
          .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] listQueue error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// POST /v1/match/{requestId}/candidates/{candidateId}/approve
  Future<ApiResult<void>> approve({
    required String tenantId,
    required String requestId,
    required String candidateId,
    String? notes,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/v1/match/$requestId/candidates/$candidateId/approve',
        data: {
          'tenant_id': tenantId,
          if (notes != null) 'notes': notes,
        },
      );
      return const Success(null);
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] approve error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// POST /v1/match/{requestId}/candidates/{candidateId}/reject
  Future<ApiResult<void>> reject({
    required String tenantId,
    required String requestId,
    required String candidateId,
    String? notes,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/v1/match/$requestId/candidates/$candidateId/reject',
        data: {
          'tenant_id': tenantId,
          if (notes != null) 'notes': notes,
        },
      );
      return const Success(null);
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] reject error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// POST /v1/match/{requestId}/candidates/{candidateId}/defer
  Future<ApiResult<void>> defer({
    required String tenantId,
    required String requestId,
    required String candidateId,
    String? reason,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/v1/match/$requestId/candidates/$candidateId/defer',
        data: {
          'tenant_id': tenantId,
          if (reason != null) 'reason': reason,
        },
      );
      return const Success(null);
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] defer error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// POST /v1/match/bulk-approve   body: { candidate_ids: [...] }
  Future<ApiResult<Map<String, dynamic>>> bulkApprove({
    required String tenantId,
    required List<String> candidateIds,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/v1/match/bulk-approve',
        data: {
          'tenant_id': tenantId,
          'candidate_ids': candidateIds,
        },
      );
      return Success(response.data ?? {});
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] bulkApprove error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// POST /v1/match/bulk-reject   body: { candidate_ids: [...] }
  Future<ApiResult<Map<String, dynamic>>> bulkReject({
    required String tenantId,
    required List<String> candidateIds,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/v1/match/bulk-reject',
        data: {
          'tenant_id': tenantId,
          'candidate_ids': candidateIds,
        },
      );
      return Success(response.data ?? {});
    } catch (e) {
      assert(() {
        debugPrint('[MatchQueueRepository] bulkReject error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
