use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde_json::json;
use std::sync::Arc;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

/// GET /data-profiling/:entity_type — return cached profile results
pub async fn get_profile(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_type): Path<String>,
) -> impl IntoResponse {
    match state.data_profile_service.get_profile(tenant_ctx.tenant_id, &entity_type).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Err(e)   => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /data-profiling/:entity_type/run — trigger a profiling run (admin/steward)
pub async fn run_profile(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_type): Path<String>,
) -> impl IntoResponse {
    match state.data_profile_service.run_profile(tenant_ctx.tenant_id, &entity_type).await {
        Ok(profiles) => (StatusCode::OK, Json(json!({
            "success": true,
            "data": {
                "entity_type":         entity_type,
                "attributes_profiled": profiles.len(),
                "profiles":            profiles,
            }
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e }))).into_response(),
    }
}
