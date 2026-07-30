import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

class BlockingRulesModel {
  final String entityTypeCode;
  final List<String> rules;
  final bool isDefault;

  const BlockingRulesModel({
    required this.entityTypeCode,
    required this.rules,
    required this.isDefault,
  });

  factory BlockingRulesModel.fromJson(Map<String, dynamic> json) {
    return BlockingRulesModel(
      entityTypeCode: json['entity_type_code'] as String? ?? '',
      rules: (json['rules'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class BlockingRulesRepository {
  final ApiClient _apiClient;
  BlockingRulesRepository(this._apiClient);

  static Options _tenantOpts(String tenantId) => Options(
        headers: {AppConstants.tenantHeaderKey: tenantId},
      );

  Future<ApiResult<BlockingRulesModel>> getRules(String tenantId, String entityTypeCode) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/admin/entity-types/$entityTypeCode/blocking-rules',
        queryParameters: {'tenant_id': tenantId},
        options: _tenantOpts(tenantId),
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(BlockingRulesModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[BlockingRulesRepository] getRules error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<BlockingRulesModel>> saveRules(
    String tenantId,
    String entityTypeCode,
    List<String> rules,
  ) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/admin/entity-types/$entityTypeCode/blocking-rules',
        options: _tenantOpts(tenantId),
        data: {'rules': rules},
      );
      final data = response.data;
      if (data == null) return const Failure(ApiException(message: 'Empty response'));
      return Success(BlockingRulesModel.fromJson(data['data'] as Map<String, dynamic>));
    } catch (e) {
      assert(() {
        debugPrint('[BlockingRulesRepository] saveRules error: $e');
        return true;
      }());
      return Failure(e is DioException ? ApiException.fromDioException(e) : ApiException(message: e.toString()));
    }
  }
}
