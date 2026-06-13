import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/match_candidate.dart';
import '../../../shared/models/api_responses.dart';

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
}
