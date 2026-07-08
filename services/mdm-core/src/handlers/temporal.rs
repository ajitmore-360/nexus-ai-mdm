use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

#[derive(Deserialize)]
pub struct AsOfParams {
    pub as_of: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
pub struct BitemporalParams {
    pub transaction_time: Option<DateTime<Utc>>,
    pub valid_time:       Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
pub struct HistoryParams {
    pub limit:  Option<i64>,
    pub offset: Option<i64>,
}

/// GET /entities/:id/history — version history ordered newest first
pub async fn get_version_history(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id): Path<Uuid>,
    Query(params): Query<HistoryParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(20).min(100);
    let offset = params.offset.unwrap_or(0);

    match state.temporal_service.get_version_history(tenant_ctx.tenant_id, entity_id, limit, offset).await {
        Ok(versions) => (StatusCode::OK, Json(json!({ "success": true, "data": versions }))).into_response(),
        Err(e)       => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// GET /entities/:id/as-of?as_of=<timestamp>
pub async fn get_entity_as_of(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id): Path<Uuid>,
    Query(params): Query<AsOfParams>,
) -> impl IntoResponse {
    let as_of = params.as_of.unwrap_or_else(Utc::now);

    match state.temporal_service.get_as_of(tenant_ctx.tenant_id, entity_id, as_of).await {
        Ok(Some(data)) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Ok(None)       => (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": format!("No version found as of {}", as_of.to_rfc3339()) }))).into_response(),
        Err(e)         => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// GET /entities/:id/bitemporal?transaction_time=<t>&valid_time=<v>
pub async fn get_entity_bitemporal(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id): Path<Uuid>,
    Query(params): Query<BitemporalParams>,
) -> impl IntoResponse {
    let tx_time    = params.transaction_time.unwrap_or_else(Utc::now);
    let valid_time = params.valid_time.unwrap_or_else(Utc::now);

    match state.temporal_service.get_bitemporal(tenant_ctx.tenant_id, entity_id, tx_time, valid_time).await {
        Ok(Some(data)) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Ok(None)       => (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "No bitemporal version found for given times" }))).into_response(),
        Err(e)         => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
