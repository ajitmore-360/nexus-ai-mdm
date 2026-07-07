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

// ── Helper ───────────────────────────────────────────────────────────────────

fn actor_id(headers: &HeaderMap) -> Option<Uuid> {
    headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
}

// ── GET /quality-rules ────────────────────────────────────────────────────────

pub async fn list_quality_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state.data_quality_service.list_rules(tenant_ctx.tenant_id).await {
        Ok(rules) => {
            let items: Vec<serde_json::Value> = rules
                .iter()
                .map(|r| json!({
                    "id":          r.id,
                    "name":        r.name,
                    "entity_type": r.entity_type,
                    "dimension":   r.dimension,
                    "conditions":  r.conditions,
                    "logical_op":  r.logical_op,
                    "action":      r.action,
                    "severity":    r.severity,
                    "priority":    r.priority,
                    "is_active":   r.is_active,
                    "created_by":  r.created_by,
                    "created_at":  r.created_at,
                    "updated_at":  r.updated_at,
                }))
                .collect();
            (StatusCode::OK, Json(json!({ "success": true, "data": items }))).into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── POST /quality-rules ───────────────────────────────────────────────────────

/// Conditions sent by the client may include the new `reference_field`.
/// The JSONB value is stored as-is; `data_quality_service` deserialises it.
#[derive(Deserialize)]
pub struct CreateRuleBody {
    pub name:        String,
    #[serde(default = "default_all")]
    pub entity_type: String,
    #[serde(default = "default_validity")]
    pub dimension:   String,
    /// Array of condition objects — each may contain `reference_field`.
    #[serde(default)]
    pub conditions:  serde_json::Value,
    #[serde(default = "default_and")]
    pub logical_op:  String,
    #[serde(default = "default_flag")]
    pub action:      String,
    #[serde(default = "default_medium")]
    pub severity:    String,
    #[serde(default = "default_priority")]
    pub priority:    i32,
}

fn default_all()      -> String { "all".to_string() }
fn default_validity() -> String { "validity".to_string() }
fn default_and()      -> String { "AND".to_string() }
fn default_flag()     -> String { "flag".to_string() }
fn default_medium()   -> String { "medium".to_string() }
fn default_priority() -> i32    { 100 }

pub async fn create_quality_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<CreateRuleBody>,
) -> impl IntoResponse {
    if body.name.trim().is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({ "success": false, "error": "name is required" })),
        )
            .into_response();
    }

    match state.data_quality_service.create_rule(
        tenant_ctx.tenant_id,
        body.name,
        body.entity_type,
        body.dimension,
        body.conditions,
        body.logical_op,
        body.action,
        body.severity,
        body.priority,
        actor_id(&headers),
    )
    .await
    {
        Ok(rule) => (
            StatusCode::CREATED,
            Json(json!({
                "success": true,
                "data": {
                    "id":          rule.id,
                    "name":        rule.name,
                    "entity_type": rule.entity_type,
                    "dimension":   rule.dimension,
                    "conditions":  rule.conditions,
                    "logical_op":  rule.logical_op,
                    "action":      rule.action,
                    "severity":    rule.severity,
                    "priority":    rule.priority,
                    "is_active":   rule.is_active,
                    "created_at":  rule.created_at,
                    "updated_at":  rule.updated_at,
                }
            })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── PATCH /quality-rules/:id ──────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct UpdateRuleBody {
    pub name:        Option<String>,
    pub entity_type: Option<String>,
    pub dimension:   Option<String>,
    pub conditions:  Option<serde_json::Value>,
    pub logical_op:  Option<String>,
    pub action:      Option<String>,
    pub severity:    Option<String>,
    pub priority:    Option<i32>,
    pub is_active:   Option<bool>,
}

pub async fn update_quality_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(rule_id):         Path<Uuid>,
    Json(body):            Json<UpdateRuleBody>,
) -> impl IntoResponse {
    match state.data_quality_service.update_rule(
        tenant_ctx.tenant_id,
        rule_id,
        body.name,
        body.entity_type,
        body.dimension,
        body.conditions,
        body.logical_op,
        body.action,
        body.severity,
        body.priority,
        body.is_active,
    )
    .await
    {
        Ok(Some(rule)) => (
            StatusCode::OK,
            Json(json!({
                "success": true,
                "data": {
                    "id":          rule.id,
                    "name":        rule.name,
                    "entity_type": rule.entity_type,
                    "dimension":   rule.dimension,
                    "conditions":  rule.conditions,
                    "logical_op":  rule.logical_op,
                    "action":      rule.action,
                    "severity":    rule.severity,
                    "priority":    rule.priority,
                    "is_active":   rule.is_active,
                    "updated_at":  rule.updated_at,
                }
            })),
        )
            .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "rule not found" })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── DELETE /quality-rules/:id ─────────────────────────────────────────────────

pub async fn delete_quality_rule(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(rule_id):         Path<Uuid>,
) -> impl IntoResponse {
    match state.data_quality_service.delete_rule(tenant_ctx.tenant_id, rule_id).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true }))).into_response(),
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "rule not found" })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── POST /quality-rules/reorder ───────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ReorderEntry {
    pub id:       Uuid,
    pub priority: i32,
}

pub async fn reorder_quality_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<Vec<ReorderEntry>>,
) -> impl IntoResponse {
    let order: Vec<(Uuid, i32)> = body.into_iter().map(|e| (e.id, e.priority)).collect();
    match state.data_quality_service.reorder_rules(tenant_ctx.tenant_id, order).await {
        Ok(()) => (StatusCode::OK, Json(json!({ "success": true }))).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── POST /quality-rules/run ───────────────────────────────────────────────────

pub async fn run_quality_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    state
        .data_quality_service
        .run_all_rules_background(tenant_ctx.tenant_id);
    (
        StatusCode::ACCEPTED,
        Json(json!({
            "success": true,
            "message": "Batch quality run started. Violations will appear in the Violations tab shortly."
        })),
    )
        .into_response()
}

// ── GET /quality-violations ───────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ListViolationsParams {
    pub entity_type: Option<String>,
    pub severity:    Option<String>,
    pub resolved:    Option<bool>,
    pub limit:       Option<i64>,
    pub offset:      Option<i64>,
}

pub async fn list_quality_violations(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListViolationsParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(100).min(500);
    let offset = params.offset.unwrap_or(0);

    match state
        .data_quality_service
        .list_violations(
            tenant_ctx.tenant_id,
            params.entity_type.as_deref(),
            params.severity.as_deref(),
            params.resolved,
            limit,
            offset,
        )
        .await
    {
        Ok(items) => (
            StatusCode::OK,
            Json(json!({ "success": true, "data": items })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── PATCH /quality-violations/:id/resolve ─────────────────────────────────────

pub async fn resolve_quality_violation(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(violation_id):    Path<Uuid>,
) -> impl IntoResponse {
    match state
        .data_quality_service
        .resolve_violation(tenant_ctx.tenant_id, violation_id, actor_id(&headers))
        .await
    {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true }))).into_response(),
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "violation not found or already resolved" })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

// ── POST /quality-violations/bulk-resolve ─────────────────────────────────────

#[derive(Deserialize)]
pub struct BulkResolveBody {
    pub ids: Vec<Uuid>,
}

pub async fn bulk_resolve_violations(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<BulkResolveBody>,
) -> impl IntoResponse {
    match state
        .data_quality_service
        .bulk_resolve(tenant_ctx.tenant_id, &body.ids, actor_id(&headers))
        .await
    {
        Ok(count) => (
            StatusCode::OK,
            Json(json!({ "success": true, "resolved": count })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}
