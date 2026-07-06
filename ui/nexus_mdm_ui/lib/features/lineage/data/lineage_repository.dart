import '../../../core/network/api_client.dart';

// ── Graph models ──────────────────────────────────────────────────────────────

class LineageGraphNode {
  final String id;
  final String label;
  final String entityType;

  const LineageGraphNode({
    required this.id,
    required this.label,
    required this.entityType,
  });

  factory LineageGraphNode.fromJson(Map<String, dynamic> json) =>
      LineageGraphNode(
        id:         json['id']          as String? ?? '',
        label:      json['label']       as String? ?? '',
        entityType: json['entity_type'] as String? ?? 'Unknown',
      );
}

class LineageGraphEdge {
  final String source;
  final String target;
  final String lineageType;
  final int count;

  const LineageGraphEdge({
    required this.source,
    required this.target,
    required this.lineageType,
    required this.count,
  });

  factory LineageGraphEdge.fromJson(Map<String, dynamic> json) =>
      LineageGraphEdge(
        source:      json['source']       as String? ?? '',
        target:      json['target']       as String? ?? '',
        lineageType: json['lineage_type'] as String? ?? '',
        count:       (json['count'] as num?)?.toInt() ?? 1,
      );
}

class LineageGraphData {
  final List<LineageGraphNode> nodes;
  final List<LineageGraphEdge> edges;

  const LineageGraphData({required this.nodes, required this.edges});

  bool get isEmpty => nodes.isEmpty && edges.isEmpty;

  static const empty = LineageGraphData(nodes: [], edges: []);
}

// ── Lineage record ─────────────────────────────────────────────────────────────

class LineageRecord {
  final String lineageId;
  final String sourceEntityId;
  final String targetEntityId;
  final String lineageType;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const LineageRecord({
    required this.lineageId,
    required this.sourceEntityId,
    required this.targetEntityId,
    required this.lineageType,
    required this.metadata,
    required this.createdAt,
  });

  factory LineageRecord.fromJson(Map<String, dynamic> json) {
    return LineageRecord(
      lineageId:      json['lineage_id']        as String? ?? '',
      sourceEntityId: json['source_entity_id']  as String? ?? '',
      targetEntityId: json['target_entity_id']  as String? ?? '',
      lineageType:    json['lineage_type']       as String? ?? '',
      metadata:       (json['metadata']          as Map<String, dynamic>?) ?? {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class LineageRepository {
  final ApiClient _client;

  LineageRepository(this._client);

  /// Fetch all lineage edges for the given entity (as source or target).
  Future<List<LineageRecord>> getEntityLineage(String entityId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/v1/entities/$entityId/lineage',
    );

    final data = response.data!;
    final success = data['success'] as bool? ?? false;
    if (!success) {
      throw Exception(data['error'] as String? ?? 'Failed to load lineage');
    }

    final rawItems = (data['data'] as List<dynamic>?) ?? [];
    return rawItems
        .map((e) => LineageRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches the deduplicated entity lineage graph (nodes + edges) for DAG rendering.
  Future<LineageGraphData> getLineageGraph() async {
    try {
      final response = await _client.get<Map<String, dynamic>>('/v1/lineage/graph');
      final data = response.data;
      if (data == null) return LineageGraphData.empty;
      final body = data['data'] as Map<String, dynamic>? ?? data;
      final nodes = (body['nodes'] as List<dynamic>? ?? [])
          .map((e) => LineageGraphNode.fromJson(e as Map<String, dynamic>))
          .toList();
      final edges = (body['edges'] as List<dynamic>? ?? [])
          .map((e) => LineageGraphEdge.fromJson(e as Map<String, dynamic>))
          .toList();
      return LineageGraphData(nodes: nodes, edges: edges);
    } catch (_) {
      return LineageGraphData.empty;
    }
  }

  /// Record a lineage edge between two entities.
  Future<String> recordLineage({
    required String sourceEntityId,
    required String targetEntityId,
    required String lineageType,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/v1/lineage',
      data: {
        'source_entity_id': sourceEntityId,
        'target_entity_id': targetEntityId,
        'lineage_type':     lineageType,
        if (metadata != null) 'metadata': metadata,
      },
    );

    final data = response.data!;
    final success = data['success'] as bool? ?? false;
    if (!success) {
      throw Exception(data['error'] as String? ?? 'Failed to record lineage');
    }

    return (data['data'] as Map<String, dynamic>?)?['lineage_id'] as String? ?? '';
  }
}
