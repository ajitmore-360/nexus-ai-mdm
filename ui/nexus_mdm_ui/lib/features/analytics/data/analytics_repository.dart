import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/dashboard_stats.dart';
import '../../../shared/models/api_responses.dart';
import 'package:flutter/foundation.dart';

class StewardPerformance {
  final String identityId;
  final String displayName;
  final String email;
  final int totalReviews;
  final int approvedCount;
  final int rejectedCount;
  final double approvalPct;
  final double avgReviewMin;

  const StewardPerformance({
    required this.identityId,
    required this.displayName,
    required this.email,
    required this.totalReviews,
    required this.approvedCount,
    required this.rejectedCount,
    required this.approvalPct,
    required this.avgReviewMin,
  });

  factory StewardPerformance.fromJson(Map<String, dynamic> json) =>
      StewardPerformance(
        identityId:    json['identity_id'] as String? ?? '',
        displayName:   json['display_name'] as String? ?? 'Unknown',
        email:         json['email'] as String? ?? '',
        totalReviews:  (json['total_reviews'] as num?)?.toInt() ?? 0,
        approvedCount: (json['approved_count'] as num?)?.toInt() ?? 0,
        rejectedCount: (json['rejected_count'] as num?)?.toInt() ?? 0,
        approvalPct:   (json['approval_pct'] as num?)?.toDouble() ?? 0.0,
        avgReviewMin:  (json['avg_review_min'] as num?)?.toDouble() ?? 0.0,
      );
}

class AnalyticsData {
  final DashboardStats stats;
  final List<StewardPerformance> stewards;

  const AnalyticsData({required this.stats, required this.stewards});
}

class AnalyticsRepository {
  final ApiClient _apiClient;

  AnalyticsRepository(this._apiClient);

  Future<ApiResult<AnalyticsData>> getAnalytics() async {
    try {
      final statsResponse = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.dashboardStatsPath,
      );
      final statsBody = statsResponse.data;
      if (statsBody == null) {
        return const Failure(ApiException(message: 'Empty stats response'));
      }
      final statsJson = statsBody['data'] as Map<String, dynamic>? ?? statsBody;
      final stats = DashboardStats.fromJson(statsJson);

      final stewardResponse = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.stewardPerformancePath,
      );
      final stewardBody = stewardResponse.data;
      final stewardList = stewardBody == null
          ? <StewardPerformance>[]
          : ((stewardBody['stewards'] as List<dynamic>?) ?? [])
              .map((s) => StewardPerformance.fromJson(s as Map<String, dynamic>))
              .toList();

      return Success(AnalyticsData(stats: stats, stewards: stewardList));
    } catch (e) {
      assert(() {
        debugPrint('[AnalyticsRepository] getAnalytics error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
