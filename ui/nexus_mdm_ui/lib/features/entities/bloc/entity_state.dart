import 'package:equatable/equatable.dart';
import '../../../shared/models/entity.dart';

abstract class EntityState extends Equatable {
  const EntityState();

  @override
  List<Object?> get props => [];
}

/// No load attempted yet.
class EntityInitial extends EntityState {
  const EntityInitial();
}

/// First page is being fetched (or filter/search changed).
class EntityLoading extends EntityState {
  const EntityLoading();
}

/// Entities available; hasMore indicates whether another page exists.
class EntityLoaded extends EntityState {
  final List<CanonicalEntity> entities;
  final bool hasMore;
  final int total;
  /// True while a subsequent page is being appended (load-more in progress).
  final bool isLoadingMore;

  const EntityLoaded({
    required this.entities,
    required this.hasMore,
    required this.total,
    this.isLoadingMore = false,
  });

  EntityLoaded copyWith({
    List<CanonicalEntity>? entities,
    bool? hasMore,
    int? total,
    bool? isLoadingMore,
  }) =>
      EntityLoaded(
        entities: entities ?? this.entities,
        hasMore: hasMore ?? this.hasMore,
        total: total ?? this.total,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  @override
  List<Object?> get props => [entities, hasMore, total, isLoadingMore];
}

/// API call failed.
class EntityError extends EntityState {
  final String message;

  const EntityError(this.message);

  @override
  List<Object?> get props => [message];
}
