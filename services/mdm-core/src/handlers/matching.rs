use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde_json::json;
use uuid::Uuid;

use contracts::mdm::matching::{MatchRequest, MatchResponse};
use tracing::{error, info, warn};

use crate::handlers::ApiResponse;
use crate::middleware::tenant::TenantContext;
use crate::AppState;

pub async fn execute_match(
    State(state): State<Arc<AppState>>,
    Json(request): Json<MatchRequest>,
) -> impl IntoResponse {
    match state.matching_service.execute_matching(request).await {
        Ok(response) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data: Some(response),
                error: None,
            }),
        ),
        Err(err) => {
            error!(error=?err, "match execution failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<MatchResponse> {
                    success: false,
                    data: None,
                    error: Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /admin/trigger-matching
///
/// Re-enqueues every active entity (lifecycle_status != 'Merged') for
/// ENTITY_MATCH processing.  Useful when the worker was not running during
/// a bulk import, or when matching config has changed and all records need
/// to be re-evaluated.
pub async fn trigger_bulk_matching(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let task_queue = match &state.task_queue {
        Some(q) => q,
        None => return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({ "success": false, "error": "task queue not available" })),
        ).into_response(),
    };

    let entity_ids: Vec<Uuid> = match sqlx::query_scalar(
        "SELECT entity_id FROM core_mdm.entities \
         WHERE tenant_id = $1 AND lifecycle_status <> 'Merged'",
    )
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await
    {
        Ok(ids) => ids,
        Err(e) => {
            error!(error=?e, "trigger_bulk_matching: failed to list entities");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response();
        }
    };

    let total = entity_ids.len();
    let mut queued = 0usize;

    for eid in entity_ids {
        let task = azile_redis::queue::Task::new(
            azile_redis::queue::task_types::ENTITY_MATCH,
            tenant_ctx.tenant_id.to_string(),
            json!({ "entity_id": eid, "tenant_id": tenant_ctx.tenant_id }),
        );
        match task_queue.enqueue(azile_redis::queue::task_types::ENTITY_MATCH, &task).await {
            Ok(_) => queued += 1,
            Err(e) => warn!(entity_id=%eid, error=%e, "trigger_bulk_matching: enqueue failed"),
        }
    }

    info!(total=%total, queued=%queued, tenant=%tenant_ctx.tenant_id, "bulk matching triggered");

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "success": true,
            "message": format!("Queued {queued} of {total} entities for matching. Results will appear in the Match Queue within a few seconds."),
            "queued": queued,
            "total":  total,
        })),
    ).into_response()
}
