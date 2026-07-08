use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── GET /entities/:id/xrefs ──────────────────────────────────────────────────

pub async fn list_entity_xrefs(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    match state.xref_service.list_xrefs(tenant_ctx.tenant_id, entity_id).await {
        Ok(xrefs) => (StatusCode::OK, Json(json!({ "success": true, "data": xrefs }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── POST /entities/:id/xrefs ─────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct UpsertXrefBody {
    pub source_system: String,
    pub external_id:   String,
    pub external_type: Option<String>,
    pub metadata:      Option<Value>,
}

pub async fn upsert_entity_xref(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<UpsertXrefBody>,
) -> impl IntoResponse {
    if body.source_system.trim().is_empty() || body.external_id.trim().is_empty() {
        return (StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "source_system and external_id are required" })))
            .into_response();
    }

    let metadata = body.metadata.unwrap_or(json!({}));

    match state.xref_service.upsert_xref(
        tenant_ctx.tenant_id,
        entity_id,
        &body.source_system,
        &body.external_id,
        body.external_type.as_deref(),
        metadata,
    ).await {
        Ok(id) => (StatusCode::OK, Json(json!({
            "success": true,
            "id":      id,
            "message": "Cross-reference saved",
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── DELETE /entities/:entity_id/xrefs/:xref_id ───────────────────────────────

pub async fn delete_entity_xref(
    State(state):                          State<Arc<AppState>>,
    Extension(tenant_ctx):                 Extension<TenantContext>,
    Path((_entity_id, xref_id)): Path<(Uuid, Uuid)>,
) -> impl IntoResponse {
    match state.xref_service.delete_xref(tenant_ctx.tenant_id, xref_id).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true, "message": "Cross-reference deleted" }))).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "Cross-reference not found" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── GET /xrefs/lookup?source_system=SAP&external_id=BP100234 ─────────────────

#[derive(Deserialize)]
pub struct LookupParams {
    pub source_system: String,
    pub external_id:   String,
}

pub async fn lookup_by_xref(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<LookupParams>,
) -> impl IntoResponse {
    match state.xref_service.find_entity_by_xref(
        tenant_ctx.tenant_id,
        &params.source_system,
        &params.external_id,
    ).await {
        Ok(Some(entity_id)) => (StatusCode::OK, Json(json!({
            "success":   true,
            "entity_id": entity_id,
            "source_system": params.source_system,
            "external_id":   params.external_id,
        }))).into_response(),
        Ok(None) => (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "No entity found for this cross-reference" }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
