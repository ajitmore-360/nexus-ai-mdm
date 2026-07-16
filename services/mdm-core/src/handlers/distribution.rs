use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension,
    Json,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::services::distribution_service::CreateJobRequest;
use crate::AppState;

#[derive(Deserialize)]
pub struct ListParams {
    pub page:      Option<i64>,
    pub page_size: Option<i64>,
}

#[derive(Deserialize)]
pub struct CreateJobBody {
    pub name:          String,
    pub target_system: String,
    pub filter_config: Option<serde_json::Value>,
}

// â"€â"€ GET /distribution/jobs â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_distribution_jobs(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);

    match state
        .distribution_service
        .list(tenant_ctx.tenant_id, page, page_size)
        .await
    {
        Ok((items, total)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "items":     items,
                "page":      page,
                "page_size": page_size,
                "total":     total,
            })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(error=%e, "list_distribution_jobs failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "failed to list distribution jobs" })),
            )
                .into_response()
        }
    }
}

// â"€â"€ POST /distribution/jobs â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn create_distribution_job(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Extension(claims):     Extension<azile_auth::Claims>,
    Json(body):            Json<CreateJobBody>,
) -> impl IntoResponse {
    if body.name.trim().is_empty() || body.target_system.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "name and target_system are required" })),
        )
            .into_response();
    }

    let created_by = Uuid::parse_str(&claims.sub).ok();

    let req = CreateJobRequest {
        name:          body.name.trim().to_owned(),
        target_system: body.target_system.trim().to_owned(),
        filter_config: body.filter_config,
    };

    match state
        .distribution_service
        .create(tenant_ctx.tenant_id, req, created_by)
        .await
    {
        Ok(job) => (
            StatusCode::CREATED,
            Json(serde_json::json!({ "success": true, "data": job })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(error=%e, "create_distribution_job failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "failed to create distribution job" })),
            )
                .into_response()
        }
    }
}

// â"€â"€ GET /distribution/jobs/:id â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_distribution_job(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(job_id_str):      Path<String>,
) -> impl IntoResponse {
    let job_id = match Uuid::parse_str(&job_id_str) {
        Ok(id)  => id,
        Err(_)  => return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "invalid job id" })),
        ).into_response(),
    };

    match state.distribution_service.get(tenant_ctx.tenant_id, job_id).await {
        Ok(Some(job)) => (StatusCode::OK, Json(job)).into_response(),
        Ok(None)      => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "job not found" })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(error=%e, "get_distribution_job failed");
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "success": false }))).into_response()
        }
    }
}

// â"€â"€ POST /distribution/jobs/:id/queue — move draft â†’ queued â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn queue_distribution_job(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(job_id_str):      Path<String>,
) -> impl IntoResponse {
    let job_id = match Uuid::parse_str(&job_id_str) {
        Ok(id)  => id,
        Err(_)  => return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "invalid job id" })),
        ).into_response(),
    };

    match state.distribution_service.queue(tenant_ctx.tenant_id, job_id).await {
        Ok(true)  => (StatusCode::OK,       Json(serde_json::json!({ "success": true, "status": "queued" }))).into_response(),
        Ok(false) => (StatusCode::CONFLICT, Json(serde_json::json!({ "success": false, "error": "job not in draft state or not found" }))).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "queue_distribution_job failed");
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "success": false }))).into_response()
        }
    }
}

// â"€â"€ DELETE /distribution/jobs/:id — cancel a queued/draft job â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn cancel_distribution_job(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(job_id_str):      Path<String>,
) -> impl IntoResponse {
    let job_id = match Uuid::parse_str(&job_id_str) {
        Ok(id)  => id,
        Err(_)  => return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "invalid job id" })),
        ).into_response(),
    };

    match state.distribution_service.cancel(tenant_ctx.tenant_id, job_id).await {
        Ok(true)  => (StatusCode::OK,       Json(serde_json::json!({ "success": true, "status": "cancelled" }))).into_response(),
        Ok(false) => (StatusCode::CONFLICT, Json(serde_json::json!({ "success": false, "error": "job cannot be cancelled in its current state" }))).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "cancel_distribution_job failed");
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "success": false }))).into_response()
        }
    }
}
