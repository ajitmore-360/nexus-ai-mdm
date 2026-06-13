import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/api_responses.dart';

// ---------------------------------------------------------------------------
// EntityPage — paginated wrapper for entity lists
// ---------------------------------------------------------------------------

class EntityPage {
  final List<CanonicalEntity> items;
  final int page;
  final int pageSize;
  final int totalCount;

  const EntityPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  bool get hasNextPage => page * pageSize < totalCount;
  int get totalPages => (totalCount / pageSize).ceil().clamp(1, 999);

  factory EntityPage.fromJson(Map<String, dynamic> json) {
    return EntityPage(
      items: (json['items'] as List<dynamic>? ??
              json['data'] as List<dynamic>? ??
              [])
          .map((e) => CanonicalEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? AppConstants.defaultPageSize,
      totalCount: json['total_count'] as int? ?? json['total'] as int? ?? 0,
    );
  }

  /// Demo fallback page wrapping [CanonicalEntity.demoList].
  static EntityPage get demo => EntityPage(
        items: CanonicalEntity.demoList,
        page: 1,
        pageSize: AppConstants.defaultPageSize,
        totalCount: CanonicalEntity.demoList.length,
      );
}

// ---------------------------------------------------------------------------
// EntityRepository
// ---------------------------------------------------------------------------

class EntityRepository {
  final ApiClient _apiClient;

  EntityRepository(this._apiClient);

  /// Returns a paginated list of entities. Falls back to demo data on error.
  Future<ApiResult<EntityPage>> getEntities({
    int page = AppConstants.defaultPage,
    int pageSize = AppConstants.defaultPageSize,
    String? search,
    String? type,
    String? status,
    String? sourceSystem,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (type != null) 'type': type,
        if (status != null) 'status': status,
        if (sourceSystem != null) 'source_system': sourceSystem,
      };

      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.entitiesPath,
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response from server'));
      return Success(EntityPage.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[EntityRepository] getEntities error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Returns a single entity by ID. Falls back to first demo entity on error.
  Future<ApiResult<CanonicalEntity>> getEntity(String entityId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '${AppConstants.entitiesPath}/$entityId',
      );

      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(
          statusCode: 404,
          message: 'Entity not found',
        ));
      }
      return Success(CanonicalEntity.fromJson(data));
    } catch (e) {
      assert(() {
        debugPrint('[EntityRepository] getEntity error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Updates an existing entity via PATCH. Returns the entity_id on success.
  Future<ApiResult<String>> updateEntity(
      String entityId, Map<String, dynamic> payload) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '${AppConstants.entitiesPath}/$entityId',
        data: payload,
      );
      final data = response.data ?? {};
      final id = data['entity_id'] as String? ?? entityId;
      return Success(id);
    } catch (e) {
      assert(() {
        debugPrint('[EntityRepository] updateEntity error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  /// Creates a new entity. Returns [CreateEntityResponse] on success.
  Future<ApiResult<CreateEntityResponse>> createEntity(
      Map<String, dynamic> payload) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        AppConstants.entitiesPath,
        data: payload,
      );

      final raw = response.data ?? {};
      // mdm-core wraps the response in { "success": true, "data": {...} }
      final inner = raw['data'] as Map<String, dynamic>? ?? raw;
      if (inner.isEmpty) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }
      return Success(CreateEntityResponse.fromJson(inner));
    } catch (e) {
      assert(() {
        debugPrint('[EntityRepository] createEntity error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
