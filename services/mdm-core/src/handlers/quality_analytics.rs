use std::sync::Arc;

use axum::{
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

fn is_admin(headers: &HeaderMap) -> bool {
    headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .map(|r| r == "Admin" || r == "BusinessAdmin")
        .unwrap_or(false)
}

// ── GET /analytics/quality-trends ────────────────────────────────────────────

#[derive(Deserialize)]
pub struct TrendParams {
    pub entity_type: Option<String>,
    pub dimension:   Option<String>,
    pub days:        Option<i32>,
}

pub async fn get_quality_trends(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<TrendParams>,
) -> impl IntoResponse {
    let days = params.days.unwrap_or(30).clamp(1, 365);

    match state.quality_analytics_service.get_quality_trends(
        tenant_ctx.tenant_id,
        params.entity_type.as_deref(),
        params.dimension.as_deref(),
        days,
    ).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data, "days": days }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /analytics/quality-dimensions ────────────────────────────────────────

#[derive(Deserialize)]
pub struct DimensionParams {
    pub entity_type: Option<String>,
}

pub async fn get_dimension_breakdown(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<DimensionParams>,
) -> impl IntoResponse {
    match state.quality_analytics_service.get_dimension_breakdown(
        tenant_ctx.tenant_id,
        params.entity_type.as_deref(),
    ).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /analytics/source-quality ────────────────────────────────────────────

pub async fn get_source_quality_ranking(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state.quality_analytics_service.get_source_quality_ranking(tenant_ctx.tenant_id).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── POST /analytics/quality-snapshot ─────────────────────────────────────────

pub async fn trigger_quality_snapshot(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
) -> impl IntoResponse {
    if !is_admin(&headers) {
        return (StatusCode::FORBIDDEN,
            Json(json!({ "success": false, "error": "Only Admins can trigger manual snapshots" })))
            .into_response();
    }

    match state.quality_analytics_service.take_daily_snapshot(tenant_ctx.tenant_id).await {
        Ok(count) => (StatusCode::OK, Json(json!({
            "success":            true,
            "snapshots_created":  count,
            "message":            format!("Quality snapshot complete — {} dimension scores recorded", count),
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
