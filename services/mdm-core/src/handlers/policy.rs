use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::AppState;

/// Weight update payload from ai-service `/weights/recommend`.
#[derive(Debug, Deserialize)]
pub struct WeightUpdateRequest {
    pub exact_weight:    Option<f32>,
    pub fuzzy_weight:    Option<f32>,
    pub phonetic_weight: Option<f32>,
    pub semantic_weight: Option<f32>,
    pub vector_weight:   Option<f32>,
    /// Optional threshold updates
    pub auto_merge_threshold: Option<f32>,
    pub review_threshold:     Option<f32>,
}

#[derive(Debug, Serialize)]
pub struct WeightResponse {
    pub exact_weight:    f32,
    pub fuzzy_weight:    f32,
    pub phonetic_weight: f32,
    pub semantic_weight: f32,
    pub vector_weight:   f32,
    pub auto_merge_threshold: f32,
    pub review_threshold:     f32,
}

/// GET /policy/weights — return current matching policy weights.
pub async fn get_weights(State(state): State<Arc<AppState>>) -> Response {
    let policy = state.matching_policy.read().unwrap();
    (StatusCode::OK, Json(json!({
        "success": true,
        "data": WeightResponse {
            exact_weight:         policy.exact_weight,
            fuzzy_weight:         policy.fuzzy_weight,
            phonetic_weight:      policy.phonetic_weight,
            semantic_weight:      policy.semantic_weight,
            vector_weight:        policy.vector_weight,
            auto_merge_threshold: policy.auto_merge_threshold,
            review_threshold:     policy.review_threshold,
        }
    })))
        .into_response()
}

/// PATCH /policy/weights — update matching weights at runtime (no restart needed).
///
/// Called by ai-service when adaptive weight tuning produces a recommendation.
/// Only provided fields are updated; omitted fields keep their current value.
/// Weights are automatically renormalised to sum to 1.0.
pub async fn update_weights(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<WeightUpdateRequest>,
) -> Response {
    let mut policy = match state.matching_policy.write() {
        Ok(p) => p,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": format!("policy lock poisoned: {}", e) })),
            )
                .into_response();
        }
    };

    // Apply partial updates
    if let Some(v) = req.exact_weight    { policy.exact_weight    = v.clamp(0.0, 1.0); }
    if let Some(v) = req.fuzzy_weight    { policy.fuzzy_weight    = v.clamp(0.0, 1.0); }
    if let Some(v) = req.phonetic_weight { policy.phonetic_weight = v.clamp(0.0, 1.0); }
    if let Some(v) = req.semantic_weight { policy.semantic_weight = v.clamp(0.0, 1.0); }
    if let Some(v) = req.vector_weight   { policy.vector_weight   = v.clamp(0.0, 1.0); }

    // Renormalise field weights to sum to 1.0
    let total = policy.exact_weight + policy.fuzzy_weight + policy.phonetic_weight
              + policy.semantic_weight + policy.vector_weight;
    if total > 0.0 {
        policy.exact_weight    /= total;
        policy.fuzzy_weight    /= total;
        policy.phonetic_weight /= total;
        policy.semantic_weight /= total;
        policy.vector_weight   /= total;
    }

    // Threshold updates — validate ordering constraint
    if let Some(v) = req.auto_merge_threshold {
        policy.auto_merge_threshold = v.clamp(0.5, 1.0);
    }
    if let Some(v) = req.review_threshold {
        policy.review_threshold = v.clamp(0.3, policy.auto_merge_threshold - 0.05);
    }

    tracing::info!(
        exact=policy.exact_weight,
        fuzzy=policy.fuzzy_weight,
        phonetic=policy.phonetic_weight,
        semantic=policy.semantic_weight,
        vector=policy.vector_weight,
        "matching policy weights updated at runtime"
    );

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": WeightResponse {
            exact_weight:         policy.exact_weight,
            fuzzy_weight:         policy.fuzzy_weight,
            phonetic_weight:      policy.phonetic_weight,
            semantic_weight:      policy.semantic_weight,
            vector_weight:        policy.vector_weight,
            auto_merge_threshold: policy.auto_merge_threshold,
            review_threshold:     policy.review_threshold,
        }
    })))
        .into_response()
}
