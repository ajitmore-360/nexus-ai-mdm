use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Extension,
    Json,
};
use serde_json::json;
use std::sync::Arc;

use crate::{
    middleware::tenant::TenantContext,
    services::branding_service::UpsertBranding,
    AppState,
};

/// GET /tenant/branding
pub async fn get_branding(
    State(state):      State<Arc<AppState>>,
    Extension(tenant): Extension<TenantContext>,
) -> impl IntoResponse {
    match state.branding_service.get(tenant.tenant_id).await {
        Ok(branding) => (
            StatusCode::OK,
            Json(json!({ "success": true, "data": branding })),
        ),
        Err(e) => {
            tracing::error!(tenant_id = %tenant.tenant_id, error = %e, "get_branding failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "internal_error" })),
            )
        }
    }
}

/// PUT /tenant/branding
pub async fn upsert_branding(
    State(state):      State<Arc<AppState>>,
    Extension(tenant): Extension<TenantContext>,
    Json(body):        Json<UpsertBranding>,
) -> impl IntoResponse {
    match state.branding_service.upsert(tenant.tenant_id, body).await {
        Ok(branding) => (
            StatusCode::OK,
            Json(json!({ "success": true, "data": branding })),
        ),
        Err(e) => {
            tracing::error!(tenant_id = %tenant.tenant_id, error = %e, "upsert_branding failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "internal_error" })),
            )
        }
    }
}
