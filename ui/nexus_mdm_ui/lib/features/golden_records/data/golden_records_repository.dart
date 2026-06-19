import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/golden_record.dart';
import '../../../shared/models/api_responses.dart';

class GoldenRecordsRepository {
  final ApiClient _apiClient;

  GoldenRecordsRepository(this._apiClient);

  Future<ApiResult<List<GoldenRecord>>> getGoldenRecords({
    String? search,
    String? entityType,
    bool? isVerified,
    int page = AppConstants.defaultPage,
    int pageSize = AppConstants.defaultPageSize,
  }) async {
    try {
      final params = <String, dynamic>{
        'status': 'golden',
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (entityType != null) 'type': entityType,
      };

      final response = await _apiClient.get<Map<String, dynamic>>(
        AppConstants.entitiesPath,
        queryParameters: params,
      );

      final data = response.data;
      if (data == null) {
        return const Failure(ApiException(message: 'Empty response from server'));
      }

      final raw = data['data'] as Map<String, dynamic>? ?? data;
      final list = raw['items'] as List<dynamic>? ??
          raw['data'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];

      final records = list
          .map((e) => _entityToGoldenRecord(
              CanonicalEntity.fromJson(e as Map<String, dynamic>)))
          .toList();

      return Success(records);
    } catch (e) {
      assert(() {
        debugPrint('[GoldenRecordsRepository] getGoldenRecords error: $e');
        return true;
      }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  GoldenRecord _entityToGoldenRecord(CanonicalEntity entity) {
    final q = entity.qualityScore;
    final t = entity.trustScore;
    return GoldenRecord(
      id: entity.goldenRecordId ?? entity.id,
      entityId: entity.id,
      displayName: entity.displayName,
      entityType: entity.type,
      trustScore: t,
      completenessScore: q,
      consistencyScore: ((q + t) / 2).clamp(0.0, 1.0),
      accuracyScore: t,
      contributingSourceCount: entity.sourceSystems.isEmpty
          ? 1
          : entity.sourceSystems.length,
      contributingSources: entity.sourceSystems.isEmpty
          ? [entity.primarySource]
          : entity.sourceSystems,
      mergedEntityCount: entity.mergedFromIds.length,
      attributes: entity.attributes,
      createdAt: entity.createdAt,
      lastVerifiedAt: entity.updatedAt,
      updatedAt: entity.updatedAt,
      isVerified: entity.status == EntityStatus.golden,
      tags: const [],
    );
  }
}
