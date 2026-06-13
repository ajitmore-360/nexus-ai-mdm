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

/// User tapped a type or status filter chip.
class EntityFilterChanged extends EntityEvent {
  final String? type;
  final String? status;

  const EntityFilterChanged({this.type, this.status});

  @override
  List<Object?> get props => [type, status];
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
