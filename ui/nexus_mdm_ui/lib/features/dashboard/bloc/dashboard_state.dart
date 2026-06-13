import 'package:equatable/equatable.dart';
import '../../../shared/models/dashboard_stats.dart';
import '../../../shared/models/activity_item.dart';

abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

/// No data loaded yet.
class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

/// Fetching data from the API.
class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

/// API responded successfully.
class DashboardLoaded extends DashboardState {
  final DashboardStats stats;
  final List<ActivityItem> activities;
  final String period;

  const DashboardLoaded({
    required this.stats,
    required this.activities,
    this.period = '7d',
  });

  DashboardLoaded copyWith({
    DashboardStats? stats,
    List<ActivityItem>? activities,
    String? period,
  }) =>
      DashboardLoaded(
        stats: stats ?? this.stats,
        activities: activities ?? this.activities,
        period: period ?? this.period,
      );

  @override
  List<Object?> get props => [stats, activities, period];
}

/// API call failed — showing demo data as a graceful fallback.
class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Server unreachable — rendering demo data with an offline banner.
class DashboardOffline extends DashboardState {
  final DashboardStats demoStats;
  final List<ActivityItem> demoActivities;
  final String message;

  const DashboardOffline({
    required this.demoStats,
    required this.demoActivities,
    this.message = 'Could not reach server — showing demo data.',
  });

  @override
  List<Object?> get props => [demoStats, message];
}
