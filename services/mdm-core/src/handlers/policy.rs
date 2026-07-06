use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;

#[derive(Debug, Deserialize)]
pub struct WeightUpdateRequest {
    pub exact_weight:    Option<f32>,
    pub fuzzy_weight:    Option<f32>,
    pub phonetic_weight: Option<f32>,
    pub semantic_weight: Option<f32>,
    pub vector_weight:   Option<f32>,
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

fn weight_response(policy: &crate::matching::MatchingPolicy) -> WeightResponse {
    WeightResponse {
        exact_weight:         policy.exact_weight,
        fuzzy_weight:         policy.fuzzy_weight,
        phonetic_weight:      policy.phonetic_weight,
        semantic_weight:      policy.semantic_weight,
        vector_weight:        policy.vector_weight,
        auto_merge_threshold: policy.auto_merge_threshold,
        review_threshold:     policy.review_threshold,
    }
}

pub async fn get_weights(State(state): State<Arc<AppState>>) -> Response {
    let policy = state.matching_policy.read().unwrap_or_else(|e| e.into_inner());
    (StatusCode::OK, Json(json!({ "success": true, "data": weight_response(&policy) }))).into_response()
}

pub async fn update_weights(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<WeightUpdateRequest>,
) -> Response {
    let mut policy = match state.matching_policy.write() {
        Ok(p) => p,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": format!("policy lock poisoned: {}", e) })),
        ).into_response(),
    };

    if let Some(v) = req.exact_weight    { policy.exact_weight    = v.clamp(0.0, 1.0); }
    if let Some(v) = req.fuzzy_weight    { policy.fuzzy_weight    = v.clamp(0.0, 1.0); }
    if let Some(v) = req.phonetic_weight { policy.phonetic_weight = v.clamp(0.0, 1.0); }
    if let Some(v) = req.semantic_weight { policy.semantic_weight = v.clamp(0.0, 1.0); }
    if let Some(v) = req.vector_weight   { policy.vector_weight   = v.clamp(0.0, 1.0); }

    let total = policy.exact_weight + policy.fuzzy_weight + policy.phonetic_weight
              + policy.semantic_weight + policy.vector_weight;
    if total > 0.0 {
        policy.exact_weight    /= total;
        policy.fuzzy_weight    /= total;
        policy.phonetic_weight /= total;
        policy.semantic_weight /= total;
        policy.vector_weight   /= total;
    }

    if let Some(v) = req.auto_merge_threshold {
        policy.auto_merge_threshold = v.clamp(0.5, 1.0);
    }
    if let Some(v) = req.review_threshold {
        policy.review_threshold = v.clamp(0.3, policy.auto_merge_threshold - 0.05);
    }

    tracing::info!(
        exact=policy.exact_weight, fuzzy=policy.fuzzy_weight,
        phonetic=policy.phonetic_weight, semantic=policy.semantic_weight,
        vector=policy.vector_weight, "matching policy weights updated at runtime"
    );

    (StatusCode::OK, Json(json!({ "success": true, "data": weight_response(&policy) }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// Survivorship suggestions — derived from historical merge decisions
// ─────────────────────────────────────────────────────────────────────────────

pub async fn get_survivorship_suggestions(State(state): State<Arc<AppState>>) -> Response {
    let rows = match sqlx::query(
        r#"
        SELECT
            field_name,
            strategy,
            COUNT(*)::bigint      AS cnt,
            AVG(confidence_score) AS avg_confidence
        FROM core_mdm.survivorship_field_decisions
        GROUP BY field_name, strategy
        ORDER BY field_name, cnt DESC
        "#,
    )
    .fetch_all(&state.db)
    .await
    {
        Ok(r) => r,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    let mut seen: std::collections::HashSet<String> = Default::default();
    let mut suggestions: Vec<serde_json::Value> = Vec::new();
    for row in &rows {
        let field_name: String = row.get("field_name");
        if seen.contains(&field_name) { continue; }
        seen.insert(field_name.clone());
        let strategy: String = row.get("strategy");
        let total: i64        = row.try_get("cnt").unwrap_or(0);
        let conf: f64         = row.try_get("avg_confidence").unwrap_or(0.0);
        suggestions.push(json!({
            "field_name":         field_name,
            "suggested_strategy": strategy,
            "confidence":         conf,
            "reasoning": format!(
                "In {} merges, '{}' was the winning strategy (avg confidence {:.0}%).",
                total, strategy, conf * 100.0
            ),
        }));
    }
    (StatusCode::OK, Json(json!({ "success": true, "data": suggestions }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// GDPR request log — read from audit_event_log
// ─────────────────────────────────────────────────────────────────────────────

pub async fn list_gdpr_requests(State(state): State<Arc<AppState>>) -> Response {
    let rows = match sqlx::query(
        r#"
        SELECT event_id, aggregate_id, event_type, payload, created_at
        FROM core_mdm.audit_event_log
        WHERE event_type ILIKE '%gdpr%'
           OR event_type ILIKE '%erase%'
        ORDER BY created_at DESC
        LIMIT 100
        "#,
    )
    .fetch_all(&state.db)
    .await
    {
        Ok(r) => r,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    let requests: Vec<serde_json::Value> = rows.iter().map(|r| {
        let event_type: String      = r.get("event_type");
        let req_type = if event_type.to_lowercase().contains("erase") { "Erasure" } else { "Access" };
        let payload: Option<serde_json::Value> = r
            .try_get::<sqlx::types::Json<serde_json::Value>, _>("payload")
            .ok()
            .map(|j| j.0);
        let status = payload.as_ref()
            .and_then(|p| p.get("status"))
            .and_then(|v| v.as_str())
            .unwrap_or("Completed")
            .to_owned();
        let records_affected = payload.as_ref()
            .and_then(|p| p.get("records_affected"))
            .and_then(|v| v.as_i64());
        json!({
            "id":               r.get::<Uuid, _>("event_id"),
            "type":             req_type,
            "subject_id":       r.get::<Option<String>, _>("aggregate_id"),
            "status":           status,
            "timestamp":        r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
            "records_affected": records_affected,
        })
    }).collect();

    (StatusCode::OK, Json(json!({ "success": true, "data": requests }))).into_response()
}
