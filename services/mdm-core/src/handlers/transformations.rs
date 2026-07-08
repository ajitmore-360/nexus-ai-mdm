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
use crate::services::transformation_service::CreateRuleInput;

#[derive(Deserialize)]
pub struct EntityTypeQuery {
    pub entity_type: Option<String>,
}

// GET /transformation-rules?entity_type=Person
pub async fn list_transformation_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(q):              Query<EntityTypeQuery>,
) -> impl IntoResponse {
    match state.transformation_service.list_rules(tenant_ctx.tenant_id, q.entity_type.as_deref()).await {
        Ok(rules) => {
            let count = rules.len();
            Json(json!({ "success": true, "items": rules, "count": count })).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// POST /transformation-rules
pub async fn create_transformation_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<CreateRuleInput>,
) -> impl IntoResponse {
    match state.transformation_service.create_rule(tenant_ctx.tenant_id, body, None).await {
        Ok(rule) => (StatusCode::CREATED,
            Json(json!({ "success": true, "rule": rule }))).into_response(),
        Err(e)   => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// PUT /transformation-rules/:id/toggle
pub async fn toggle_transformation_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(id):              Path<Uuid>,
) -> impl IntoResponse {
    match state.transformation_service.toggle_rule(tenant_ctx.tenant_id, id).await {
        Ok(active) => Json(json!({ "success": true, "is_active": active })).into_response(),
        Err(e)     => (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// DELETE /transformation-rules/:id
pub async fn delete_transformation_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(id):              Path<Uuid>,
) -> impl IntoResponse {
    match state.transformation_service.delete_rule(tenant_ctx.tenant_id, id).await {
        Ok(true)  => Json(json!({ "success": true })).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "not found" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// POST /transformation-rules/preview
#[derive(serde::Deserialize)]
pub struct PreviewBody {
    pub entity_type: String,
    pub attributes:  serde_json::Value,
}

pub async fn preview_transformation(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<PreviewBody>,
) -> impl IntoResponse {
    match state.transformation_service.preview(tenant_ctx.tenant_id, &body.entity_type, &body.attributes).await {
        Ok(changes) => {
            let count = changes.len();
            Json(json!({
                "success": true,
                "changes": changes,
                "changes_count": count,
            })).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
