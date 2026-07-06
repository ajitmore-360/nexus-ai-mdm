import 'package:equatable/equatable.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Fired on initial page load.
class DashboardLoadRequested extends DashboardEvent {
  const DashboardLoadRequested();
}

/// Fired by the pull-to-refresh control or retry button.
class DashboardRefreshRequested extends DashboardEvent {
  const DashboardRefreshRequested();
}

/// Fired when the user selects a different time period from the header.
class DashboardPeriodChanged extends DashboardEvent {
  final String period;

  const DashboardPeriodChanged(this.period);

  @override
  List<Object?> get props => [period];
}

/// Internal event: fired by the auto-refresh Timer every 60 seconds.
/// Not part of the public API — treated as an implementation detail.
class DashboardAutoRefresh extends DashboardEvent {
  const DashboardAutoRefresh();
}

/// Internal event: fired when a real-time WebSocket event arrives that
/// affects dashboard data (entity ingested, match approved/rejected, etc.).
/// Triggers a silent stat refresh without showing a loading spinner.
class DashboardRealtimeUpdate extends DashboardEvent {
  final String eventType;

  const DashboardRealtimeUpdate(this.eventType);

  @override
  List<Object?> get props => [eventType];
}
