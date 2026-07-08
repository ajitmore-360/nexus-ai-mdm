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
use crate::services::party_role_service::UpsertRoleInput;

// GET /entities/:id/roles
pub async fn list_party_roles(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state.party_role_service.list_roles(tenant_ctx.tenant_id, entity_id).await {
        Ok(roles) => {
            let count = roles.len();
            Json(json!({ "success": true, "items": roles, "count": count })).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// POST /entities/:id/roles
pub async fn upsert_party_role(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<UpsertRoleInput>,
) -> impl IntoResponse {
    match state.party_role_service.upsert_role(tenant_ctx.tenant_id, entity_id, body).await {
        Ok(role) => (StatusCode::OK,
            Json(json!({ "success": true, "role": role }))).into_response(),
        Err(e)   => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// DELETE /entities/:id/roles/:role_code
pub async fn delete_party_role(
    State(state):                        State<Arc<AppState>>,
    Extension(tenant_ctx):               Extension<TenantContext>,
    Path((entity_id, role_code)):        Path<(Uuid, String)>,
) -> impl IntoResponse {
    match state.party_role_service.delete_role(tenant_ctx.tenant_id, entity_id, &role_code).await {
        Ok(true)  => Json(json!({ "success": true })).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "role not found" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// GET /party-roles/by-role?role_code=Customer&status=Active
#[derive(Deserialize)]
pub struct ByRoleQuery {
    pub role_code: String,
    pub status:    Option<String>,
}

pub async fn entities_by_role(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(q):              Query<ByRoleQuery>,
) -> impl IntoResponse {
    match state.party_role_service.entities_by_role(tenant_ctx.tenant_id, &q.role_code, q.status.as_deref()).await {
        Ok(entities) => {
            let count = entities.len();
            Json(json!({ "success": true, "items": entities, "count": count })).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
