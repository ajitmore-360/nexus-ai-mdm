use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Extension,
    Json,
};
use serde::Deserialize;
use tracing::error;

use crate::handlers::ApiResponse;
use crate::matching::policy::MatchingPolicy;
use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── Request body for PUT /domain-policies/:entity_type_code ─────────────────

#[derive(Deserialize)]
pub struct DomainPolicyBody {
    pub auto_merge_threshold:     Option<f32>,
    pub review_threshold:         Option<f32>,
    pub ambiguity_delta:          Option<f32>,
    pub exact_weight:             Option<f32>,
    pub fuzzy_weight:             Option<f32>,
    pub phonetic_weight:          Option<f32>,
    pub semantic_weight:          Option<f32>,
    pub vector_weight:            Option<f32>,
    pub master_weight_score:      Option<f32>,
    pub master_weight_confidence: Option<f32>,
    pub master_weight_centrality: Option<f32>,
    pub max_clusters:             Option<usize>,
    pub description:              Option<String>,
}

// ── GET /domain-policies ─────────────────────────────────────────────────────

pub async fn list_domain_policies(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state
        .domain_policy_service
        .list(tenant_ctx.tenant_id)
        .await
    {
        Ok(rows) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(rows),
                error:   None,
            }),
        ),
        Err(err) => {
            error!(error=?err, "list_domain_policies failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<Vec<serde_json::Value>> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

// ── GET /domain-policies/:entity_type_code ───────────────────────────────────

pub async fn get_domain_policy(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_type_code): Path<String>,
) -> impl IntoResponse {
    match state
        .domain_policy_service
        .get_policy(tenant_ctx.tenant_id, &entity_type_code)
        .await
    {
        Ok(Some(policy)) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(policy),
                error:   None,
            }),
        )
            .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<MatchingPolicy> {
                success: false,
                data:    None,
                error:   Some(format!(
                    "No domain policy found for entity type '{}'",
                    entity_type_code
                )),
            }),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, entity_type_code=%entity_type_code, "get_domain_policy failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<MatchingPolicy> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ── PUT /domain-policies/:entity_type_code ───────────────────────────────────

pub async fn upsert_domain_policy(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_type_code): Path<String>,
    Json(body): Json<DomainPolicyBody>,
) -> impl IntoResponse {
    // Read the current global policy as the baseline and overlay any provided fields.
    let base: MatchingPolicy = state
        .matching_policy
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone();

    let merged = MatchingPolicy {
        auto_merge_threshold:     body.auto_merge_threshold.unwrap_or(base.auto_merge_threshold),
        review_threshold:         body.review_threshold.unwrap_or(base.review_threshold),
        ambiguity_delta:          body.ambiguity_delta.unwrap_or(base.ambiguity_delta),
        exact_weight:             body.exact_weight.unwrap_or(base.exact_weight),
        fuzzy_weight:             body.fuzzy_weight.unwrap_or(base.fuzzy_weight),
        phonetic_weight:          body.phonetic_weight.unwrap_or(base.phonetic_weight),
        semantic_weight:          body.semantic_weight.unwrap_or(base.semantic_weight),
        vector_weight:            body.vector_weight.unwrap_or(base.vector_weight),
        master_weight_score:      body.master_weight_score.unwrap_or(base.master_weight_score),
        master_weight_confidence: body.master_weight_confidence.unwrap_or(base.master_weight_confidence),
        master_weight_centrality: body.master_weight_centrality.unwrap_or(base.master_weight_centrality),
        max_clusters:             body.max_clusters.unwrap_or(base.max_clusters),
    };

    let description = body.description.as_deref();

    match state
        .domain_policy_service
        .upsert(tenant_ctx.tenant_id, &entity_type_code, &merged, description)
        .await
    {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(merged),
                error:   None,
            }),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, entity_type_code=%entity_type_code, "upsert_domain_policy failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<MatchingPolicy> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}

// ── DELETE /domain-policies/:entity_type_code ────────────────────────────────

pub async fn delete_domain_policy(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(entity_type_code): Path<String>,
) -> impl IntoResponse {
    match state
        .domain_policy_service
        .delete(tenant_ctx.tenant_id, &entity_type_code)
        .await
    {
        Ok(true) => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                success: true,
                data:    None,
                error:   None,
            }),
        )
            .into_response(),
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()> {
                success: false,
                data:    None,
                error:   Some(format!(
                    "No domain policy found for entity type '{}'",
                    entity_type_code
                )),
            }),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, entity_type_code=%entity_type_code, "delete_domain_policy failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
                .into_response()
        }
    }
}
