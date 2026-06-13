import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/dashboard_stats.dart';
import '../../../shared/models/activity_item.dart';
import '../../../shared/models/api_responses.dart';

class DashboardRepository {
  final ApiClient _apiClient;

  DashboardRepository(this._apiClient);

  /// Fetches dashboard stats for the current tenant.
  Future<ApiResult<DashboardStats>> getStats(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.dashboardStatsPath,
      );
      final body = response.data;
      if (body == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      // mdm-core wraps responses: { "success": true, "data": {...} }
      final statsJson = body['data'] as Map<String, dynamic>? ?? body;
      return Success(DashboardStats.fromJson(statsJson));
    } catch (e) {
      assert(() {
        debugPrint('[DashboardRepository] getStats unexpected error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Fetches recent activity for the current tenant.
  Future<ApiResult<List<ActivityItem>>> getActivityFeed(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.activityPath,
      );
      final body = response.data;
      if (body == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      // Direct response is { "items": [...], "total": N }
      final items =
          (body['items'] as List<dynamic>? ?? body['data'] as List<dynamic>? ?? [])
              .map((item) => ActivityItem.fromJson(item as Map<String, dynamic>))
              .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[DashboardRepository] getActivityFeed unexpected error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
