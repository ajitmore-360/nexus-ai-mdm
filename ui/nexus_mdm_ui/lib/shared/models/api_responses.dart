import 'package:dio/dio.dart';
import 'match_candidate.dart';

// ---------------------------------------------------------------------------
// Create Entity Response
// ---------------------------------------------------------------------------

class CreateEntityResponse {
  final String entityId;
  final String? distributionId;
  final List<String> outboxEventIds;

  const CreateEntityResponse({
    required this.entityId,
    this.distributionId,
    this.outboxEventIds = const [],
  });

  factory CreateEntityResponse.fromJson(Map<String, dynamic> json) {
    return CreateEntityResponse(
      entityId: (json['entity_id'] ?? json['id'] ?? '') as String,
      distributionId: json['distribution_id'] as String?,
      outboxEventIds: List<String>.from(
        json['outbox_event_ids'] as List? ?? [],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'entity_id': entityId,
        'distribution_id': distributionId,
        'outbox_event_ids': outboxEventIds,
      };
}

// ---------------------------------------------------------------------------
// Match Response
// ---------------------------------------------------------------------------

class MatchCluster {
  final String clusterId;
  final List<String> entityIds;
  final double confidence;

  const MatchCluster({
    required this.clusterId,
    required this.entityIds,
    required this.confidence,
  });

  factory MatchCluster.fromJson(Map<String, dynamic> json) => MatchCluster(
        clusterId: json['cluster_id'] as String? ?? '',
        entityIds: List<String>.from(json['entity_ids'] as List? ?? []),
        confidence: (json['confidence'] as num? ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'cluster_id': clusterId,
        'entity_ids': entityIds,
        'confidence': confidence,
      };
}

class MatchResponse {
  final String requestId;
  final List<MatchCandidate> matches;
  final List<MatchCluster> clusters;
  final Map<String, dynamic> metadata;

  const MatchResponse({
    required this.requestId,
    required this.matches,
    this.clusters = const [],
    this.metadata = const {},
  });

  factory MatchResponse.fromJson(Map<String, dynamic> json) {
    return MatchResponse(
      requestId: (json['request_id'] ?? json['id'] ?? '') as String,
      matches: (json['matches'] as List<dynamic>? ?? [])
          .map((m) => MatchCandidate.fromJson(m as Map<String, dynamic>))
          .toList(),
      clusters: (json['clusters'] as List<dynamic>? ?? [])
          .map((c) => MatchCluster.fromJson(c as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'matches': matches.map((m) => m.toJson()).toList(),
        'clusters': clusters.map((c) => c.toJson()).toList(),
        'metadata': metadata,
      };
}

// ---------------------------------------------------------------------------
// Copilot Response
// ---------------------------------------------------------------------------

class PrismResponse {
  final bool success;
  final String answer;
  final List<String> sourceDocs;
  final String? error;

  const PrismResponse({
    required this.success,
    required this.answer,
    this.sourceDocs = const [],
    this.error,
  });

  factory PrismResponse.fromJson(Map<String, dynamic> json) {
    return PrismResponse(
      success: json['success'] as bool? ?? true,
      answer: (json['answer'] ?? json['response'] ?? json['content'] ?? '') as String,
      sourceDocs: List<String>.from(json['source_docs'] as List? ?? []),
      error: json['error'] as String?,
    );
  }

  factory PrismResponse.error(String message) => PrismResponse(
        success: false,
        answer: '',
        error: message,
      );

  Map<String, dynamic> toJson() => {
        'success': success,
        'answer': answer,
        'source_docs': sourceDocs,
        'error': error,
      };
}

// ---------------------------------------------------------------------------
// API Exception
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final dynamic details;

  const ApiException({
    this.statusCode,
    required this.message,
    this.details,
  });

  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isServerError => statusCode != null && statusCode! >= 500;
  bool get isNetworkError => statusCode == null;

  factory ApiException.fromDioException(DioException e) {
    final code = e.response?.statusCode;
    final String msg;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        msg = 'Connection timeout. Check your network.';
      case DioExceptionType.receiveTimeout:
        msg = 'Request timed out. Please try again.';
      case DioExceptionType.sendTimeout:
        msg = 'Failed to send request. Please try again.';
      case DioExceptionType.connectionError:
        msg = 'Cannot connect to server. Check your network.';
      case DioExceptionType.cancel:
        msg = 'Request cancelled.';
      case DioExceptionType.badResponse:
        final data = e.response?.data;
        msg = (data is Map
                ? (data['error'] ?? data['message']) as String?
                : null) ??
            'Server error ($code)';
      default:
        msg = e.message ?? 'An unexpected error occurred.';
    }
    return ApiException(statusCode: code, message: msg, details: e.response?.data);
  }

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}

// ---------------------------------------------------------------------------
// ApiResult â€” sealed success/failure wrapper
// ---------------------------------------------------------------------------

sealed class ApiResult<T> {
  const ApiResult();
}

final class Success<T> extends ApiResult<T> {
  final T data;
  const Success(this.data);
}

final class Failure<T> extends ApiResult<T> {
  final ApiException exception;
  const Failure(this.exception);
}
