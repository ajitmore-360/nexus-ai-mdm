import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// RelationshipType
// ---------------------------------------------------------------------------

class RelationshipType {
  final String typeId;
  final String name;
  final String displayName;
  final String fromEntityType;
  final String toEntityType;
  final bool isBidirectional;

  const RelationshipType({
    required this.typeId,
    required this.name,
    required this.displayName,
    required this.fromEntityType,
    required this.toEntityType,
    required this.isBidirectional,
  });

  factory RelationshipType.fromJson(Map<String, dynamic> json) {
    return RelationshipType(
      typeId: json['type_id'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['name'] as String? ?? '',
      fromEntityType: json['from_entity_type'] as String? ?? '',
      toEntityType: json['to_entity_type'] as String? ?? '',
      isBidirectional: json['is_bidirectional'] as bool? ?? false,
    );
  }

  @override
  String toString() => displayName;
}

// ---------------------------------------------------------------------------
// EntityRelationshipRecord
// ---------------------------------------------------------------------------

class EntityRelationshipRecord {
  final String relationshipId;
  final String typeId;
  final String typeName;
  final String typeDisplayName;
  final String fromEntityId;
  final String toEntityId;
  final String fromEntityType;
  final String toEntityType;

  /// True if this entity is the "from" side of the relationship.
  final bool isFromEntity;

  /// Relationship strength in [0.0, 1.0].
  final double strength;

  final DateTime createdAt;

  const EntityRelationshipRecord({
    required this.relationshipId,
    required this.typeId,
    required this.typeName,
    required this.typeDisplayName,
    required this.fromEntityId,
    required this.toEntityId,
    required this.fromEntityType,
    required this.toEntityType,
    required this.isFromEntity,
    required this.strength,
    required this.createdAt,
  });

  factory EntityRelationshipRecord.fromJson(
    Map<String, dynamic> json, {
    required String thisEntityId,
  }) {
    final fromId = json['from_entity_id'] as String? ?? '';
    return EntityRelationshipRecord(
      relationshipId:
          json['relationship_id'] as String? ?? json['id'] as String? ?? '',
      typeId: json['type_id'] as String? ?? '',
      typeName: json['type_name'] as String? ?? '',
      typeDisplayName:
          json['type_display_name'] as String? ?? json['type_name'] as String? ?? '',
      fromEntityId: fromId,
      toEntityId: json['to_entity_id'] as String? ?? '',
      fromEntityType: json['from_entity_type'] as String? ?? '',
      toEntityType: json['to_entity_type'] as String? ?? '',
      isFromEntity: fromId == thisEntityId,
      strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// The entity ID of the "other" side of the relationship (not this entity).
  String otherEntityId(String thisEntityId) =>
      isFromEntity ? toEntityId : fromEntityId;

  /// The entity type of the "other" side.
  String otherEntityType() => isFromEntity ? toEntityType : fromEntityType;
}

// ---------------------------------------------------------------------------
// RelationshipRepository
// ---------------------------------------------------------------------------

class RelationshipRepository {
  final ApiClient _apiClient;

  RelationshipRepository(this._apiClient);

  /// Lists all available relationship type definitions.
  ///
  /// GET /v1/relationship-types
  Future<ApiResult<List<RelationshipType>>> listTypes({
    required String tenantId,
  }) async {
    try {
      final response = await _apiClient.get<dynamic>(
        '/v1/relationship-types',
        queryParameters: {'tenant_id': tenantId},
      );

      final raw = response.data;
      final List<dynamic> items;
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = raw['items'] as List<dynamic>? ??
            raw['data'] as List<dynamic>? ??
            [];
      } else {
        items = [];
      }

      final types = items
          .map((e) =>
              RelationshipType.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(types);
    } catch (e) {
      assert(() {
        debugPrint('[RelationshipRepository] listTypes error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Lists all relationships that include the given entity (as from or to).
  ///
  /// GET /v1/entities/{entityId}/relationships
  Future<ApiResult<List<EntityRelationshipRecord>>> listForEntity({
    required String tenantId,
    required String entityId,
  }) async {
    try {
      final response = await _apiClient.get<dynamic>(
        '/v1/entities/$entityId/relationships',
        queryParameters: {'tenant_id': tenantId},
      );

      final raw = response.data;
      final List<dynamic> items;
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = raw['items'] as List<dynamic>? ??
            raw['data'] as List<dynamic>? ??
            [];
      } else {
        items = [];
      }

      final records = items
          .map((e) => EntityRelationshipRecord.fromJson(
                e as Map<String, dynamic>,
                thisEntityId: entityId,
              ))
          .toList();
      return Success(records);
    } catch (e) {
      assert(() {
        debugPrint('[RelationshipRepository] listForEntity error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Creates a new relationship from [entityId] to [toEntityId].
  ///
  /// POST /v1/entities/{entityId}/relationships
  Future<ApiResult<void>> create({
    required String tenantId,
    required String entityId,
    required String typeId,
    required String toEntityId,
    double strength = 1.0,
  }) async {
    try {
      await _apiClient.post<dynamic>(
        '/v1/entities/$entityId/relationships',
        data: {
          'type_id': typeId,
          'to_entity_id': toEntityId,
          'strength': strength,
          'tenant_id': tenantId,
        },
      );
      return const Success(null);
    } catch (e) {
      assert(() {
        debugPrint('[RelationshipRepository] create error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Deletes a relationship by its ID.
  ///
  /// DELETE /v1/relationships/{relationshipId}
  Future<ApiResult<void>> delete({
    required String tenantId,
    required String relationshipId,
  }) async {
    try {
      await _apiClient.delete<dynamic>(
        '/v1/relationships/$relationshipId',
        queryParameters: {'tenant_id': tenantId},
      );
      return const Success(null);
    } catch (e) {
      assert(() {
        debugPrint('[RelationshipRepository] delete error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
