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
use crate::services::connector_service::CreateConnectorInstance;

pub async fn list_catalog(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.connector_service.list_catalog().await {
        Ok(catalog) => (StatusCode::OK, Json(json!({"success":true,"data":catalog}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn list_instances(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
) -> impl IntoResponse {
    match state.connector_service.list_instances(claims.nxs_tenant_id).await {
        Ok(instances) => (StatusCode::OK, Json(json!({"success":true,"data":instances}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn get_instance(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(instance_id): Path<Uuid>,
) -> impl IntoResponse {
    match state.connector_service.get_instance(claims.nxs_tenant_id, instance_id).await {
        Ok(inst) => (StatusCode::OK, Json(json!({"success":true,"data":inst}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn create_instance(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(req): Json<CreateConnectorInstance>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    let actor = claims.user_id().unwrap_or(Uuid::nil());
    match state.connector_service.create_instance(claims.nxs_tenant_id, actor, req).await {
        Ok(inst) => (StatusCode::CREATED, Json(json!({"success":true,"data":inst}))).into_response(),
        Err(StatusCode::CONFLICT) => (StatusCode::CONFLICT, Json(json!({"success":false,"error":"Instance name already exists"}))).into_response(),
        Err(StatusCode::BAD_REQUEST) => (StatusCode::BAD_REQUEST, Json(json!({"success":false,"error":"Unknown connector code"}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn update_instance(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(instance_id): Path<Uuid>,
    Json(config): Json<serde_json::Value>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.connector_service.update_instance(claims.nxs_tenant_id, instance_id, config).await {
        Ok(inst) => (StatusCode::OK, Json(json!({"success":true,"data":inst}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn delete_instance(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(instance_id): Path<Uuid>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.connector_service.delete_instance(claims.nxs_tenant_id, instance_id).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn test_instance(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(instance_id): Path<Uuid>,
) -> impl IntoResponse {
    match state.connector_service.test_instance(claims.nxs_tenant_id, instance_id).await {
        Ok(result) => (StatusCode::OK, Json(json!({"success":true,"data":result}))).into_response(),
        Err(e) => e.into_response(),
    }
}
