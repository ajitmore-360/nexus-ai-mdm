import 'package:equatable/equatable.dart';
import 'entity.dart';

class GoldenRecord extends Equatable {
  final String id;
  final String entityId;
  final String displayName;
  final EntityType entityType;
  final double trustScore;
  final double completenessScore;
  final double consistencyScore;
  final double accuracyScore;
  final int contributingSourceCount;
  final List<String> contributingSources;
  final int mergedEntityCount;
  final Map<String, EntityAttribute> attributes;
  final DateTime createdAt;
  final DateTime lastVerifiedAt;
  final DateTime updatedAt;
  final String? createdBy;
  final bool isVerified;
  final List<String> tags;

  const GoldenRecord({
    required this.id,
    required this.entityId,
    required this.displayName,
    required this.entityType,
    required this.trustScore,
    required this.completenessScore,
    required this.consistencyScore,
    required this.accuracyScore,
    required this.contributingSourceCount,
    required this.contributingSources,
    required this.mergedEntityCount,
    required this.attributes,
    required this.createdAt,
    required this.lastVerifiedAt,
    required this.updatedAt,
    this.createdBy,
    this.isVerified = false,
    this.tags = const [],
  });

  double get overallQuality =>
      (completenessScore + consistencyScore + accuracyScore) / 3.0;

  factory GoldenRecord.fromJson(Map<String, dynamic> json) {
    return GoldenRecord(
      id: json['id'] as String,
      entityId: json['entity_id'] as String,
      displayName: json['display_name'] as String,
      entityType: EntityType.values.firstWhere(
        (t) => t.name == (json['entity_type'] as String? ?? 'person'),
        orElse: () => EntityType.person,
      ),
      trustScore: (json['trust_score'] as num).toDouble(),
      completenessScore: (json['completeness_score'] as num).toDouble(),
      consistencyScore: (json['consistency_score'] as num).toDouble(),
      accuracyScore: (json['accuracy_score'] as num).toDouble(),
      contributingSourceCount: json['contributing_source_count'] as int,
      contributingSources:
          List<String>.from(json['contributing_sources'] as List? ?? []),
      mergedEntityCount: json['merged_entity_count'] as int? ?? 0,
      attributes: (json['attributes'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          EntityAttribute.fromJson(value as Map<String, dynamic>),
        ),
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      lastVerifiedAt: DateTime.parse(json['last_verified_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdBy: json['created_by'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      tags: List<String>.from(json['tags'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_id': entityId,
        'display_name': displayName,
        'entity_type': entityType.name,
        'trust_score': trustScore,
        'completeness_score': completenessScore,
        'consistency_score': consistencyScore,
        'accuracy_score': accuracyScore,
        'contributing_source_count': contributingSourceCount,
        'contributing_sources': contributingSources,
        'merged_entity_count': mergedEntityCount,
        'attributes':
            attributes.map((k, v) => MapEntry(k, v.toJson())),
        'created_at': createdAt.toIso8601String(),
        'last_verified_at': lastVerifiedAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'created_by': createdBy,
        'is_verified': isVerified,
        'tags': tags,
      };

  @override
  List<Object?> get props => [
        id,
        entityId,
        displayName,
        entityType,
        trustScore,
        updatedAt,
      ];
}
