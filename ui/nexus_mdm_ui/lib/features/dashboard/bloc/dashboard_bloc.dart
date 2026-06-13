import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/dashboard_repository.dart';
import '../../../shared/models/api_responses.dart';
import '../../../shared/models/dashboard_stats.dart';
import '../../../shared/models/activity_item.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository _repository;
  Timer? _autoRefreshTimer;

  // Demo tenant ID used when no tenant is in prefs.
  static const String _defaultTenantId =
      '00000000-0000-0000-0000-000000000001';
  static const Duration _autoRefreshInterval = Duration(seconds: 60);

  DashboardBloc(this._repository) : super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
    on<DashboardRefreshRequested>(_onRefresh);
    on<DashboardPeriodChanged>(_onPeriodChanged);
    on<DashboardAutoRefresh>(_onAutoRefresh);
  }

  // ── Handlers ─────────────────────────────────

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    await _fetch(emit, period: '7d');
    _startAutoRefresh();
  }

  Future<void> _onRefresh(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    final currentPeriod =
        state is DashboardLoaded ? (state as DashboardLoaded).period : '7d';
    emit(const DashboardLoading());
    await _fetch(emit, period: currentPeriod);
  }

  Future<void> _onPeriodChanged(
    DashboardPeriodChanged event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    await _fetch(emit, period: event.period);
  }

  Future<void> _onAutoRefresh(
    DashboardAutoRefresh event,
    Emitter<DashboardState> emit,
  ) async {
    // Only auto-refresh when actively loaded (not during manual loading).
    if (state is! DashboardLoaded && state is! DashboardOffline) return;
    final currentPeriod =
        state is DashboardLoaded ? (state as DashboardLoaded).period : '7d';
    await _fetch(emit, period: currentPeriod, silent: true);
  }

  // ── Core fetch logic ─────────────────────────

  Future<void> _fetch(
    Emitter<DashboardState> emit, {
    required String period,
    bool silent = false,
  }) async {
    try {
      final statsResult = await _repository.getStats(_defaultTenantId);
      final activityResult =
          await _repository.getActivityFeed(_defaultTenantId);

      DashboardStats stats;
      List<ActivityItem> activities;
      bool hadError = false;
      String errorMsg = '';

      switch (statsResult) {
        case Success<DashboardStats>(:final data):
          stats = data;
        case Failure<DashboardStats>(:final exception):
          stats = DashboardStats.demo;
          hadError = true;
          errorMsg = exception.message;
      }

      switch (activityResult) {
        case Success<List<ActivityItem>>(:final data):
          activities = data;
        case Failure<List<ActivityItem>>(:final exception):
          activities = ActivityItem.demoList;
          hadError = true;
          if (errorMsg.isEmpty) errorMsg = exception.message;
      }

      if (hadError) {
        emit(DashboardOffline(
          demoStats: stats,
          demoActivities: activities,
          message: 'Could not reach server — showing demo data. $errorMsg',
        ));
      } else {
        emit(DashboardLoaded(
          stats: stats,
          activities: activities,
          period: period,
        ));
      }
    } catch (e) {
      if (!silent) {
        emit(DashboardOffline(
          demoStats: DashboardStats.demo,
          demoActivities: ActivityItem.demoList,
          message: 'Unexpected error: $e',
        ));
      }
    }
  }

  // ── Auto-refresh ─────────────────────────────

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(_autoRefreshInterval, (_) {
      if (!isClosed) {
        add(const DashboardAutoRefresh());
      }
    });
  }

  @override
  Future<void> close() {
    _autoRefreshTimer?.cancel();
    return super.close();
  }
}
