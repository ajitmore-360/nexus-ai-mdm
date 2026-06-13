import 'package:equatable/equatable.dart';

enum ActivityType {
  entityCreated,
  entityUpdated,
  entityMerged,
  matchFound,
  matchReviewed,
  goldenRecordCreated,
  goldenRecordUpdated,
  dataQualityAlert,
  ruleTriggered,
  userAction,
}

class ActivityItem extends Equatable {
  final String id;
  final ActivityType type;
  final String title;
  final String description;
  final String? entityId;
  final String? entityName;
  final String? userId;
  final String? userName;
  final String sourceSystem;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final bool isRead;

  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.entityId,
    this.entityName,
    this.userId,
    this.userName,
    required this.sourceSystem,
    required this.timestamp,
    this.metadata = const {},
    this.isRead = false,
  });

  String get typeDisplayName {
    switch (type) {
      case ActivityType.entityCreated:
        return 'Entity Created';
      case ActivityType.entityUpdated:
        return 'Entity Updated';
      case ActivityType.entityMerged:
        return 'Entity Merged';
      case ActivityType.matchFound:
        return 'Match Found';
      case ActivityType.matchReviewed:
        return 'Match Reviewed';
      case ActivityType.goldenRecordCreated:
        return 'Golden Record Created';
      case ActivityType.goldenRecordUpdated:
        return 'Golden Record Updated';
      case ActivityType.dataQualityAlert:
        return 'Data Quality Alert';
      case ActivityType.ruleTriggered:
        return 'Rule Triggered';
      case ActivityType.userAction:
        return 'User Action';
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        id: json['id'] as String? ?? '',
        type: ActivityType.values.firstWhere(
          (t) => t.name == (json['type'] as String? ?? 'entityCreated'),
          orElse: () => ActivityType.entityCreated,
        ),
        title:        json['title'] as String? ?? 'System Event',
        description:  json['description'] as String? ?? '',
        entityId:     json['entity_id'] as String?,
        entityName:   json['entity_name'] as String?,
        userId:       json['user_id'] as String?,
        userName:     json['user_name'] as String?,
        sourceSystem: json['source_system'] as String? ?? 'Nexus AI',
        timestamp:    DateTime.tryParse(json['timestamp'] as String? ?? '') ??
                      DateTime.now(),
        metadata:     json['metadata'] as Map<String, dynamic>? ?? const {},
        isRead:       json['is_read'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'entity_id': entityId,
        'entity_name': entityName,
        'user_id': userId,
        'user_name': userName,
        'source_system': sourceSystem,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
        'is_read': isRead,
      };

  ActivityItem copyWith({bool? isRead}) => ActivityItem(
        id: id,
        type: type,
        title: title,
        description: description,
        entityId: entityId,
        entityName: entityName,
        userId: userId,
        userName: userName,
        sourceSystem: sourceSystem,
        timestamp: timestamp,
        metadata: metadata,
        isRead: isRead ?? this.isRead,
      );

  static List<ActivityItem> get demoList => [
        ActivityItem(
          id: 'act-001',
          type: ActivityType.goldenRecordCreated,
          title: 'Golden Record Created',
          description: 'Alexandra Chen elevated to golden record status',
          entityId: 'ent-001',
          entityName: 'Alexandra Chen',
          userId: 'user-001',
          userName: 'AI Engine',
          sourceSystem: 'Nexus AI',
          timestamp:
              DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        ActivityItem(
          id: 'act-002',
          type: ActivityType.matchFound,
          title: 'High Confidence Match Detected',
          description:
              'Michael Rodriguez matches M. Rodriguez Jr. with 93% confidence',
          entityId: 'ent-003',
          entityName: 'Michael Rodriguez',
          userId: 'system',
          userName: 'Matching Engine',
          sourceSystem: 'Nexus AI',
          timestamp:
              DateTime.now().subtract(const Duration(minutes: 12)),
        ),
        ActivityItem(
          id: 'act-003',
          type: ActivityType.entityMerged,
          title: 'Entities Merged',
          description: '2 duplicate records merged into TechCorp Industries LLC',
          entityId: 'ent-002',
          entityName: 'TechCorp Industries LLC',
          userId: 'user-002',
          userName: 'Alex Chen',
          sourceSystem: 'Manual',
          timestamp:
              DateTime.now().subtract(const Duration(minutes: 28)),
        ),
        ActivityItem(
          id: 'act-004',
          type: ActivityType.dataQualityAlert,
          title: 'Data Quality Alert',
          description: '47 new records from Salesforce have missing email fields',
          sourceSystem: 'Salesforce CRM',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        ActivityItem(
          id: 'act-005',
          type: ActivityType.entityCreated,
          title: 'Bulk Import Completed',
          description: '2,341 new entities imported from SAP ERP',
          sourceSystem: 'SAP ERP',
          userId: 'system',
          userName: 'Import Service',
          timestamp:
              DateTime.now().subtract(const Duration(hours: 2)),
        ),
        ActivityItem(
          id: 'act-006',
          type: ActivityType.matchReviewed,
          title: 'Match Review Completed',
          description:
              'Batch of 50 match candidates reviewed — 43 merged, 7 rejected',
          userId: 'user-001',
          userName: 'Alex Chen',
          sourceSystem: 'Manual',
          timestamp:
              DateTime.now().subtract(const Duration(hours: 3)),
        ),
        ActivityItem(
          id: 'act-007',
          type: ActivityType.ruleTriggered,
          title: 'Governance Rule Triggered',
          description:
              'Mandatory field rule applied to 128 Organization entities',
          sourceSystem: 'Governance Engine',
          timestamp:
              DateTime.now().subtract(const Duration(hours: 4)),
        ),
      ];

  @override
  List<Object?> get props => [id, type, title, timestamp, isRead];
}
