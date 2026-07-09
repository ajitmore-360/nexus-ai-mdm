use axum::{
    extract::{Extension, Json, Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use nexus_auth::Claims;

use crate::AppState;
use crate::services::workflow_service::UpsertWorkflow;

pub async fn list_step_types(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.workflow_service.list_step_types().await {
        Ok(types) => (StatusCode::OK, Json(json!({"success":true,"data":types}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn list_workflows(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
) -> impl IntoResponse {
    match state.workflow_service.list_definitions(claims.nxs_tenant_id).await {
        Ok(defs) => (StatusCode::OK, Json(json!({"success":true,"data":defs}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn get_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
) -> impl IntoResponse {
    match state.workflow_service.get_definition(claims.nxs_tenant_id, workflow_id).await {
        Ok(def) => (StatusCode::OK, Json(json!({"success":true,"data":def}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn create_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<UpsertWorkflow>,
) -> impl IntoResponse {
    let actor = claims.user_id().unwrap_or(Uuid::nil());
    match state.workflow_service.create_definition(claims.nxs_tenant_id, actor, req).await {
        Ok(def) => (StatusCode::CREATED, Json(json!({"success":true,"data":def}))).into_response(),
        Err(StatusCode::CONFLICT) => (StatusCode::CONFLICT, Json(json!({"success":false,"error":"Workflow name already exists"}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn update_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
    Json(req): Json<UpsertWorkflow>,
) -> impl IntoResponse {
    match state.workflow_service.update_definition(claims.nxs_tenant_id, workflow_id, req).await {
        Ok(def) => (StatusCode::OK, Json(json!({"success":true,"data":def}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn delete_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.workflow_service.delete_definition(claims.nxs_tenant_id, workflow_id).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn toggle_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
) -> impl IntoResponse {
    match state.workflow_service.toggle_definition(claims.nxs_tenant_id, workflow_id).await {
        Ok(is_active) => (StatusCode::OK, Json(json!({"success":true,"data":{"is_active":is_active}}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn list_workflow_runs(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
) -> impl IntoResponse {
    match state.workflow_service.list_runs(claims.nxs_tenant_id, workflow_id).await {
        Ok(runs) => (StatusCode::OK, Json(json!({"success":true,"data":runs}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn trigger_workflow(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(workflow_id): Path<Uuid>,
    body: Option<Json<serde_json::Value>>,
) -> impl IntoResponse {
    let payload = body.map(|b| b.0).unwrap_or(serde_json::json!({}));
    match state.workflow_service.trigger_run(claims.nxs_tenant_id, workflow_id, payload).await {
        Ok(run) => (StatusCode::CREATED, Json(json!({"success":true,"data":run}))).into_response(),
        Err(e) => e.into_response(),
    }
}
