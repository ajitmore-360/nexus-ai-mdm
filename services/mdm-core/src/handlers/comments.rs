use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
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

fn actor_name(headers: &HeaderMap) -> String {
    headers
        .get("x-user-name")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("Unknown User")
        .to_string()
}

fn is_admin(headers: &HeaderMap) -> bool {
    headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .map(|r| r == "Admin" || r == "BusinessAdmin")
        .unwrap_or(false)
}

// ── GET /entities/:id/comments ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct CommentPagination {
    pub limit:  Option<i64>,
    pub offset: Option<i64>,
}

pub async fn list_entity_comments(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Query(pagination):     Query<CommentPagination>,
) -> impl IntoResponse {
    let limit  = pagination.limit.unwrap_or(50).clamp(1, 200);
    let offset = pagination.offset.unwrap_or(0).max(0);

    match state.comment_service.list_comments(tenant_ctx.tenant_id, entity_id, limit, offset).await {
        Ok(comments) => (StatusCode::OK, Json(json!({ "success": true, "data": comments }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── POST /entities/:id/comments ──────────────────────────────────────────────

#[derive(Deserialize)]
pub struct AddCommentBody {
    pub content: String,
}

pub async fn add_entity_comment(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<AddCommentBody>,
) -> impl IntoResponse {
    let content = body.content.trim().to_string();
    if content.is_empty() {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "Comment content cannot be empty" })))
            .into_response();
    }
    if content.len() > 5000 {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "Comment exceeds maximum length of 5000 characters" })))
            .into_response();
    }

    let author_id   = actor_id(&headers).unwrap_or(Uuid::nil());
    let author_name = actor_name(&headers);

    match state.comment_service.add_comment(
        tenant_ctx.tenant_id,
        entity_id,
        author_id,
        &author_name,
        &content,
    ).await {
        Ok(id) => (StatusCode::CREATED, Json(json!({
            "success": true,
            "id":      id,
            "message": "Comment added",
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── PATCH /entities/:entity_id/comments/:comment_id ─────────────────────────

#[derive(Deserialize)]
pub struct EditCommentBody {
    pub content: String,
}

pub async fn edit_entity_comment(
    State(state):                              State<Arc<AppState>>,
    Extension(tenant_ctx):                     Extension<TenantContext>,
    headers:                                   HeaderMap,
    Path((_entity_id, comment_id)): Path<(Uuid, Uuid)>,
    Json(body):                                Json<EditCommentBody>,
) -> impl IntoResponse {
    let content = body.content.trim().to_string();
    if content.is_empty() || content.len() > 5000 {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "Invalid comment content" })))
            .into_response();
    }

    let author_id = actor_id(&headers).unwrap_or(Uuid::nil());

    match state.comment_service.edit_comment(
        tenant_ctx.tenant_id, comment_id, author_id, &content,
    ).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true, "message": "Comment updated" }))).into_response(),
        Ok(false) => (StatusCode::FORBIDDEN, Json(json!({ "success": false, "error": "Comment not found or you are not the author" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── DELETE /entities/:entity_id/comments/:comment_id ────────────────────────

pub async fn delete_entity_comment(
    State(state):                              State<Arc<AppState>>,
    Extension(tenant_ctx):                     Extension<TenantContext>,
    headers:                                   HeaderMap,
    Path((_entity_id, comment_id)): Path<(Uuid, Uuid)>,
) -> impl IntoResponse {
    let author_id = actor_id(&headers).unwrap_or(Uuid::nil());
    let admin     = is_admin(&headers);

    match state.comment_service.delete_comment(
        tenant_ctx.tenant_id, comment_id, author_id, admin,
    ).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true, "message": "Comment deleted" }))).into_response(),
        Ok(false) => (StatusCode::FORBIDDEN, Json(json!({ "success": false, "error": "Comment not found or insufficient permissions" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
