import 'package:equatable/equatable.dart';

enum EntityType {
  person,
  organization,
  product,
  location,
  asset,
}

enum EntityStatus {
  active,
  golden,
  review,
  merged,
  inactive,
  pending,
}

class EntityAttribute extends Equatable {
  final String name;
  final String displayName;
  final dynamic value;
  final String sourceSystem;
  final String? sourceId;
  final double confidence;
  final bool hasConflict;
  final List<AttributeConflict> conflicts;
  final DateTime updatedAt;

  const EntityAttribute({
    required this.name,
    required this.displayName,
    required this.value,
    required this.sourceSystem,
    this.sourceId,
    required this.confidence,
    this.hasConflict = false,
    this.conflicts = const [],
    required this.updatedAt,
  });

  factory EntityAttribute.fromJson(Map<String, dynamic> json) {
    return EntityAttribute(
      name:         json['name'] as String? ?? '',
      displayName:  json['display_name'] as String? ?? '',
      value:        json['value'],
      sourceSystem: json['source_system'] as String? ?? 'Unknown',
      sourceId:     json['source_id'] as String?,
      confidence:   (json['confidence'] as num?)?.toDouble() ?? 0.0,
      hasConflict:  json['has_conflict'] as bool? ?? false,
      conflicts: (json['conflicts'] as List<dynamic>? ?? [])
          .map((c) => AttributeConflict.fromJson(c as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
                 DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'display_name': displayName,
        'value': value,
        'source_system': sourceSystem,
        'source_id': sourceId,
        'confidence': confidence,
        'has_conflict': hasConflict,
        'conflicts': conflicts.map((c) => c.toJson()).toList(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [name, displayName, value, sourceSystem, confidence, hasConflict];
}

class AttributeConflict extends Equatable {
  final String sourceSystem;
  final dynamic value;
  final double confidence;

  const AttributeConflict({
    required this.sourceSystem,
    required this.value,
    required this.confidence,
  });

  factory AttributeConflict.fromJson(Map<String, dynamic> json) =>
      AttributeConflict(
        sourceSystem: json['source_system'] as String? ?? 'Unknown',
        value:        json['value'],
        confidence:   (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'source_system': sourceSystem,
        'value': value,
        'confidence': confidence,
      };

  @override
  List<Object?> get props => [sourceSystem, value, confidence];
}

class CanonicalEntity extends Equatable {
  final String id;
  final EntityType type;
  final EntityStatus status;
  final String displayName;
  final String? goldenRecordId;
  final double trustScore;
  final double qualityScore;
  final String primarySource;
  final List<String> sourceSystems;
  final Map<String, EntityAttribute> attributes;
  final int duplicateCount;
  final int conflictCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mergedIntoId;
  final List<String> mergedFromIds;
  final Map<String, dynamic> metadata;

  const CanonicalEntity({
    required this.id,
    required this.type,
    required this.status,
    required this.displayName,
    this.goldenRecordId,
    required this.trustScore,
    required this.qualityScore,
    required this.primarySource,
    required this.sourceSystems,
    required this.attributes,
    this.duplicateCount = 0,
    this.conflictCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.mergedIntoId,
    this.mergedFromIds = const [],
    this.metadata = const {},
  });

  bool get isGolden => status == EntityStatus.golden;
  bool get needsReview => status == EntityStatus.review;
  bool get hasDuplicates => duplicateCount > 0;
  bool get hasConflicts => conflictCount > 0;

  String get typeDisplayName {
    switch (type) {
      case EntityType.person:
        return 'Person';
      case EntityType.organization:
        return 'Organization';
      case EntityType.product:
        return 'Product';
      case EntityType.location:
        return 'Location';
      case EntityType.asset:
        return 'Asset';
    }
  }

  String get statusDisplayName {
    switch (status) {
      case EntityStatus.active:
        return 'Active';
      case EntityStatus.golden:
        return 'Golden';
      case EntityStatus.review:
        return 'Review';
      case EntityStatus.merged:
        return 'Merged';
      case EntityStatus.inactive:
        return 'Inactive';
      case EntityStatus.pending:
        return 'Pending';
    }
  }

  static EntityStatus _parseStatus(String? rawStatus, String? goldenRecordId) {
    final normalized = (rawStatus ?? '').toLowerCase().replaceAll('_', '');
    if (normalized == 'golden') return EntityStatus.golden;
    if (goldenRecordId != null && normalized == 'active') return EntityStatus.golden;
    switch (normalized) {
      case 'active':
        return EntityStatus.active;
      case 'inactive':
        return EntityStatus.inactive;
      case 'merged':
        return EntityStatus.merged;
      case 'draft':
      case 'pending':
        return EntityStatus.pending;
      case 'pendingreview':
      case 'underinvestigation':
      case 'review':
        return EntityStatus.review;
      case 'deleted':
      case 'softdeleted':
      case 'archived':
        return EntityStatus.inactive;
      default:
        return EntityStatus.active;
    }
  }

  factory CanonicalEntity.fromJson(Map<String, dynamic> json) {
    return CanonicalEntity(
      id: json['id'] as String? ?? json['entity_id'] as String? ?? '',
      type: EntityType.values.firstWhere(
        (t) => t.name == (json['type'] as String? ?? 'person').toLowerCase(),
        orElse: () => EntityType.person,
      ),
      status: _parseStatus(json['status'] as String?, json['golden_record_id'] as String?),
      displayName:    json['display_name'] as String? ?? 'Unknown Entity',
      goldenRecordId: json['golden_record_id'] as String?,
      trustScore:     (json['trust_score'] as num?)?.toDouble() ?? 0.0,
      qualityScore:   (json['quality_score'] as num?)?.toDouble() ?? 0.0,
      primarySource:  json['primary_source'] as String? ?? 'Unknown',
      sourceSystems: List<String>.from(json['source_systems'] as List? ?? []),
      attributes: (json['attributes'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          EntityAttribute.fromJson(value as Map<String, dynamic>),
        ),
      ),
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
      conflictCount:  (json['conflict_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
                 DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
                 DateTime.now(),
      mergedIntoId:  json['merged_into_id'] as String?,
      mergedFromIds: List<String>.from(json['merged_from_ids'] as List? ?? []),
      metadata:      json['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'status': status.name,
        'display_name': displayName,
        'golden_record_id': goldenRecordId,
        'trust_score': trustScore,
        'quality_score': qualityScore,
        'primary_source': primarySource,
        'source_systems': sourceSystems,
        'attributes': attributes
            .map((key, value) => MapEntry(key, value.toJson())),
        'duplicate_count': duplicateCount,
        'conflict_count': conflictCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'merged_into_id': mergedIntoId,
        'merged_from_ids': mergedFromIds,
        'metadata': metadata,
      };

  CanonicalEntity copyWith({
    String? id,
    EntityType? type,
    EntityStatus? status,
    String? displayName,
    String? goldenRecordId,
    double? trustScore,
    double? qualityScore,
    String? primarySource,
    List<String>? sourceSystems,
    Map<String, EntityAttribute>? attributes,
    int? duplicateCount,
    int? conflictCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mergedIntoId,
    List<String>? mergedFromIds,
    Map<String, dynamic>? metadata,
  }) {
    return CanonicalEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      displayName: displayName ?? this.displayName,
      goldenRecordId: goldenRecordId ?? this.goldenRecordId,
      trustScore: trustScore ?? this.trustScore,
      qualityScore: qualityScore ?? this.qualityScore,
      primarySource: primarySource ?? this.primarySource,
      sourceSystems: sourceSystems ?? this.sourceSystems,
      attributes: attributes ?? this.attributes,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      conflictCount: conflictCount ?? this.conflictCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mergedIntoId: mergedIntoId ?? this.mergedIntoId,
      mergedFromIds: mergedFromIds ?? this.mergedFromIds,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        status,
        displayName,
        trustScore,
        qualityScore,
        updatedAt,
      ];
}
