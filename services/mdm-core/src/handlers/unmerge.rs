use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── POST /entities/:id/unmerge ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct UnmergeBody {
    pub reason: Option<String>,
}

pub async fn unmerge_entity(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<UnmergeBody>,
) -> impl IntoResponse {
    // Use nil UUID as a fallback actor when header is missing (AUTH_DISABLED mode)
    let actor_id = Uuid::nil();

    match state.unmerge_service.unmerge_entity(
        tenant_ctx.tenant_id,
        entity_id,
        actor_id,
        body.reason.clone(),
    ).await {
        Ok(restored_ids) => {
            let count = restored_ids.len();
            (StatusCode::OK, Json(json!({
                "success":              true,
                "restored_entity_ids":  restored_ids,
                "message":              format!("Entity successfully split into {} records", count),
            }))).into_response()
        }
        Err(e) => (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": e }))).into_response(),
    }
}

// ── GET /entities/:id/unmerge-history ────────────────────────────────────────

pub async fn get_unmerge_history(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state.unmerge_service.list_unmerge_history(tenant_ctx.tenant_id, entity_id).await {
        Ok(history) => (StatusCode::OK, Json(json!({ "success": true, "data": history }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
