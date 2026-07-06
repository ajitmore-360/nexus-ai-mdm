import 'package:equatable/equatable.dart';

abstract class EntityEvent extends Equatable {
  const EntityEvent();

  @override
  List<Object?> get props => [];
}

/// User typed in the search box. Debounced 300 ms inside the BLoC.
class EntitySearchRequested extends EntityEvent {
  final String query;
  final String? entityType;

  const EntitySearchRequested(this.query, {this.entityType});

  @override
  List<Object?> get props => [query, entityType];
}

/// User scrolled to the bottom of the list.
class EntityLoadMoreRequested extends EntityEvent {
  const EntityLoadMoreRequested();
}

/// User tapped a type, status, or source filter chip, or changed sort order.
class EntityFilterChanged extends EntityEvent {
  final String? type;
  final String? status;
  final String? sourceSystem;
  /// Column to sort by: 'created_at' | 'updated_at' | 'trust_score' | 'entity_type' | 'status'
  final String? sortBy;
  /// Sort direction: 'asc' or 'desc'.
  final String? sortDir;

  const EntityFilterChanged({
    this.type,
    this.status,
    this.sourceSystem,
    this.sortBy,
    this.sortDir,
  });

  @override
  List<Object?> get props => [type, status, sourceSystem, sortBy, sortDir];
}

/// User triggered pull-to-refresh or tapped retry.
class EntityRefreshRequested extends EntityEvent {
  const EntityRefreshRequested();
}

/// Internal debounce event — fired after 300 ms with the buffered query.
/// Prefixed with $ to signal it is an implementation detail, not public API.
class EntitySearchDebounced extends EntityEvent {
  final String query;
  final String? entityType;

  const EntitySearchDebounced(this.query, {this.entityType});

  @override
  List<Object?> get props => [query, entityType];
}
