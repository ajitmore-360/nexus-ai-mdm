import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart' hide ApiException;
import '../../../shared/models/api_responses.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class GovernanceAssignment {
  final String assignmentId;
  final String entityTypeCode;
  final String assignmentType; // 'owner' | 'steward'
  final String identityId;
  final String email;
  final String? displayName;
  final DateTime assignedAt;

  const GovernanceAssignment({
    required this.assignmentId,
    required this.entityTypeCode,
    required this.assignmentType,
    required this.identityId,
    required this.email,
    this.displayName,
    required this.assignedAt,
  });

  factory GovernanceAssignment.fromJson(Map<String, dynamic> json) {
    return GovernanceAssignment(
      assignmentId:    json['assignment_id'] as String,
      entityTypeCode:  json['entity_type_code'] as String,
      assignmentType:  json['assignment_type'] as String,
      identityId:      json['identity_id'] as String,
      email:           json['email'] as String,
      displayName:     json['display_name'] as String?,
      assignedAt:      DateTime.tryParse(json['assigned_at'] as String? ?? '') ?? DateTime(2024),
    );
  }

  String get displayLabel => displayName ?? email;
}

class PendingApproval {
  final String requestId;
  final String entityId;
  final String entityTypeCode;
  final DateTime submittedAt;
  final String? changeSummary;
  final String status;
  final String? submitterName;
  final String submitterEmail;

  const PendingApproval({
    required this.requestId,
    required this.entityId,
    required this.entityTypeCode,
    required this.submittedAt,
    this.changeSummary,
    required this.status,
    this.submitterName,
    required this.submitterEmail,
  });

  factory PendingApproval.fromJson(Map<String, dynamic> json) {
    return PendingApproval(
      requestId:      json['request_id'] as String,
      entityId:       json['entity_id'] as String,
      entityTypeCode: json['entity_type_code'] as String,
      submittedAt:    DateTime.tryParse(json['submitted_at'] as String? ?? '') ?? DateTime(2024),
      changeSummary:  json['change_summary'] as String?,
      status:         json['status'] as String,
      submitterName:  json['submitter_name'] as String?,
      submitterEmail: json['submitter_email'] as String,
    );
  }

  String get submitterDisplay => submitterName ?? submitterEmail;
}

// ── Repository ────────────────────────────────────────────────────────────────

class GovernanceRepository {
  final ApiClient _apiClient;

  GovernanceRepository(this._apiClient);

  Future<ApiResult<List<GovernanceAssignment>>> listAssignments() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/governance/assignments',
      );
      final data = response.data ?? {};
      final raw  = data['data'] as List<dynamic>? ?? [];
      return Success(raw.map((e) => GovernanceAssignment.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] listAssignments error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<List<Map<String, String>>>> myAssignedTypes() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/governance/assignments/my-types',
      );
      final data = response.data ?? {};
      final raw  = data['data'] as List<dynamic>? ?? [];
      return Success(raw.map((e) => Map<String, String>.from(e as Map)).toList());
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] myAssignedTypes error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<String>> createAssignment({
    required String identityId,
    required String entityTypeCode,
    required String assignmentType, // 'owner' | 'steward'
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/governance/assignments',
        data: {
          'identity_id':      identityId,
          'entity_type_code': entityTypeCode,
          'assignment_type':  assignmentType,
        },
      );
      final data = response.data ?? {};
      final inner = data['data'] as Map<String, dynamic>? ?? {};
      return Success(inner['assignment_id'] as String? ?? '');
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] createAssignment error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> deleteAssignment(String assignmentId) async {
    try {
      await _apiClient.delete<Map<String, dynamic>>(
        '/governance/assignments/$assignmentId',
      );
      return const Success(true);
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] deleteAssignment error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<List<PendingApproval>>> listPendingApprovals() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/entities/pending-approvals',
      );
      final data = response.data ?? {};
      final raw  = data['data'] as List<dynamic>? ?? [];
      return Success(raw.map((e) => PendingApproval.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] listPendingApprovals error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> submitForReview(String entityId, {String? changeSummary}) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/entities/$entityId/submit-for-review',
        data: {'change_summary': changeSummary},
      );
      return const Success(true);
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] submitForReview error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> approveEntity(String entityId) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/entities/$entityId/approve',
        data: {},
      );
      return const Success(true);
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] approveEntity error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }

  Future<ApiResult<bool>> rejectEntity(String entityId, String reviewerNotes) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/entities/$entityId/reject',
        data: {'reviewer_notes': reviewerNotes},
      );
      return const Success(true);
    } catch (e) {
      assert(() { debugPrint('[GovernanceRepository] rejectEntity error: $e'); return true; }());
      return Failure(ApiException(message: e.toString()));
    }
  }
}
