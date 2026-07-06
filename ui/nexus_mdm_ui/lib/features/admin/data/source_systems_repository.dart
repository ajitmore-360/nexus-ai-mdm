import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

class SourceSystemModel {
  final String id;
  final String tenantId;
  final String name;
  final String code;
  final String connectorType;
  final String description;
  final String icon;
  final double trustWeight;
  final int priority;
  final List<String> entityTypes;
  final String syncMode;
  final bool isActive;
  final bool isConnected;
  final DateTime? lastSyncAt;
  final String lastSyncStatus;

  const SourceSystemModel({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.code,
    required this.connectorType,
    required this.description,
    required this.icon,
    required this.trustWeight,
    required this.priority,
    required this.entityTypes,
    required this.syncMode,
    required this.isActive,
    required this.isConnected,
    this.lastSyncAt,
    required this.lastSyncStatus,
  });

  factory SourceSystemModel.fromJson(Map<String, dynamic> json) {
    return SourceSystemModel(
      id: json['id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      connectorType: json['connector_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      trustWeight: (json['trust_weight'] as num? ?? 0.0).toDouble(),
      priority: json['priority'] as int? ?? 0,
      entityTypes: (json['entity_types'] as List<dynamic>? ?? [])
          .map((e) => e as String? ?? '')
          .toList(),
      syncMode: json['sync_mode'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isConnected: json['is_connected'] as bool? ?? false,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      lastSyncStatus: json['last_sync_status'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'code': code,
        'connector_type': connectorType,
        'description': description,
        'icon': icon,
        'trust_weight': trustWeight,
        'priority': priority,
        'entity_types': entityTypes,
        'sync_mode': syncMode,
        'is_active': isActive,
        'is_connected': isConnected,
        'last_sync_at': lastSyncAt?.toIso8601String(),
        'last_sync_status': lastSyncStatus,
      };
}

class SourceSystemsRepository {
  final ApiClient _apiClient;
  SourceSystemsRepository(this._apiClient);

  Future<ApiResult<List<SourceSystemModel>>> listSourceSystems(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/source-systems',
        queryParameters: {'tenant_id': tenantId},
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      if (data['success'] == false) {
        return Failure(ApiException(message: data['error'] as String? ?? 'Request failed'));
      }
      final items = (data['data'] as List<dynamic>? ?? [])
          .map((e) => SourceSystemModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[SourceSystemsRepository] listSourceSystems error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<SourceSystemModel>> createSourceSystem({
    required String tenantId,
    required String name,
    required String code,
    required String connectorType,
    required String description,
    required String icon,
    required double trustWeight,
    required int priority,
    required List<String> entityTypes,
    required String syncMode,
    Map<String, dynamic> connectionConfig = const {},
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/source-systems',
        data: {
          'tenant_id': tenantId,
          'name': name,
          'code': code,
          'connector_type': connectorType,
          'description': description,
          'icon': icon,
          'trust_weight': trustWeight,
          'priority': priority,
          'entity_types': entityTypes,
          'sync_mode': syncMode,
          'connection_config': connectionConfig,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      if (data['success'] == false) {
        return Failure(ApiException(message: data['error'] as String? ?? 'Request failed'));
      }
      return Success(SourceSystemModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[SourceSystemsRepository] createSourceSystem error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> testConnection(String id) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/admin/source-systems/$id/test',
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[SourceSystemsRepository] testConnection error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> deleteSourceSystem(String id) async {
    try {
      await _apiClient.delete<Map<String, dynamic>>('/admin/source-systems/$id');
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[SourceSystemsRepository] deleteSourceSystem error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
