use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::handlers::{entities::extract_request_context, ApiResponse};
use crate::middleware::tenant::TenantContext;
use crate::AppState;

#[derive(Deserialize)]
pub struct ReviewQueueParams {
    pub limit:  Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ReviewDecisionBody {
    pub notes: Option<String>,
}

/// GET /match/review-queue?limit=&offset=
/// Returns all match candidates that require human review, newest first.
pub async fn get_review_queue(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ReviewQueueParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(20).clamp(1, 100);
    let offset = params.offset.unwrap_or(0).max(0);

    match state.review_service.get_queue(tenant_ctx.tenant_id, limit, offset).await {
        Ok(queue) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(serde_json::json!({ "items": queue, "limit": limit, "offset": offset })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "review queue fetch failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /match/:request_id/candidates/:candidate_id/approve
/// Steward approves a match candidate — marks it Matched and emits a feedback event.
pub async fn approve_match(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    headers:                   HeaderMap,
    Path((request_id, candidate_id)): Path<(Uuid, Uuid)>,
    body: Option<Json<ReviewDecisionBody>>,
) -> impl IntoResponse {
    let ctx   = extract_request_context(&tenant_ctx, &headers);
    let notes = body.and_then(|b| b.notes.clone());

    match state.review_service.approve(ctx, request_id, candidate_id, notes).await {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse::<serde_json::Value> {
                success: true,
                data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Matched" })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "match approve failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /match/:request_id/candidates/:candidate_id/reject
/// Steward rejects a match candidate — marks it Rejected and emits a feedback event.
pub async fn reject_match(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    headers:                   HeaderMap,
    Path((request_id, candidate_id)): Path<(Uuid, Uuid)>,
    body: Option<Json<ReviewDecisionBody>>,
) -> impl IntoResponse {
    let ctx   = extract_request_context(&tenant_ctx, &headers);
    let notes = body.and_then(|b| b.notes.clone());

    match state.review_service.reject(ctx, request_id, candidate_id, notes).await {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse::<serde_json::Value> {
                success: true,
                data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Rejected" })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "match reject failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}
