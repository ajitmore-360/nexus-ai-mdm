import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class SubmasterTypeModel {
  final String id;
  final String tenantId;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final bool isSystem;

  const SubmasterTypeModel({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    this.description,
    required this.isActive,
    required this.isSystem,
  });

  factory SubmasterTypeModel.fromJson(Map<String, dynamic> json) =>
      SubmasterTypeModel(
        id:          json['id']          as String? ?? '',
        tenantId:    json['tenant_id']   as String? ?? '',
        code:        json['code']        as String? ?? '',
        name:        json['name']        as String? ?? '',
        description: json['description'] as String?,
        isActive:    json['is_active']   as bool?   ?? true,
        isSystem:    json['is_system']   as bool?   ?? false,
      );
}

class SubmasterValueModel {
  final String id;
  final String submasterTypeId;
  final String code;
  final String label;
  final String? description;
  final int sortOrder;
  final bool isActive;

  const SubmasterValueModel({
    required this.id,
    required this.submasterTypeId,
    required this.code,
    required this.label,
    this.description,
    required this.sortOrder,
    required this.isActive,
  });

  factory SubmasterValueModel.fromJson(Map<String, dynamic> json) =>
      SubmasterValueModel(
        id:               json['id']                as String? ?? '',
        submasterTypeId:  json['submaster_type_id'] as String? ?? '',
        code:             json['code']              as String? ?? '',
        label:            json['label']             as String? ?? '',
        description:      json['description']       as String?,
        sortOrder:        json['sort_order']        as int?    ?? 0,
        isActive:         json['is_active']         as bool?   ?? true,
      );
}

// ── Repository ────────────────────────────────────────────────────────────────

class SubmasterRepository {
  final ApiClient _apiClient;
  SubmasterRepository(this._apiClient);

  static Options _tenantOpts(String tenantId) => Options(
        headers: {AppConstants.tenantHeaderKey: tenantId},
      );

  /// List all active reference data types for this tenant.
  Future<ApiResult<List<SubmasterTypeModel>>> listTypes(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/submasters',
        options: _tenantOpts(tenantId),
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['data'] as List<dynamic>? ?? [])
          .map((e) => SubmasterTypeModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] listTypes error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// Create a new reference data type (admin / business_admin only).
  Future<ApiResult<SubmasterTypeModel>> createType({
    required String tenantId,
    required String code,
    required String name,
    String? description,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/submasters',
        options: _tenantOpts(tenantId),
        data: {
          'code': code,
          'name': name,
          if (description != null) 'description': description,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(SubmasterTypeModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] createType error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// Update an existing reference data type.
  Future<ApiResult<SubmasterTypeModel>> updateType({
    required String tenantId,
    required String code,
    String? name,
    String? description,
    bool? isActive,
  }) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '/admin/submasters/$code',
        options: _tenantOpts(tenantId),
        data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (isActive != null) 'is_active': isActive,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(SubmasterTypeModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] updateType error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// List all active values for a reference data type (all roles).
  Future<ApiResult<List<SubmasterValueModel>>> listValues(
    String tenantId,
    String typeCode,
  ) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/submasters/$typeCode/values',
        options: _tenantOpts(tenantId),
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['data'] as List<dynamic>? ?? [])
          .map((e) => SubmasterValueModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] listValues error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// Create a new value under a reference data type (admin / business_admin only).
  Future<ApiResult<SubmasterValueModel>> createValue({
    required String tenantId,
    required String typeCode,
    required String code,
    required String label,
    String? description,
    int sortOrder = 0,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/submasters/$typeCode/values',
        options: _tenantOpts(tenantId),
        data: {
          'code': code,
          'label': label,
          if (description != null) 'description': description,
          'sort_order': sortOrder,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(SubmasterValueModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] createValue error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// Update a value.
  Future<ApiResult<SubmasterValueModel>> updateValue({
    required String tenantId,
    required String typeCode,
    required String valueId,
    String? label,
    String? description,
    int? sortOrder,
    bool? isActive,
  }) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '/admin/submasters/$typeCode/values/$valueId',
        options: _tenantOpts(tenantId),
        data: {
          if (label != null) 'label': label,
          if (description != null) 'description': description,
          if (sortOrder != null) 'sort_order': sortOrder,
          if (isActive != null) 'is_active': isActive,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(SubmasterValueModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] updateValue error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }

  /// Soft-delete (deactivate) a value.
  Future<ApiResult<bool>> deleteValue({
    required String tenantId,
    required String typeCode,
    required String valueId,
  }) async {
    try {
      await _apiClient.delete<Map<String, dynamic>>(
        '/admin/submasters/$typeCode/values/$valueId',
        options: _tenantOpts(tenantId),
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[SubmasterRepository] deleteValue error: $e');
        return true;
      }());
      return Failure(e is DioException
          ? ApiException.fromDioException(e)
          : ApiException(message: e.toString()));
    }
  }
}
