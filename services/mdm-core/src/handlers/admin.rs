use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Extension,
    Json,
};
use serde_json::json;
use uuid::Uuid;

use nexus_redis::queue::{Task, task_types};

use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── POST /admin/embed-migration ──────────────────────────────────────────────
//
// Enqueues `entity.embed` tasks for every entity in the caller's tenant that
// does not yet have a row in `ai.entity_embeddings`. Safe to call repeatedly —
// each entity is only queued once per invocation; the AI service is idempotent.

pub async fn embed_migration(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;

    let Some(queue) = &state.task_queue else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({
                "success": false,
                "error":   "Task queue not configured — set REDIS_URL to enable embedding migration",
            })),
        ).into_response();
    };

    // Find all entities that have no embedding in any model.
    let entity_ids: Vec<Uuid> = match sqlx::query_scalar::<_, Uuid>(
        "SELECT e.entity_id
         FROM core_mdm.entities e
         WHERE e.tenant_id = $1
           AND e.is_deleted IS NOT TRUE
           AND NOT EXISTS (
               SELECT 1 FROM ai.entity_embeddings ee
               WHERE ee.entity_id = e.entity_id
                 AND ee.tenant_id = e.tenant_id
           )
         ORDER BY e.created_at",
    )
    .bind(tenant_id)
    .fetch_all(&state.db)
    .await
    {
        Ok(ids)  => ids,
        Err(err) => {
            tracing::error!(error=%err, %tenant_id, "embed migration: DB query failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": err.to_string() })),
            ).into_response();
        }
    };

    if entity_ids.is_empty() {
        return (
            StatusCode::OK,
            Json(json!({ "success": true, "queued": 0, "message": "All entities already have embeddings" })),
        ).into_response();
    }

    let total = entity_ids.len();
    let mut queued = 0usize;
    let mut failed = 0usize;

    for entity_id in entity_ids {
        let task = Task::new(
            task_types::ENTITY_EMBED,
            tenant_id.to_string(),
            json!({ "entity_id": entity_id, "tenant_id": tenant_id }),
        );
        match queue.enqueue(task_types::ENTITY_EMBED, &task).await {
            Ok(_) => queued += 1,
            Err(e) => {
                tracing::warn!(error=%e, %entity_id, "embed migration: enqueue failed");
                failed += 1;
            }
        }
    }

    tracing::info!(%tenant_id, queued, failed, total, "embed migration enqueue complete");

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "success": true,
            "queued":  queued,
            "failed":  failed,
            "total":   total,
            "message": format!("{queued}/{total} entities queued for embedding"),
        })),
    ).into_response()
}
