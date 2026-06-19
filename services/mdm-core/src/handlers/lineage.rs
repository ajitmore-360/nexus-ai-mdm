use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::AppState;
use super::ApiResponse;

// ── Request / Response types ──────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct RecordLineageRequest {
    pub tenant_id:        Uuid,
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

#[derive(Debug, Deserialize)]
pub struct LineageQuery {
    pub tenant_id: Uuid,
}

// ── Handlers ──────────────────────────────────────────────────────────────────

/// POST /lineage — record a lineage event.
/// Called by: merge_service (internally via DB), enrichment-service (via HTTP).
pub async fn record_lineage(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<RecordLineageRequest>,
) -> Response {
    let lineage_id = Uuid::new_v4();

    let result = sqlx::query(
        r#"
        INSERT INTO lineage.entity_lineage
            (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(lineage_id)
    .bind(req.tenant_id)
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

/// GET /entities/:id/lineage?tenant_id=<uuid>
/// Returns all lineage edges where this entity is source or target.
pub async fn get_entity_lineage(
    State(state): State<Arc<AppState>>,
    Path(entity_id): Path<Uuid>,
    Query(q): Query<LineageQuery>,
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
    .bind(q.tenant_id)
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
