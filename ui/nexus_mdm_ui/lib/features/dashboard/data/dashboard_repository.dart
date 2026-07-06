import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/dashboard_stats.dart';
import '../../../shared/models/activity_item.dart';
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// Data models for quality dimensions and steward performance
// ---------------------------------------------------------------------------

class QualityDimensions {
  final double completeness;
  final double accuracy;
  final double consistency;
  final double uniqueness;
  final double timeliness;
  final double validity;

  const QualityDimensions({
    required this.completeness,
    required this.accuracy,
    required this.consistency,
    required this.uniqueness,
    required this.timeliness,
    required this.validity,
  });

  factory QualityDimensions.fromJson(Map<String, dynamic> json) {
    final d = json['dimensions'] as Map<String, dynamic>? ?? json;
    double v(String k) => (d[k] as num?)?.toDouble() ?? 0.0;
    return QualityDimensions(
      completeness: v('completeness'),
      accuracy:     v('accuracy'),
      consistency:  v('consistency'),
      uniqueness:   v('uniqueness'),
      timeliness:   v('timeliness'),
      validity:     v('validity'),
    );
  }

  static const empty = QualityDimensions(
    completeness: 0, accuracy: 0, consistency: 0,
    uniqueness: 0, timeliness: 0, validity: 0,
  );

  double get overallScore =>
      (completeness + accuracy + consistency + uniqueness + timeliness + validity) / 6.0;
}

class StewardStat {
  final String displayName;
  final String email;
  final int    totalReviews;
  final int    approvedCount;
  final int    rejectedCount;
  final double approvalPct;
  final double avgReviewMin;

  const StewardStat({
    required this.displayName,
    required this.email,
    required this.totalReviews,
    required this.approvedCount,
    required this.rejectedCount,
    required this.approvalPct,
    required this.avgReviewMin,
  });

  factory StewardStat.fromJson(Map<String, dynamic> json) => StewardStat(
    displayName:   json['display_name']  as String? ?? '',
    email:         json['email']         as String? ?? '',
    totalReviews:  (json['total_reviews']  as num?)?.toInt()   ?? 0,
    approvedCount: (json['approved_count'] as num?)?.toInt()   ?? 0,
    rejectedCount: (json['rejected_count'] as num?)?.toInt()   ?? 0,
    approvalPct:   (json['approval_pct']   as num?)?.toDouble() ?? 0.0,
    avgReviewMin:  (json['avg_review_min'] as num?)?.toDouble() ?? 0.0,
  );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

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

  /// Fetches the 6 data-quality dimension scores for the tenant.
  Future<QualityDimensions> getQualityDimensions() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.qualityDimensionsPath,
      );
      final body = response.data;
      if (body == null) return QualityDimensions.empty;
      return QualityDimensions.fromJson(body);
    } catch (e) {
      assert(() { debugPrint('[DashboardRepository] getQualityDimensions error: $e'); return true; }());
      return QualityDimensions.empty;
    }
  }

  /// Fetches top steward performance stats for the tenant.
  Future<List<StewardStat>> getStewardPerformance() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.stewardPerformancePath,
      );
      final body = response.data;
      if (body == null) return const [];
      final list = body['stewards'] as List<dynamic>? ?? [];
      return list
          .map((e) => StewardStat.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      assert(() { debugPrint('[DashboardRepository] getStewardPerformance error: $e'); return true; }());
      return const [];
    }
  }
}
