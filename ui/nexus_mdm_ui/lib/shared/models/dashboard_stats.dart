import 'package:equatable/equatable.dart';

class DashboardStats extends Equatable {
  final int totalEntities;
  final int totalGoldenRecords;
  final int pendingReview;
  final double aiMatchScore;
  final double entityGrowthRate;
  final double goldenRecordGrowthRate;
  final int pendingReviewDelta;
  final double aiScoreDelta;
  final List<MatchActivityPoint> matchActivity;
  final List<DuplicateSourcePoint> topDuplicateSources;
  final int mergedToday;
  final int newEntitiesToday;
  final double overallDataQuality;

  const DashboardStats({
    required this.totalEntities,
    required this.totalGoldenRecords,
    required this.pendingReview,
    required this.aiMatchScore,
    required this.entityGrowthRate,
    required this.goldenRecordGrowthRate,
    required this.pendingReviewDelta,
    required this.aiScoreDelta,
    required this.matchActivity,
    required this.topDuplicateSources,
    required this.mergedToday,
    required this.newEntitiesToday,
    required this.overallDataQuality,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalEntities:         (json['total_entities'] as num?)?.toInt() ?? 0,
      totalGoldenRecords:    (json['total_golden_records'] as num?)?.toInt() ?? 0,
      pendingReview:         (json['pending_review'] as num?)?.toInt() ?? 0,
      aiMatchScore:          (json['ai_match_score'] as num?)?.toDouble() ?? 0.0,
      entityGrowthRate:      (json['entity_growth_rate'] as num?)?.toDouble() ?? 0.0,
      goldenRecordGrowthRate:(json['golden_record_growth_rate'] as num?)?.toDouble() ?? 0.0,
      pendingReviewDelta:    (json['pending_review_delta'] as num?)?.toInt() ?? 0,
      aiScoreDelta:          (json['ai_score_delta'] as num?)?.toDouble() ?? 0.0,
      matchActivity: (json['match_activity'] as List<dynamic>? ?? [])
          .map((a) => MatchActivityPoint.fromJson(a as Map<String, dynamic>))
          .toList(),
      topDuplicateSources:
          (json['top_duplicate_sources'] as List<dynamic>? ?? [])
              .map((s) => DuplicateSourcePoint.fromJson(s as Map<String, dynamic>))
              .toList(),
      mergedToday:         (json['merged_today'] as num?)?.toInt() ?? 0,
      newEntitiesToday:    (json['new_entities_today'] as num?)?.toInt() ?? 0,
      overallDataQuality:  (json['overall_data_quality'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_entities': totalEntities,
        'total_golden_records': totalGoldenRecords,
        'pending_review': pendingReview,
        'ai_match_score': aiMatchScore,
        'entity_growth_rate': entityGrowthRate,
        'golden_record_growth_rate': goldenRecordGrowthRate,
        'pending_review_delta': pendingReviewDelta,
        'ai_score_delta': aiScoreDelta,
        'match_activity':
            matchActivity.map((a) => a.toJson()).toList(),
        'top_duplicate_sources':
            topDuplicateSources.map((s) => s.toJson()).toList(),
        'merged_today': mergedToday,
        'new_entities_today': newEntitiesToday,
        'overall_data_quality': overallDataQuality,
      };

  static DashboardStats get demo => DashboardStats(
        totalEntities: 247583,
        totalGoldenRecords: 198421,
        pendingReview: 1247,
        aiMatchScore: 94.7,
        entityGrowthRate: 12.4,
        goldenRecordGrowthRate: 8.2,
        pendingReviewDelta: -23,
        aiScoreDelta: 1.3,
        mergedToday: 184,
        newEntitiesToday: 2341,
        overallDataQuality: 87.3,
        matchActivity: List.generate(
          14,
          (i) => MatchActivityPoint(
            date: DateTime.now().subtract(Duration(days: 13 - i)),
            autoMerged: 150 + (i * 12) + (i % 3 == 0 ? 50 : 0),
            manualMerged: 30 + (i * 3),
            rejected: 15 + (i % 4),
            pending: 40 - i,
          ),
        ),
        topDuplicateSources: const [
          DuplicateSourcePoint(
              source: 'Salesforce CRM', count: 523, percentage: 0.34),
          DuplicateSourcePoint(
              source: 'CSV Import', count: 389, percentage: 0.25),
          DuplicateSourcePoint(
              source: 'HubSpot', count: 287, percentage: 0.19),
          DuplicateSourcePoint(
              source: 'SAP ERP', count: 198, percentage: 0.13),
          DuplicateSourcePoint(
              source: 'Manual Entry', count: 142, percentage: 0.09),
        ],
      );

  @override
  List<Object?> get props => [
        totalEntities,
        totalGoldenRecords,
        pendingReview,
        aiMatchScore,
      ];
}

class MatchActivityPoint extends Equatable {
  final DateTime date;
  final int autoMerged;
  final int manualMerged;
  final int rejected;
  final int pending;

  const MatchActivityPoint({
    required this.date,
    required this.autoMerged,
    required this.manualMerged,
    required this.rejected,
    required this.pending,
  });

  int get total => autoMerged + manualMerged + rejected + pending;

  factory MatchActivityPoint.fromJson(Map<String, dynamic> json) =>
      MatchActivityPoint(
        date:        DateTime.parse(json['date'] as String),
        autoMerged:  (json['auto_merged'] as num?)?.toInt() ?? 0,
        manualMerged:(json['manual_merged'] as num?)?.toInt() ?? 0,
        rejected:    (json['rejected'] as num?)?.toInt() ?? 0,
        pending:     (json['pending'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'auto_merged': autoMerged,
        'manual_merged': manualMerged,
        'rejected': rejected,
        'pending': pending,
      };

  @override
  List<Object?> get props => [date, autoMerged, manualMerged];
}

class DuplicateSourcePoint extends Equatable {
  final String source;
  final int count;
  final double percentage;

  const DuplicateSourcePoint({
    required this.source,
    required this.count,
    required this.percentage,
  });

  factory DuplicateSourcePoint.fromJson(Map<String, dynamic> json) =>
      DuplicateSourcePoint(
        source:     json['source'] as String? ?? 'Unknown',
        count:      (json['count'] as num?)?.toInt() ?? 0,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'count': count,
        'percentage': percentage,
      };

  @override
  List<Object?> get props => [source, count, percentage];
}
