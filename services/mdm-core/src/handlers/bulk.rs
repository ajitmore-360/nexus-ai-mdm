use std::sync::Arc;

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

fn actor_id(headers: &HeaderMap) -> Option<Uuid> {
    headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
}

// ── POST /entities/bulk/status ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct BulkStatusBody {
    pub entity_ids: Vec<Uuid>,
    pub status:     String,
}

pub async fn bulk_update_entity_status(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<BulkStatusBody>,
) -> impl IntoResponse {
    if body.entity_ids.is_empty() {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "entity_ids cannot be empty" })))
            .into_response();
    }
    if body.entity_ids.len() > 10_000 {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "Cannot update more than 10,000 entities at once" })))
            .into_response();
    }

    let actor = actor_id(&headers).unwrap_or(Uuid::nil());

    match state.bulk_service.bulk_update_status(
        tenant_ctx.tenant_id, body.entity_ids, &body.status, actor,
    ).await {
        Ok(result) => (StatusCode::OK, Json(json!({
            "success": true,
            "updated":    result.updated,
            "skipped":    result.skipped,
            "failed_ids": result.failed_ids,
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── POST /entities/bulk/export ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct BulkExportBody {
    pub entity_ids:  Option<Vec<Uuid>>,
    pub entity_type: Option<String>,
}

pub async fn bulk_export_entities(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<BulkExportBody>,
) -> Response {
    let entity_ids = match body.entity_ids {
        Some(ids) if !ids.is_empty() => ids,
        _ => {
            // No specific IDs — export by entity_type (up to 10k)
            match state.bulk_service.get_entity_ids_for_type(
                tenant_ctx.tenant_id,
                body.entity_type.as_deref(),
                10_000,
            ).await {
                Ok(ids) => ids,
                Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
            }
        }
    };

    match state.bulk_service.bulk_export_csv(tenant_ctx.tenant_id, entity_ids).await {
        Ok(csv) => axum::response::Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "text/csv; charset=utf-8")
            .header("Content-Disposition", "attachment; filename=\"entities_export.csv\"")
            .body(axum::body::Body::from(csv))
            .unwrap_or_else(|_| (StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "response build error" }))).into_response()),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── POST /entities/bulk/tag ──────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct BulkTagBody {
    pub entity_ids: Vec<Uuid>,
    pub tag:        String,
    pub remove:     Option<bool>,
}

pub async fn bulk_tag_entities(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<BulkTagBody>,
) -> impl IntoResponse {
    if body.entity_ids.is_empty() {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "entity_ids cannot be empty" })))
            .into_response();
    }
    if body.tag.trim().is_empty() {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "tag cannot be empty" })))
            .into_response();
    }

    let remove = body.remove.unwrap_or(false);

    match state.bulk_service.bulk_tag(
        tenant_ctx.tenant_id, body.entity_ids, &body.tag, remove,
    ).await {
        Ok(result) => (StatusCode::OK, Json(json!({
            "success": true,
            "updated":    result.updated,
            "skipped":    result.skipped,
            "failed_ids": result.failed_ids,
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
