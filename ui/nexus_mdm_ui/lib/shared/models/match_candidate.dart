import 'package:equatable/equatable.dart';

enum MatchPriority {
  critical,
  high,
  normal,
  low,
}

enum MatchDecision {
  pending,
  merged,
  notDuplicate,
  deferred,
}

class FieldMatch extends Equatable {
  final String fieldName;
  final String displayName;
  final dynamic sourceValue;
  final dynamic targetValue;
  final double similarity;
  final String algorithm;

  const FieldMatch({
    required this.fieldName,
    required this.displayName,
    required this.sourceValue,
    required this.targetValue,
    required this.similarity,
    required this.algorithm,
  });

  bool get isExact => similarity >= 0.999;
  bool get isHigh => similarity >= 0.85;
  bool get isMedium => similarity >= 0.65;
  bool get isLow => similarity < 0.65;

  factory FieldMatch.fromJson(Map<String, dynamic> json) => FieldMatch(
        fieldName: json['field_name'] as String,
        displayName: json['display_name'] as String,
        sourceValue: json['source_value'],
        targetValue: json['target_value'],
        similarity: (json['similarity'] as num).toDouble(),
        algorithm: json['algorithm'] as String,
      );

  Map<String, dynamic> toJson() => {
        'field_name': fieldName,
        'display_name': displayName,
        'source_value': sourceValue,
        'target_value': targetValue,
        'similarity': similarity,
        'algorithm': algorithm,
      };

  @override
  List<Object?> get props =>
      [fieldName, sourceValue, targetValue, similarity];
}

class MatchCandidate extends Equatable {
  final String id;
  final String sourceEntityId;
  final String sourceEntityName;
  final String targetEntityId;
  final String targetEntityName;
  final double overallScore;
  final MatchPriority priority;
  final MatchDecision decision;
  final List<FieldMatch> fieldMatches;
  final String matchAlgorithm;
  final double? aiConfidence;
  final String? aiExplanation;
  final String? assignedTo;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final Map<String, dynamic> metadata;

  const MatchCandidate({
    required this.id,
    required this.sourceEntityId,
    required this.sourceEntityName,
    required this.targetEntityId,
    required this.targetEntityName,
    required this.overallScore,
    required this.priority,
    required this.decision,
    required this.fieldMatches,
    required this.matchAlgorithm,
    this.aiConfidence,
    this.aiExplanation,
    this.assignedTo,
    required this.createdAt,
    this.decidedAt,
    this.decidedBy,
    this.metadata = const {},
  });

  bool get isPending => decision == MatchDecision.pending;
  bool get isCritical => priority == MatchPriority.critical;
  bool get hasAiRecommendation => aiConfidence != null;

  String get priorityDisplayName {
    switch (priority) {
      case MatchPriority.critical:
        return 'Critical';
      case MatchPriority.high:
        return 'High';
      case MatchPriority.normal:
        return 'Normal';
      case MatchPriority.low:
        return 'Low';
    }
  }

  String get decisionDisplayName {
    switch (decision) {
      case MatchDecision.pending:
        return 'Pending Review';
      case MatchDecision.merged:
        return 'Merged';
      case MatchDecision.notDuplicate:
        return 'Not a Duplicate';
      case MatchDecision.deferred:
        return 'Deferred';
    }
  }

  int get matchedFieldsCount =>
      fieldMatches.where((f) => f.similarity >= 0.65).length;
  int get totalFieldsCount => fieldMatches.length;

  factory MatchCandidate.fromJson(Map<String, dynamic> json) {
    return MatchCandidate(
      id: json['id'] as String,
      sourceEntityId: json['source_entity_id'] as String,
      sourceEntityName: json['source_entity_name'] as String,
      targetEntityId: json['target_entity_id'] as String,
      targetEntityName: json['target_entity_name'] as String,
      overallScore: (json['overall_score'] as num).toDouble(),
      priority: MatchPriority.values.firstWhere(
        (p) => p.name == (json['priority'] as String? ?? 'normal'),
        orElse: () => MatchPriority.normal,
      ),
      decision: MatchDecision.values.firstWhere(
        (d) => d.name == (json['decision'] as String? ?? 'pending'),
        orElse: () => MatchDecision.pending,
      ),
      fieldMatches: (json['field_matches'] as List<dynamic>? ?? [])
          .map((f) =>
              FieldMatch.fromJson(f as Map<String, dynamic>))
          .toList(),
      matchAlgorithm: json['match_algorithm'] as String,
      aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
      aiExplanation: json['ai_explanation'] as String?,
      assignedTo: json['assigned_to'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      decidedAt: json['decided_at'] != null
          ? DateTime.parse(json['decided_at'] as String)
          : null,
      decidedBy: json['decided_by'] as String?,
      metadata:
          json['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_entity_id': sourceEntityId,
        'source_entity_name': sourceEntityName,
        'target_entity_id': targetEntityId,
        'target_entity_name': targetEntityName,
        'overall_score': overallScore,
        'priority': priority.name,
        'decision': decision.name,
        'field_matches': fieldMatches.map((f) => f.toJson()).toList(),
        'match_algorithm': matchAlgorithm,
        'ai_confidence': aiConfidence,
        'ai_explanation': aiExplanation,
        'assigned_to': assignedTo,
        'created_at': createdAt.toIso8601String(),
        'decided_at': decidedAt?.toIso8601String(),
        'decided_by': decidedBy,
        'metadata': metadata,
      };

  static List<MatchCandidate> get demoList => [
        MatchCandidate(
          id: 'mc-001',
          sourceEntityId: 'ent-003',
          sourceEntityName: 'Michael Rodriguez',
          targetEntityId: 'ent-007',
          targetEntityName: 'M. Rodriguez Jr.',
          overallScore: 0.93,
          priority: MatchPriority.critical,
          decision: MatchDecision.pending,
          fieldMatches: const [
            FieldMatch(
              fieldName: 'name',
              displayName: 'Full Name',
              sourceValue: 'Michael Rodriguez',
              targetValue: 'M. Rodriguez Jr.',
              similarity: 0.87,
              algorithm: 'Jaro-Winkler',
            ),
            FieldMatch(
              fieldName: 'email',
              displayName: 'Email',
              sourceValue: 'mrodriguez@company.com',
              targetValue: 'michael.r@company.com',
              similarity: 0.72,
              algorithm: 'Edit Distance',
            ),
            FieldMatch(
              fieldName: 'phone',
              displayName: 'Phone',
              sourceValue: '+1-555-0147',
              targetValue: '+1 (555) 0147',
              similarity: 0.99,
              algorithm: 'Exact',
            ),
          ],
          matchAlgorithm: 'Ensemble ML v2.1',
          aiConfidence: 0.91,
          aiExplanation:
              'High confidence match based on phone number exact match and name phonetic similarity. Email domain consistency suggests same individual.',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        MatchCandidate(
          id: 'mc-002',
          sourceEntityId: 'ent-010',
          sourceEntityName: 'TechCorp Inc',
          targetEntityId: 'ent-002',
          targetEntityName: 'TechCorp Industries LLC',
          overallScore: 0.87,
          priority: MatchPriority.high,
          decision: MatchDecision.pending,
          fieldMatches: const [
            FieldMatch(
              fieldName: 'name',
              displayName: 'Company Name',
              sourceValue: 'TechCorp Inc',
              targetValue: 'TechCorp Industries LLC',
              similarity: 0.82,
              algorithm: 'Token Sort',
            ),
            FieldMatch(
              fieldName: 'address',
              displayName: 'Address',
              sourceValue: '350 Mission St, SF, CA',
              targetValue: '350 Mission Street, San Francisco, CA 94105',
              similarity: 0.91,
              algorithm: 'Address Normalization',
            ),
          ],
          matchAlgorithm: 'Ensemble ML v2.1',
          aiConfidence: 0.84,
          aiExplanation:
              'Likely same organization. Name variation (Inc vs Industries LLC) is common. Address normalization confirms same physical location.',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        MatchCandidate(
          id: 'mc-003',
          sourceEntityId: 'ent-015',
          sourceEntityName: 'Enterprise Suite 3.0',
          targetEntityId: 'ent-004',
          targetEntityName: 'Enterprise Data Suite v3.0',
          overallScore: 0.78,
          priority: MatchPriority.normal,
          decision: MatchDecision.pending,
          fieldMatches: const [
            FieldMatch(
              fieldName: 'name',
              displayName: 'Product Name',
              sourceValue: 'Enterprise Suite 3.0',
              targetValue: 'Enterprise Data Suite v3.0',
              similarity: 0.78,
              algorithm: 'TF-IDF',
            ),
          ],
          matchAlgorithm: 'Ensemble ML v2.1',
          aiConfidence: 0.71,
          createdAt: DateTime.now().subtract(const Duration(hours: 8)),
        ),
      ];

  @override
  List<Object?> get props => [
        id,
        sourceEntityId,
        targetEntityId,
        overallScore,
        priority,
        decision,
      ];
}
