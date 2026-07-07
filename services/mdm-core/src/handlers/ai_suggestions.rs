use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use contracts::mdm::entity::EntityAttribute;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::services::audit_service::AuditEvent;
use crate::AppState;

fn actor_id(headers: &HeaderMap) -> Option<Uuid> {
    headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
}

// ── POST /entities/:entity_id/ai-suggestions/address-parse ───────────────────

#[derive(Deserialize)]
pub struct AddressParseBody {
    pub raw_address_field: String,
}

pub async fn trigger_address_parse(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<AddressParseBody>,
) -> impl IntoResponse {
    // Load entity attributes so we can strip PII and forward only the address field
    let entity = match state.entity_service.get_entity(tenant_ctx.tenant_id, entity_id).await {
        Ok(Some(e)) => e,
        Ok(None)    => return (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "entity not found" }))).into_response(),
        Err(e)      => return (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    };

    let attrs = serde_json::to_value(&entity.attributes).unwrap_or(serde_json::Value::Object(Default::default()));

    match state.ai_suggestion_service.trigger_address_parse(
        tenant_ctx.tenant_id,
        entity_id,
        &entity.entity_type.to_string(),
        &attrs,
        &body.raw_address_field,
    ).await {
        Ok(id) => (StatusCode::ACCEPTED, Json(json!({
            "success": true,
            "suggestion_id": id,
            "message": "Suggestion created — review it in the AI Insights panel before applying.",
        }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": e }))).into_response(),
    }
}

// ── POST /entities/:entity_id/ai-suggestions/anomaly ─────────────────────────

pub async fn trigger_anomaly(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
) -> impl IntoResponse {
    let entity = match state.entity_service.get_entity(tenant_ctx.tenant_id, entity_id).await {
        Ok(Some(e)) => e,
        Ok(None)    => return (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "entity not found" }))).into_response(),
        Err(e)      => return (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    };

    let attrs = serde_json::to_value(&entity.attributes).unwrap_or(serde_json::Value::Object(Default::default()));

    match state.ai_suggestion_service.trigger_anomaly(
        tenant_ctx.tenant_id,
        entity_id,
        &entity.entity_type.to_string(),
        &attrs,
    ).await {
        Ok(id) => (StatusCode::ACCEPTED, Json(json!({
            "success": true,
            "suggestion_id": id,
            "message": "Anomaly analysis queued — review suggestions before accepting.",
        }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": e }))).into_response(),
    }
}

// ── POST /entities/:entity_id/ai-suggestions/enrichment ──────────────────────

#[derive(Deserialize)]
pub struct EnrichmentBody {
    /// List of field names the caller wants the LLM to suggest values for.
    pub missing_fields: Vec<String>,
}

pub async fn trigger_enrichment(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_id):       Path<Uuid>,
    Json(body):            Json<EnrichmentBody>,
) -> impl IntoResponse {
    let entity = match state.entity_service.get_entity(tenant_ctx.tenant_id, entity_id).await {
        Ok(Some(e)) => e,
        Ok(None)    => return (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "entity not found" }))).into_response(),
        Err(e)      => return (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    };

    let attrs = serde_json::to_value(&entity.attributes).unwrap_or(serde_json::Value::Object(Default::default()));

    match state.ai_suggestion_service.trigger_enrichment(
        tenant_ctx.tenant_id,
        entity_id,
        &entity.entity_type.to_string(),
        &attrs,
        body.missing_fields,
    ).await {
        Ok(id) => (StatusCode::ACCEPTED, Json(json!({
            "success": true,
            "suggestion_id": id,
            "message": "Enrichment suggestion created — review before applying.",
        }))).into_response(),
        Err(e) => (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": e }))).into_response(),
    }
}

// ── GET /ai-suggestions ───────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ListSuggestionsParams {
    pub entity_id:       Option<Uuid>,
    pub suggestion_type: Option<String>,
    pub status:          Option<String>,
    pub limit:           Option<i64>,
    pub offset:          Option<i64>,
}

pub async fn list_suggestions(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListSuggestionsParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(50).min(200);
    let offset = params.offset.unwrap_or(0);

    match state.ai_suggestion_service.list_suggestions(
        tenant_ctx.tenant_id,
        params.entity_id,
        params.suggestion_type.as_deref(),
        params.status.as_deref(),
        limit,
        offset,
    ).await {
        Ok(items) => (StatusCode::OK, Json(json!({ "success": true, "data": items }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

// ── PATCH /ai-suggestions/:id/approve ────────────────────────────────────────
// Marks approved AND applies the suggested field values to the entity.

pub async fn approve_suggestion(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(suggestion_id):   Path<Uuid>,
) -> impl IntoResponse {
    let reviewer = actor_id(&headers);

    let approved = match state.ai_suggestion_service.approve(
        tenant_ctx.tenant_id, suggestion_id, reviewer,
    ).await {
        Ok(Some(v)) => v,
        Ok(None)    => return (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "suggestion not found or already reviewed" }))).into_response(),
        Err(e)      => return (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    };

    let (entity_id, suggestion) = approved;

    // Convert suggestion array → Vec<EntityAttribute>
    let new_attrs: Vec<EntityAttribute> = suggestion
        .as_array()
        .map(|arr| arr.iter().filter_map(|s| {
            let field = s["field"].as_str()?.to_string();
            let raw   = s["proposed_value"].as_str().unwrap_or("");
            if raw.is_empty() { return None; }
            Some(EntityAttribute {
                attribute_id: Uuid::new_v4(),
                key:       field,
                value:     serde_json::Value::String(raw.to_string()),
                data_type: "string".to_string(),
                ..Default::default()
            })
        }).collect())
        .unwrap_or_default();

    let applied = new_attrs.len();

    if !new_attrs.is_empty() {
        let mut tx = match state.db.begin().await {
            Ok(t)  => t,
            Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": format!("tx failed: {e}") }))).into_response(),
        };

        if let Err(e) = state.entity_repository.update_entity(
            &mut tx,
            tenant_ctx.tenant_id,
            entity_id,
            None, None, None,
            Some(&new_attrs),
        ).await {
            return (StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": format!("patch failed: {e}") }))).into_response();
        }

        if let Err(e) = tx.commit().await {
            return (StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": format!("commit failed: {e}") }))).into_response();
        }

        let _ = state.ai_suggestion_service.mark_applied(tenant_ctx.tenant_id, suggestion_id).await;

        state.audit_service.log_background(AuditEvent {
            tenant_id:     tenant_ctx.tenant_id,
            event_type:    "entity.ai_suggestion_applied".to_string(),
            actor_id:      reviewer,
            resource_type: "entity".to_string(),
            resource_id:   entity_id.to_string(),
            metadata:      json!({ "suggestion_id": suggestion_id, "fields_applied": applied }),
            before:        None,
            after:         Some(suggestion),
        });
    }

    (StatusCode::OK, Json(json!({
        "success":        true,
        "applied_fields": applied,
        "message":        "Suggestion approved and applied to entity.",
    }))).into_response()
}

// ── PATCH /ai-suggestions/:id/reject ─────────────────────────────────────────

pub async fn reject_suggestion(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(suggestion_id):   Path<Uuid>,
) -> impl IntoResponse {
    match state.ai_suggestion_service.reject(
        tenant_ctx.tenant_id, suggestion_id, actor_id(&headers),
    ).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true }))).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "suggestion not found or already reviewed" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
