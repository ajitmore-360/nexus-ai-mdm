import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/entity_repository.dart';
import '../../../shared/models/api_responses.dart';
import '../../../shared/models/entity.dart';
import 'entity_event.dart';
import 'entity_state.dart';

class EntityBloc extends Bloc<EntityEvent, EntityState> {
  final EntityRepository _repository;

  static const int _pageSize = 25;

  // State kept between events so refresh / load-more can replay filters.
  String _lastQuery = '';
  String? _lastType;
  String? _lastStatus;
  int _currentPage = 1;

  // Debounce timer for search input.
  Timer? _debounceTimer;

  EntityBloc(this._repository) : super(const EntityInitial()) {
    on<EntitySearchRequested>(_onSearchRequested);
    on<EntitySearchDebounced>(_onSearchDebounced);
    on<EntityLoadMoreRequested>(_onLoadMore);
    on<EntityFilterChanged>(_onFilterChanged);
    on<EntityRefreshRequested>(_onRefresh);
  }

  // ── Handlers ─────────────────────────────────

  void _onSearchRequested(
    EntitySearchRequested event,
    Emitter<EntityState> emit,
  ) {
    // Cancel any pending debounce and start a fresh 300 ms window.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        if (!isClosed) {
          add(EntitySearchDebounced(
            event.query,
            entityType: event.entityType ?? _lastType,
          ));
        }
      },
    );
  }

  Future<void> _onSearchDebounced(
    EntitySearchDebounced event,
    Emitter<EntityState> emit,
  ) async {
    _lastQuery = event.query;
    if (event.entityType != null) _lastType = event.entityType;
    _currentPage = 1;
    emit(const EntityLoading());
    await _fetchPage(emit, page: 1, replace: true);
  }

  Future<void> _onLoadMore(
    EntityLoadMoreRequested event,
    Emitter<EntityState> emit,
  ) async {
    final current = state;
    if (current is! EntityLoaded || !current.hasMore || current.isLoadingMore) {
      return;
    }

    final nextPage = _currentPage + 1;
    // Show a spinner at the bottom without clearing the list.
    emit(current.copyWith(isLoadingMore: true));
    await _fetchPage(emit, page: nextPage, replace: false);
  }

  Future<void> _onFilterChanged(
    EntityFilterChanged event,
    Emitter<EntityState> emit,
  ) async {
    _lastType = event.type;
    _lastStatus = event.status;
    _currentPage = 1;
    emit(const EntityLoading());
    await _fetchPage(emit, page: 1, replace: true);
  }

  Future<void> _onRefresh(
    EntityRefreshRequested event,
    Emitter<EntityState> emit,
  ) async {
    _currentPage = 1;
    emit(const EntityLoading());
    await _fetchPage(emit, page: 1, replace: true);
  }

  // ── Core fetch ───────────────────────────────

  Future<void> _fetchPage(
    Emitter<EntityState> emit, {
    required int page,
    required bool replace,
  }) async {
    try {
      final result = await _repository.getEntities(
        page: page,
        pageSize: _pageSize,
        search: _lastQuery.isEmpty ? null : _lastQuery,
        type: _lastType?.toLowerCase(),
        status: _lastStatus?.toLowerCase(),
      );

      switch (result) {
        case Success<EntityPage>(:final data):
          _currentPage = data.page;
          final incoming = data.items;
          final existing = (!replace && state is EntityLoaded)
              ? (state as EntityLoaded).entities
              : <CanonicalEntity>[];

          emit(EntityLoaded(
            entities: [...existing, ...incoming],
            hasMore: data.hasNextPage,
            total: data.totalCount,
          ));

        case Failure<EntityPage>(:final exception):
          if (replace) {
            // Show demo data with an error state on first load.
            emit(EntityError(exception.message));
          } else {
            // Load-more failed — keep existing list, clear the spinner.
            if (state is EntityLoaded) {
              emit((state as EntityLoaded).copyWith(isLoadingMore: false));
            }
          }
      }
    } catch (e) {
      if (replace) {
        emit(EntityLoaded(
          entities: CanonicalEntity.demoList,
          hasMore: false,
          total: CanonicalEntity.demoList.length,
        ));
      } else if (state is EntityLoaded) {
        emit((state as EntityLoaded).copyWith(isLoadingMore: false));
      }
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
