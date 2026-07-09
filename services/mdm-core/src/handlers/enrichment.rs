use axum::{
    extract::{Extension, Json, Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use azile_auth::Claims;

use crate::AppState;
use crate::services::enrichment_service::UpsertEnrichmentConfig;

#[derive(Deserialize)]
pub struct EnrichmentQuery {
    pub entity_id: Option<Uuid>,
}

pub async fn list_providers(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.enrichment_service.list_providers().await {
        Ok(providers) => (StatusCode::OK, Json(json!({"success":true,"data":providers}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn list_configs(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
) -> impl IntoResponse {
    match state.enrichment_service.list_configs(claims.nxs_tenant_id).await {
        Ok(configs) => (StatusCode::OK, Json(json!({"success":true,"data":configs}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn upsert_config(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(provider_code): Path<String>,
    Json(req): Json<UpsertEnrichmentConfig>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.enrichment_service.upsert_config(claims.nxs_tenant_id, &provider_code, req).await {
        Ok(cfg) => (StatusCode::OK, Json(json!({"success":true,"data":cfg}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn delete_config(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(provider_code): Path<String>,
) -> impl IntoResponse {
    if !claims.nxs_role.can_admin() {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.enrichment_service.delete_config(claims.nxs_tenant_id, &provider_code).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn list_requests(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(q): Query<EnrichmentQuery>,
) -> impl IntoResponse {
    match state.enrichment_service.list_requests(claims.nxs_tenant_id, q.entity_id).await {
        Ok(reqs) => (StatusCode::OK, Json(json!({"success":true,"data":reqs}))).into_response(),
        Err(e) => e.into_response(),
    }
}

pub async fn trigger_provider_enrichment(
    State(state): State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path((entity_id, provider_code)): Path<(Uuid, String)>,
) -> impl IntoResponse {
    match state.enrichment_service.trigger_enrichment(claims.nxs_tenant_id, entity_id, &provider_code).await {
        Ok(req) => (StatusCode::CREATED, Json(json!({"success":true,"data":req}))).into_response(),
        Err(e) => e.into_response(),
    }
}
