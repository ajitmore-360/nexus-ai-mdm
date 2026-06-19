import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/match_candidate.dart';
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// ReviewQueueItem — returned by GET /match/review-queue
// ---------------------------------------------------------------------------

class ReviewQueueItem {
  final String requestId;
  final String candidateId;
  final String sourceEntityId;
  final String candidateEntityId;
  final double score;
  final String status;
  final double? aiConfidence;
  final String? aiExplanation;
  final DateTime createdAt;

  const ReviewQueueItem({
    required this.requestId,
    required this.candidateId,
    required this.sourceEntityId,
    required this.candidateEntityId,
    required this.score,
    required this.status,
    this.aiConfidence,
    this.aiExplanation,
    required this.createdAt,
  });

  factory ReviewQueueItem.fromJson(Map<String, dynamic> json) => ReviewQueueItem(
        requestId: json['request_id'] as String? ?? json['id'] as String? ?? '',
        candidateId: json['candidate_id'] as String? ?? '',
        sourceEntityId: json['source_entity_id'] as String? ?? '',
        candidateEntityId: json['candidate_entity_id'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        status: json['status'] as String? ?? 'pending',
        aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
        aiExplanation: json['ai_explanation'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// MatchRepository
// ---------------------------------------------------------------------------

class MatchRepository {
  final ApiClient _apiClient;

  MatchRepository(this._apiClient);

  /// Returns pending match candidates from the queue.
  /// Falls back to [MatchCandidate.demoList] on error.
  Future<ApiResult<List<MatchCandidate>>> getQueue({
    int page = AppConstants.defaultPage,
    int pageSize = AppConstants.defaultPageSize,
    String? priority,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.matchQueuePath,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          if (priority != null) 'priority': priority,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response from server'));

      final items =
          (data['items'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [])
              .map((m) => MatchCandidate.fromJson(m as Map<String, dynamic>))
              .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] getQueue error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Approves (merges) a match candidate.
  Future<ApiResult<bool>> approveMatch(String candidateId) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '${AppConstants.matchQueuePath}/$candidateId/approve',
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] approveMatch error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Rejects a match candidate (marks as not a duplicate).
  Future<ApiResult<bool>> rejectMatch(String candidateId) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '${AppConstants.matchQueuePath}/$candidateId/reject',
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] rejectMatch error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Triggers the matching engine to re-run for a given entity.
  Future<ApiResult<MatchResponse>> executeMatch(String entityId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '${AppConstants.entitiesPath}/$entityId/match',
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      return Success(MatchResponse.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] executeMatch error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Returns the human-review queue via GET /match/review-queue.
  Future<ApiResult<List<ReviewQueueItem>>> getReviewQueue() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/match/review-queue',
      );
      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      final raw = data['data'] as Map<String, dynamic>? ?? data;
      final list = raw['items'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];
      final items = list
          .map((e) => ReviewQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] getReviewQueue error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Approves a match via the review-queue route:
  /// POST /match/{requestId}/candidates/{candidateId}/approve
  Future<ApiResult<bool>> approveReview(
      String requestId, String candidateId, {String? notes}) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/match/$requestId/candidates/$candidateId/approve',
        data: notes != null ? {'notes': notes} : null,
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] approveReview error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Rejects a match via the review-queue route:
  /// POST /match/{requestId}/candidates/{candidateId}/reject
  Future<ApiResult<bool>> rejectReview(
      String requestId, String candidateId, {String? notes}) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/match/$requestId/candidates/$candidateId/reject',
        data: notes != null ? {'notes': notes} : null,
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[MatchRepository] rejectReview error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
