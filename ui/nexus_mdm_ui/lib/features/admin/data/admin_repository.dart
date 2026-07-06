import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

class TenantModel {
  final String id;
  final String name;
  final String subdomain;
  final String plan;
  final int maxUsers;
  final int maxEntities;
  final String region;
  final String status;
  final DateTime createdAt;

  const TenantModel({
    required this.id,
    required this.name,
    required this.subdomain,
    required this.plan,
    required this.maxUsers,
    required this.maxEntities,
    required this.region,
    required this.status,
    required this.createdAt,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    return TenantModel(
      id: (json['tenant_id'] ?? json['id']) as String? ?? '',
      name: (json['display_name'] ?? json['name']) as String? ?? '',
      subdomain: (json['tenant_code'] ?? json['subdomain']) as String? ?? '',
      plan: json['plan'] as String? ?? '',
      maxUsers: json['max_users'] as int? ?? 0,
      maxEntities: json['max_entities'] as int? ?? 0,
      region: json['region'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subdomain': subdomain,
        'plan': plan,
        'max_users': maxUsers,
        'max_entities': maxEntities,
        'region': region,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}

class TenantUserModel {
  final String id;
  final String tenantId;
  final String email;
  final String fullName;
  final String role;
  final String status;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  const TenantUserModel({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.lastLoginAt,
    required this.createdAt,
  });

  factory TenantUserModel.fromJson(Map<String, dynamic> json) {
    return TenantUserModel(
      id: (json['user_id'] ?? json['id']) as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: (json['display_name'] ?? json['full_name']) as String? ?? '',
      role: json['role'] as String? ?? '',
      status: json['status'] as String? ?? '',
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'email': email,
        'full_name': fullName,
        'role': role,
        'status': status,
        'last_login_at': lastLoginAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

class AdminRepository {
  final ApiClient _apiClient;
  AdminRepository(this._apiClient);

  Future<ApiResult<List<TenantModel>>> listTenants() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>('/admin/tenants');
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['data'] as List<dynamic>? ?? [])
          .map((e) => TenantModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] listTenants error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<TenantModel>> createTenant({
    required String name,
    required String subdomain,
    required String plan,
    required int maxUsers,
    required int maxEntities,
    required String region,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/tenants',
        data: {
          'name': name,
          'subdomain': subdomain,
          'plan': plan,
          'max_users': maxUsers,
          'max_entities': maxEntities,
          'region': region,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final payload = (data['data'] as Map<String, dynamic>?) ?? data;
      return Success(TenantModel.fromJson(payload));
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] createTenant error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<TenantUserModel>> createAdminUser(
    String tenantId, {
    required String email,
    required String fullName,
    required String tempPassword,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/tenants/$tenantId/admin-user',
        data: {
          'email': email,
          'full_name': fullName,
          'temp_password': tempPassword,
        },
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(TenantUserModel.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] createAdminUser error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<List<TenantUserModel>>> listUsers(String tenantId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/users',
        queryParameters: {'tenant_id': tenantId},
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      final items = (data['data'] as List<dynamic>? ?? [])
          .map((e) => TenantUserModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] listUsers error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  /// Returns the invite token on success. The token must be shared with the
  /// invited user — no email is sent automatically.
  Future<ApiResult<String>> inviteUser({
    required String tenantId,
    required String email,
    required String fullName,
    required String role,
    String? targetTenantId,
    List<String>? entityTypeAssignments,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/admin/users/invite',
        data: {
          'email':        email,
          'display_name': fullName,
          'role':         role,
          if (targetTenantId != null && targetTenantId.isNotEmpty)
            'target_tenant_id': targetTenantId,
          if (entityTypeAssignments != null && entityTypeAssignments.isNotEmpty)
            'entity_type_assignments': entityTypeAssignments,
        },
      );
      final token = ((response.data?['data']) as Map<String, dynamic>?)?['invite_token']
              as String? ??
          '';
      return Success(token);
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] inviteUser error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> updateUserRole(String userId, String role) async {
    try {
      await _apiClient.patch<Map<String, dynamic>>(
        '/admin/users/$userId/role',
        data: {'role': role},
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] updateUserRole error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> updateTenantLicense(
    String tenantId, {
    required String tier,
    String? notes,
  }) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/admin/tenants/$tenantId/license',
        data: {
          'tier': tier,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      return const Success(true);
    } catch (e) {
      assert(() {
        debugPrint('[AdminRepository] updateTenantLicense error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }
}
