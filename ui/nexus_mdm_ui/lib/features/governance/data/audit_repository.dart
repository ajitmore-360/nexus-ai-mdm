import '../../../core/network/api_client.dart';

class AuditEvent {
  final String eventId;
  final String aggregateType;
  final String aggregateId;
  final String eventType;
  final Map<String, dynamic> payload;
  final String topic;
  final bool published;
  final DateTime timestamp;

  const AuditEvent({
    required this.eventId,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventType,
    required this.payload,
    required this.topic,
    required this.published,
    required this.timestamp,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      eventId:       json['event_id']       as String? ?? '',
      aggregateType: json['aggregate_type'] as String? ?? '',
      aggregateId:   json['aggregate_id']   as String? ?? '',
      eventType:     json['event_type']     as String? ?? '',
      payload:       (json['payload']       as Map<String, dynamic>?) ?? {},
      topic:         json['topic']          as String? ?? '',
      published:     json['published']      as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AuditEventsPage {
  final List<AuditEvent> items;
  final int page;
  final int pageSize;
  final int totalCount;

  const AuditEventsPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });
}

class AuditRepository {
  final ApiClient _client;

  AuditRepository(this._client);

  Future<AuditEventsPage> listAuditEvents({
    int page = 1,
    int pageSize = 20,
    String? aggregateType,
    String? eventType,
    String? aggregateId,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, dynamic>{
      'page':      page,
      'page_size': pageSize,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (eventType != null)     'event_type':     eventType,
      if (aggregateId != null)   'aggregate_id':   aggregateId,
      if (from != null)          'from':           from.toIso8601String(),
      if (to != null)            'to':             to.toIso8601String(),
    };

    final response = await _client.get<Map<String, dynamic>>(
      '/v1/audit/events',
      queryParameters: params,
    );

    final data = response.data!;
    final rawItems = (data['items'] as List<dynamic>?) ?? [];

    return AuditEventsPage(
      items:      rawItems.map((e) => AuditEvent.fromJson(e as Map<String, dynamic>)).toList(),
      page:       data['page']        as int? ?? page,
      pageSize:   data['page_size']   as int? ?? pageSize,
      totalCount: data['total_count'] as int? ?? 0,
    );
  }
}
