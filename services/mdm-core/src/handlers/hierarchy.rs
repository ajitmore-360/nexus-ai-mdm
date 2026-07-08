use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── GET /entities/hierarchy/roots ────────────────────────────────────────────

#[derive(Deserialize)]
pub struct RootsParams {
    pub entity_type: Option<String>,
}

pub async fn get_hierarchy_roots(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<RootsParams>,
) -> impl IntoResponse {
    match state.hierarchy_service.get_roots(
        tenant_ctx.tenant_id,
        params.entity_type.as_deref(),
    ).await {
        Ok(roots) => (StatusCode::OK, Json(json!({ "success": true, "data": roots }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /entities/:id/children ───────────────────────────────────────────────

pub async fn get_entity_children(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state.hierarchy_service.get_children(tenant_ctx.tenant_id, entity_id).await {
        Ok(children) => (StatusCode::OK, Json(json!({ "success": true, "data": children }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /entities/:id/ancestors ──────────────────────────────────────────────

pub async fn get_entity_ancestors(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state.hierarchy_service.get_ancestors(tenant_ctx.tenant_id, entity_id).await {
        Ok(ancestors) => (StatusCode::OK, Json(json!({ "success": true, "data": ancestors }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /entities/:id/subtree ────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct SubtreeParams {
    pub max_depth: Option<i32>,
}

pub async fn get_entity_subtree(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Query(params):         Query<SubtreeParams>,
) -> impl IntoResponse {
    let max_depth = params.max_depth.unwrap_or(5).clamp(1, 20);

    match state.hierarchy_service.get_subtree(tenant_ctx.tenant_id, entity_id, max_depth).await {
        Ok(nodes) => (StatusCode::OK, Json(json!({ "success": true, "data": nodes }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── PATCH /entities/:id/parent ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct SetParentBody {
    pub parent_id: Option<Uuid>,
}

pub async fn set_entity_parent(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<SetParentBody>,
) -> impl IntoResponse {
    match state.hierarchy_service.set_parent(
        tenant_ctx.tenant_id, entity_id, body.parent_id,
    ).await {
        Ok(()) => (StatusCode::OK, Json(json!({
            "success": true,
            "message": if body.parent_id.is_some() { "Parent set successfully" } else { "Entity removed from hierarchy" },
        }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": e }))).into_response(),
    }
}
