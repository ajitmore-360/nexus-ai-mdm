import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

class EntityTypeModel {
  final String id;
  final String tenantId;
  final String name;
  final String code;
  final String description;
  final String icon;
  final String color;
  final String seqPrefix;
  final String seqFormat;
  final int seqCurrent;
  final bool isActive;

  const EntityTypeModel({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.code,
    required this.description,
    required this.icon,
    required this.color,
    required this.seqPrefix,
    required this.seqFormat,
    required this.seqCurrent,
    required this.isActive,
  });

  factory EntityTypeModel.fromJson(Map<String, dynamic> json) {
    return EntityTypeModel(
      id: json['id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      color: json['color'] as String? ?? '',
      seqPrefix: json['seq_prefix'] as String? ?? '',
      seqFormat: json['seq_format'] as String? ?? '',
      seqCurrent: json['seq_current'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'code': code,
        'description': description,
        'icon': icon,
        'color': color,
        'seq_prefix': seqPrefix,
        'seq_format': seqFormat,
        'seq_current': seqCurrent,
        'is_active': isActive,
      };
}

class AttributeSchemaModel {
  final String id;
  final String tenantId;
  final String entityTypeCode;
  final String attributeKey;
  final String displayName;
  final String dataType;
  final bool isRequired;
  final bool isSystem;
  final bool isPii;
  final int displayOrder;
  final List<String> enumValues;

  const AttributeSchemaModel({
    required this.id,
    required this.tenantId,
    required this.entityTypeCode,
    required this.attributeKey,
    required this.displayName,
    required this.dataType,
    required this.isRequired,
    required this.isSystem,
    required this.isPii,
    required this.displayOrder,
    required this.enumValues,
  });

  factory AttributeSchemaModel.fromJson(Map<String, dynamic> json) {
    return AttributeSchemaModel(
      id: json['id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      entityTypeCode: json['entity_type_code'] as String? ?? '',
      attributeKey: json['attribute_key'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      dataType: json['data_type'] as String? ?? '',
      isRequired: json['is_required'] as bool? ?? false,
      isSystem: json['is_system'] as bool? ?? false,
      isPii: json['is_pii'] as bool? ?? false,
      displayOrder: json['display_order'] as int? ?? 0,
      enumValues: (json['enum_values'] as List<dynamic>? ?? [])
          .map((e) => e as String? ?? '')
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'entity_type_code': entityTypeCode,
        'attribute_key': attributeKey,
        'display_name': displayName,
        'data_type': dataType,
        'is_required': isRequired,
        'is_system': isSystem,
        'is_pii': isPii,
        'display_order': displayOrder,
        'enum_values': enumValues,
      };
}

class EntityTypeRepository {
  final ApiClient _apiClient;
  EntityTypeRepository(this._apiClient);

  Future<ApiResult<List<EntityTypeModel>>> listEntityTypes(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/entity-types',
        queryParameters: {'tenant_id': tenantId},
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['items'] as List<dynamic>? ?? [])
          .map((e) => EntityTypeModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] listEntityTypes error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<EntityTypeModel>> createEntityType({
    required String tenantId,
    required String name,
    required String code,
    required String description,
    required String icon,
    required String color,
    required String seqPrefix,
    required String seqFormat,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/entity-types',
        data: {
          'tenant_id': tenantId,
          'name': name,
          'code': code,
          'description': description,
          'icon': icon,
          'color': color,
          'seq_prefix': seqPrefix,
          'seq_format': seqFormat,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(EntityTypeModel.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] createEntityType error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<List<AttributeSchemaModel>>> listAttributes(
    String tenantId,
    String entityTypeCode,
  ) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/attributes',
        queryParameters: {
          'tenant_id': tenantId,
          'entity_type_code': entityTypeCode,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['items'] as List<dynamic>? ?? [])
          .map((e) => AttributeSchemaModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] listAttributes error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<AttributeSchemaModel>> createAttribute(
    String entityTypeCode, {
    required String tenantId,
    required String attributeKey,
    required String displayName,
    required String dataType,
    required bool isRequired,
    required bool isPii,
    required int displayOrder,
    List<String> enumValues = const [],
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/attributes',
        data: {
          'entity_type_code': entityTypeCode,
          'tenant_id': tenantId,
          'attribute_key': attributeKey,
          'display_name': displayName,
          'data_type': dataType,
          'is_required': isRequired,
          'is_pii': isPii,
          'display_order': displayOrder,
          'enum_values': enumValues,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(AttributeSchemaModel.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] createAttribute error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> deleteAttribute(
    String entityTypeCode,
    String attrId,
  ) async {
    try {
      await _apiClient.delete<Map<String, dynamic>>('/admin/attributes/$attrId');
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] deleteAttribute error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<String>> nextSequence(
    String tenantId,
    String entityTypeCode,
  ) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/entity-types/$entityTypeCode/next-sequence',
        queryParameters: {'tenant_id': tenantId},
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final value = data['sequence'] as String? ?? data['value'] as String? ?? '';
      return Success(value);
    } catch (e) {
      assert(() {
        debugPrint('[EntityTypeRepository] nextSequence error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
