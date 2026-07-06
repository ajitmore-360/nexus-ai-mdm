use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;
use super::ApiResponse;

// ── Request / Response types ──────────────────────────────────────────────────

/// tenant_id is NOT accepted from the request body — it is taken from the
/// validated TenantContext injected by the auth + tenant middleware stack.
/// Accepting tenant_id from a client-supplied body would allow any
/// authenticated user to record lineage for any tenant (IDOR).
#[derive(Debug, Deserialize)]
pub struct RecordLineageRequest {
    pub source_entity_id: Uuid,
    pub target_entity_id: Uuid,
    pub lineage_type:     String,
    pub metadata:         Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct LineageRecord {
    pub lineage_id:       Uuid,
    pub tenant_id:        Uuid,
    pub source_entity_id: Uuid,
    pub target_entity_id: Uuid,
    pub lineage_type:     String,
    pub metadata:         serde_json::Value,
    pub created_at:       chrono::DateTime<chrono::Utc>,
}

// ── Handlers ──────────────────────────────────────────────────────────────────

/// POST /lineage — record a lineage event.
/// tenant_id comes exclusively from the JWT-validated TenantContext extension.
pub async fn record_lineage(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(req):             Json<RecordLineageRequest>,
) -> Response {
    let tenant_id  = tenant_ctx.tenant_id;
    let lineage_id = Uuid::new_v4();

    let result = sqlx::query(
        r#"
        INSERT INTO lineage.entity_lineage
            (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(lineage_id)
    .bind(tenant_id)
    .bind(req.source_entity_id)
    .bind(req.target_entity_id)
    .bind(&req.lineage_type)
    .bind(req.metadata.clone().unwrap_or(serde_json::Value::Object(Default::default())))
    .execute(&state.db)
    .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(ApiResponse {
                success: true,
                data:    Some(serde_json::json!({ "lineage_id": lineage_id })),
                error:   None,
            }),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some(e.to_string()),
            }),
        )
            .into_response(),
    }
}

/// GET /entities/:id/lineage
/// Returns all lineage edges where this entity is source or target.
/// tenant_id comes from the JWT-validated TenantContext — not a query param.
pub async fn get_entity_lineage(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> Response {
    let result = sqlx::query_as::<_, LineageRow>(
        r#"
        SELECT lineage_id, tenant_id, source_entity_id, target_entity_id,
               lineage_type, metadata, created_at
        FROM lineage.entity_lineage
        WHERE tenant_id = $1
          AND (source_entity_id = $2 OR target_entity_id = $2)
        ORDER BY created_at DESC
        LIMIT 200
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(entity_id)
    .fetch_all(&state.db)
    .await;

    match result {
        Ok(rows) => {
            let records: Vec<LineageRecord> = rows.into_iter().map(|r| r.into()).collect();
            (StatusCode::OK, Json(ApiResponse { success: true, data: Some(records), error: None }))
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<Vec<LineageRecord>> { success: false, data: None, error: Some(e.to_string()) }),
        )
            .into_response(),
    }
}

/// GET /lineage?limit=&lineage_type= — list recent lineage events for this tenant.
pub async fn list_lineage(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListLineageParams>,
) -> Response {
    let limit = params.limit.unwrap_or(20).clamp(1, 100);
    let result = if let Some(ltype) = &params.lineage_type {
        sqlx::query_as::<_, LineageRow>(
            r#"SELECT lineage_id, tenant_id, source_entity_id, target_entity_id,
                      lineage_type, metadata, created_at
               FROM lineage.entity_lineage
               WHERE tenant_id = $1 AND lineage_type = $2
               ORDER BY created_at DESC LIMIT $3"#,
        )
        .bind(tenant_ctx.tenant_id)
        .bind(ltype)
        .bind(limit)
        .fetch_all(&state.db)
        .await
    } else {
        sqlx::query_as::<_, LineageRow>(
            r#"SELECT lineage_id, tenant_id, source_entity_id, target_entity_id,
                      lineage_type, metadata, created_at
               FROM lineage.entity_lineage
               WHERE tenant_id = $1
               ORDER BY created_at DESC LIMIT $2"#,
        )
        .bind(tenant_ctx.tenant_id)
        .bind(limit)
        .fetch_all(&state.db)
        .await
    };

    match result {
        Ok(rows) => {
            let records: Vec<LineageRecord> = rows.into_iter().map(|r| r.into()).collect();
            (StatusCode::OK, Json(ApiResponse { success: true, data: Some(records), error: None }))
                .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<Vec<LineageRecord>> { success: false, data: None, error: Some(e.to_string()) }),
        ).into_response(),
    }
}

/// GET /lineage/stats — aggregate counts for the lineage dashboard.
pub async fn lineage_stats(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> Response {
    let tid = tenant_ctx.tenant_id;

    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM lineage.entity_lineage WHERE tenant_id = $1",
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let type_counts: Vec<(String, i64)> = sqlx::query_as(
        "SELECT lineage_type, COUNT(*)::BIGINT FROM lineage.entity_lineage WHERE tenant_id = $1 GROUP BY lineage_type",
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let by_type: serde_json::Value = type_counts
        .into_iter()
        .map(|(k, v)| (k, serde_json::json!(v)))
        .collect::<serde_json::Map<_, _>>()
        .into();

    (StatusCode::OK, Json(serde_json::json!({
        "total_lineage_events": total,
        "by_type": by_type,
    }))).into_response()
}

#[derive(Debug, Deserialize)]
pub struct ListLineageParams {
    pub limit:        Option<i64>,
    pub lineage_type: Option<String>,
}

// ── GET /lineage/graph ────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct GraphNode {
    pub id:          String,
    pub label:       String,
    pub entity_type: String,
}

#[derive(Debug, Serialize)]
pub struct GraphEdge {
    pub source:       String,
    pub target:       String,
    pub lineage_type: String,
    pub count:        i32,
}

#[derive(Debug, Serialize)]
pub struct LineageGraph {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
}

#[derive(sqlx::FromRow)]
struct EdgeCountRow {
    source_entity_id: Uuid,
    target_entity_id: Uuid,
    lineage_type:     String,
    edge_count:       i32,
}

#[derive(sqlx::FromRow)]
struct NodeNameRow {
    entity_id:    Uuid,
    entity_type:  String,
    display_name: String,
}

/// GET /lineage/graph — returns a deduplicated node/edge graph for DAG rendering.
pub async fn lineage_graph(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> Response {
    let tid = tenant_ctx.tenant_id;

    let edge_rows = match sqlx::query_as::<_, EdgeCountRow>(
        r#"
        SELECT source_entity_id, target_entity_id, lineage_type, COUNT(*)::int AS edge_count
        FROM lineage.entity_lineage
        WHERE tenant_id = $1
        GROUP BY source_entity_id, target_entity_id, lineage_type
        ORDER BY edge_count DESC
        LIMIT 20
        "#,
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    {
        Ok(rows) => rows,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false, data: None, error: Some(e.to_string()),
                }),
            )
            .into_response()
        }
    };

    if edge_rows.is_empty() {
        return (StatusCode::OK, Json(ApiResponse {
            success: true,
            data:    Some(LineageGraph { nodes: vec![], edges: vec![] }),
            error:   None,
        }))
        .into_response();
    }

    // Collect unique entity IDs from the edge list.
    let entity_ids: Vec<Uuid> = {
        let mut seen = std::collections::HashSet::new();
        edge_rows.iter()
            .flat_map(|e| [e.source_entity_id, e.target_entity_id])
            .filter(|id| seen.insert(*id))
            .collect()
    };

    let node_rows = sqlx::query_as::<_, NodeNameRow>(
        r#"
        SELECT DISTINCT ON (e.entity_id)
            e.entity_id,
            e.entity_type,
            COALESCE(
                (
                    SELECT a.attribute_value #>> '{}'
                    FROM core_mdm.entity_attributes a
                    WHERE a.entity_id = e.entity_id
                      AND a.tenant_id = e.tenant_id
                      AND lower(a.attribute_key) IN (
                              'name', 'full_name', 'display_name',
                              'company_name', 'product_name', 'title'
                          )
                    ORDER BY a.confidence DESC NULLS LAST
                    LIMIT 1
                ),
                LEFT(e.entity_id::text, 8)
            ) AS display_name
        FROM core_mdm.entities e
        WHERE e.tenant_id = $1 AND e.entity_id = ANY($2)
        ORDER BY e.entity_id
        "#,
    )
    .bind(tid)
    .bind(&entity_ids[..])
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let node_map: std::collections::HashMap<String, &NodeNameRow> =
        node_rows.iter().map(|r| (r.entity_id.to_string(), r)).collect();

    let nodes: Vec<GraphNode> = entity_ids.iter().map(|id| {
        let id_str = id.to_string();
        let short = id_str[..8].to_string();
        let info = node_map.get(&id_str);
        GraphNode {
            id:          id_str.clone(),
            label:       info.map(|r| r.display_name.clone()).unwrap_or(short),
            entity_type: info.map(|r| r.entity_type.clone()).unwrap_or_else(|| "Unknown".to_string()),
        }
    }).collect();

    let edges: Vec<GraphEdge> = edge_rows.into_iter().map(|e| GraphEdge {
        source:       e.source_entity_id.to_string(),
        target:       e.target_entity_id.to_string(),
        lineage_type: e.lineage_type,
        count:        e.edge_count,
    }).collect();

    (StatusCode::OK, Json(ApiResponse {
        success: true,
        data:    Some(LineageGraph { nodes, edges }),
        error:   None,
    }))
    .into_response()
}

// ── SQLx row type ─────────────────────────────────────────────────────────────

#[derive(sqlx::FromRow)]
struct LineageRow {
    lineage_id:       Uuid,
    tenant_id:        Uuid,
    source_entity_id: Uuid,
    target_entity_id: Uuid,
    lineage_type:     String,
    metadata:         serde_json::Value,
    created_at:       chrono::DateTime<chrono::Utc>,
}

impl From<LineageRow> for LineageRecord {
    fn from(r: LineageRow) -> Self {
        Self {
            lineage_id:       r.lineage_id,
            tenant_id:        r.tenant_id,
            source_entity_id: r.source_entity_id,
            target_entity_id: r.target_entity_id,
            lineage_type:     r.lineage_type,
            metadata:         r.metadata,
            created_at:       r.created_at,
        }
    }
}
