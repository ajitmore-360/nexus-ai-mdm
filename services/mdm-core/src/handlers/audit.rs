use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct AuditQueryParams {
    pub page:           Option<i64>,
    pub page_size:      Option<i64>,
    pub aggregate_type: Option<String>,
    pub event_type:     Option<String>,
    pub aggregate_id:   Option<Uuid>,
    pub from:           Option<DateTime<Utc>>,
    pub to:             Option<DateTime<Utc>>,
}

/// GET /audit/events — paginated audit event log for the current tenant.
///
/// Reads from `event_store.outbox_events` which is the authoritative source
/// of all domain events produced by this tenant.
pub async fn list_audit_events(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<AuditQueryParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);
    let offset    = (page - 1) * page_size;

    let from = params.from.unwrap_or_else(|| {
        Utc::now() - chrono::Duration::days(30)
    });
    let to = params.to.unwrap_or_else(|| Utc::now());

    // Build query dynamically using sqlx
    let count_result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM event_store.outbox_events
        WHERE tenant_id       = $1
          AND created_at      BETWEEN $2 AND $3
          AND ($4::TEXT IS NULL OR aggregate_type ILIKE $4)
          AND ($5::TEXT IS NULL OR event_type     ILIKE $5)
          AND ($6::UUID IS NULL OR aggregate_id   = $6)
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(from)
    .bind(to)
    .bind(params.aggregate_type.as_deref())
    .bind(params.event_type.as_deref())
    .bind(params.aggregate_id)
    .fetch_one(&state.db)
    .await;

    let total_count = match count_result {
        Ok(n)  => n,
        Err(e) => {
            tracing::error!(error=%e, "audit count query failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to query audit log" })),
            ).into_response();
        }
    };

    let rows_result = sqlx::query(
        r#"
        SELECT
            event_id,
            tenant_id,
            aggregate_type,
            aggregate_id,
            event_type,
            event_payload,
            topic_name,
            published,
            retry_count,
            created_at
        FROM event_store.outbox_events
        WHERE tenant_id       = $1
          AND created_at      BETWEEN $2 AND $3
          AND ($4::TEXT IS NULL OR aggregate_type ILIKE $4)
          AND ($5::TEXT IS NULL OR event_type     ILIKE $5)
          AND ($6::UUID IS NULL OR aggregate_id   = $6)
        ORDER BY created_at DESC
        LIMIT  $7
        OFFSET $8
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(from)
    .bind(to)
    .bind(params.aggregate_type.as_deref())
    .bind(params.event_type.as_deref())
    .bind(params.aggregate_id)
    .bind(page_size)
    .bind(offset)
    .fetch_all(&state.db)
    .await;

    match rows_result {
        Err(e) => {
            tracing::error!(error=%e, "audit events query failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to query audit log" })),
            ).into_response()
        }
        Ok(rows) => {
            use sqlx::Row;
            let items: Vec<serde_json::Value> = rows.iter().map(|row| {
                let event_id:      Uuid             = row.get("event_id");
                let aggregate_type: String          = row.get("aggregate_type");
                let aggregate_id:  Uuid             = row.get("aggregate_id");
                let event_type:    String           = row.get("event_type");
                let event_payload: serde_json::Value = row.get("event_payload");
                let topic_name:    String           = row.get("topic_name");
                let published:     bool             = row.get("published");
                let created_at: DateTime<Utc>       = row.get("created_at");

                json!({
                    "event_id":       event_id,
                    "aggregate_type": aggregate_type,
                    "aggregate_id":   aggregate_id,
                    "event_type":     event_type,
                    "payload":        event_payload,
                    "topic":          topic_name,
                    "published":      published,
                    "timestamp":      created_at.to_rfc3339(),
                })
            }).collect();

            (
                StatusCode::OK,
                Json(json!({
                    "items":       items,
                    "page":        page,
                    "page_size":   page_size,
                    "total_count": total_count,
                })),
            ).into_response()
        }
    }
}
