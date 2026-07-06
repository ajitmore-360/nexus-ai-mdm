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
use crate::AppState;

#[derive(Deserialize)]
pub struct ListParams {
    pub page:      Option<i64>,
    pub page_size: Option<i64>,
}

// ── GET /notifications — list for this tenant (newest first) ─────────────────

pub async fn list_notifications(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);

    match state
        .notification_service
        .list(tenant_ctx.tenant_id, page, page_size)
        .await
    {
        Ok((items, total)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "items":      items,
                "page":       page,
                "page_size":  page_size,
                "total":      total,
                "unread":     items.iter().filter(|n| !n["is_read"].as_bool().unwrap_or(false)).count(),
            })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(error=%e, "list_notifications failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "failed to list notifications" })),
            )
                .into_response()
        }
    }
}

// ── GET /notifications/unread-count ──────────────────────────────────────────

pub async fn unread_count(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let count = state
        .notification_service
        .unread_count(tenant_ctx.tenant_id)
        .await
        .unwrap_or(0);

    (
        StatusCode::OK,
        Json(serde_json::json!({ "unread_count": count })),
    )
        .into_response()
}

// ── PATCH /notifications/:id/read — mark a single notification read ───────────

pub async fn mark_notification_read(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(notification_id_str): Path<String>,
) -> impl IntoResponse {
    let notification_id = match Uuid::parse_str(&notification_id_str) {
        Ok(id)  => id,
        Err(_)  => return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "invalid notification id" })),
        ).into_response(),
    };

    match state
        .notification_service
        .mark_read(tenant_ctx.tenant_id, notification_id)
        .await
    {
        Ok(true)  => (StatusCode::OK,       Json(serde_json::json!({ "success": true }))).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND, Json(serde_json::json!({ "success": false, "error": "notification not found" }))).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "mark_read failed");
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "success": false }))).into_response()
        }
    }
}

// ── POST /notifications/read-all — mark every unread notification read ────────

pub async fn mark_all_read(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let count = state
        .notification_service
        .mark_all_read(tenant_ctx.tenant_id)
        .await
        .unwrap_or(0);

    (
        StatusCode::OK,
        Json(serde_json::json!({ "success": true, "marked_count": count })),
    )
        .into_response()
}
