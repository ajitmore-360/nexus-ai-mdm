use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::models::{
    ApiResponse, CreateRuleRequest, EvaluateMergeRequest,
    GdprRequest, PolicyContext, PolicyOperation,
    RecordConsentRequest, WithdrawConsentQuery,
};
use crate::state::AppState;

macro_rules! ok {
    ($data:expr) => {
        (StatusCode::OK, Json(ApiResponse::ok($data))).into_response()
    };
}

macro_rules! err {
    ($code:expr, $msg:expr) => {
        ($code, Json(ApiResponse::<serde_json::Value>::err($msg))).into_response()
    };
}

// ── POST /policy/evaluate ──────────────────────────────────────────────────

pub async fn evaluate(
    State(state): State<Arc<AppState>>,
    Json(ctx):    Json<PolicyContext>,
) -> Response {
    match state.evaluator.evaluate(&ctx).await {
        Ok(d)  => ok!(d),
        Err(e) => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/evaluate/merge ────────────────────────────────────────────

pub async fn evaluate_merge(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<EvaluateMergeRequest>,
) -> Response {
    let ctx = PolicyContext {
        tenant_id:     req.tenant_id,
        user_id:       None,
        entity_type:   "merge".to_string(),
        operation:     PolicyOperation::Merge,
        entity:        req.source,
        user_role:     None,
        target_system: None,
        attributes:    Some(req.candidate),
    };
    match state.evaluator.evaluate(&ctx).await {
        Ok(d)  => ok!(d),
        Err(e) => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── GET /policy/rules ─────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ListRulesQuery {
    pub tenant_id:   Uuid,
    pub entity_type: Option<String>,
}

pub async fn list_rules(
    State(state): State<Arc<AppState>>,
    Query(q):     Query<ListRulesQuery>,
) -> Response {
    match state.rule_repo.list_rules(q.tenant_id, q.entity_type.as_deref()).await {
        Ok(rules) => ok!(rules),
        Err(e)    => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/rules ────────────────────────────────────────────────────

pub async fn create_rule(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<CreateRuleRequest>,
) -> Response {
    match state.rule_repo.create_rule(req).await {
        Ok(id) => (StatusCode::CREATED, Json(ApiResponse::ok(id))).into_response(),
        Err(e) => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── DELETE /policy/rules/:id ──────────────────────────────────────────────

#[derive(Deserialize)]
pub struct TenantIdQuery {
    pub tenant_id: Uuid,
}

pub async fn delete_rule(
    State(state):  State<Arc<AppState>>,
    Path(rule_id): Path<Uuid>,
    Query(q):      Query<TenantIdQuery>,
) -> Response {
    match state.rule_repo.delete_rule(rule_id, q.tenant_id).await {
        Ok(deleted) => ok!(serde_json::json!({ "deleted": deleted })),
        Err(e)      => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/gdpr/erasure ─────────────────────────────────────────────

pub async fn gdpr_erasure(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<GdprRequest>,
) -> Response {
    match state.gdpr.process_erasure(&req).await {
        Ok(result) => ok!(result),
        Err(e)     => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/gdpr/access ──────────────────────────────────────────────

pub async fn gdpr_access(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<GdprRequest>,
) -> Response {
    match state.gdpr.process_access(&req).await {
        Ok(data) => ok!(data),
        Err(e)   => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/consent ──────────────────────────────────────────────────

pub async fn record_consent(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<RecordConsentRequest>,
) -> Response {
    match state.consent.record_consent(&req).await {
        Ok(record) => (StatusCode::CREATED, Json(ApiResponse::ok(record))).into_response(),
        Err(e)     => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── GET /policy/consent ───────────────────────────────────────────────────

#[derive(serde::Deserialize)]
pub struct ConsentListQuery {
    pub tenant_id: uuid::Uuid,
    pub entity_id: uuid::Uuid,
}

pub async fn list_consent(
    State(state): State<Arc<AppState>>,
    Query(q):     Query<ConsentListQuery>,
) -> Response {
    match state.consent.list_by_entity(q.tenant_id, q.entity_id).await {
        Ok(records) => ok!(records),
        Err(e)      => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

// ── POST /policy/consent/:id/withdraw ────────────────────────────────────

pub async fn withdraw_consent(
    State(state):    State<Arc<AppState>>,
    Path(consent_id): Path<uuid::Uuid>,
    Query(q):        Query<WithdrawConsentQuery>,
) -> Response {
    match state.consent.withdraw(q.tenant_id, consent_id).await {
        Ok(true)  => ok!(serde_json::json!({ "withdrawn": true })),
        Ok(false) => err!(StatusCode::NOT_FOUND, "consent record not found or already withdrawn"),
        Err(e)    => err!(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}
