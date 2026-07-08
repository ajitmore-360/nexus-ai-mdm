use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::services::task_service::{CreateTaskInput, UpdateTaskInput};
use crate::AppState;

#[derive(Deserialize)]
pub struct TaskListParams {
    pub assignee_id: Option<Uuid>,
    pub status:      Option<String>,
    pub entity_id:   Option<Uuid>,
    pub limit:       Option<i64>,
    pub offset:      Option<i64>,
}

/// GET /tasks
pub async fn list_tasks(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params): Query<TaskListParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(20).min(100);
    let offset = params.offset.unwrap_or(0);

    match state.task_service.list_tasks(
        tenant_ctx.tenant_id,
        params.assignee_id,
        params.status.as_deref(),
        params.entity_id,
        limit,
        offset,
    ).await {
        Ok(tasks) => (StatusCode::OK, Json(json!({ "success": true, "data": tasks }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /tasks
pub async fn create_task(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers: HeaderMap,
    Json(body): Json<CreateTaskInput>,
) -> impl IntoResponse {
    let actor_id = headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<Uuid>().ok())
        .unwrap_or_else(Uuid::nil);

    match state.task_service.create_task(tenant_ctx.tenant_id, actor_id, body).await {
        Ok(id) => (StatusCode::CREATED, Json(json!({ "success": true, "data": { "id": id } }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// PATCH /tasks/:id
pub async fn update_task(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers: HeaderMap,
    Path(task_id): Path<Uuid>,
    Json(body): Json<UpdateTaskInput>,
) -> impl IntoResponse {
    let actor_id = headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<Uuid>().ok())
        .unwrap_or_else(Uuid::nil);

    match state.task_service.update_task(tenant_ctx.tenant_id, task_id, actor_id, body).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true, "data": { "updated": true } }))).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "Task not found" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /tasks/check-sla — SLA breach detection (internal/admin)
pub async fn check_sla_breaches(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state.task_service.check_sla_breaches(tenant_ctx.tenant_id).await {
        Ok(count) => (StatusCode::OK, Json(json!({ "success": true, "data": { "breaches_marked": count } }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
