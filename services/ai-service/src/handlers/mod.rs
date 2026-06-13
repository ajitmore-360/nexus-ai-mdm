use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::feedback::{StewardFeedback, WeightTuner};
use crate::mcp::{McpRequest, route};
use crate::state::AppState;

// =========================================================================
// HEALTH
// =========================================================================

pub async fn health(State(state): State<AppState>) -> impl IntoResponse {
    let llm_ok = state.llm.health_check().await.unwrap_or(false);
    let status = if llm_ok { "healthy" } else { "degraded" };
    Json(json!({
        "status": status,
        "service": "ai-service",
        "llm_available": llm_ok,
    }))
}

// =========================================================================
// MCP COPILOT
// =========================================================================

pub async fn copilot(
    State(state): State<AppState>,
    Json(request): Json<McpRequest>,
) -> impl IntoResponse {
    let response = route(&state, request).await;
    (StatusCode::OK, Json(response))
}

// =========================================================================
// SEMANTIC MATCH
// =========================================================================

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct SemanticMatchRequest {
    pub tenant_id:       Uuid,
    pub source_attrs:    serde_json::Value,
    pub candidate_attrs: serde_json::Value,
    pub algo_score:      f32,
    pub entity_type:     String,
}

pub async fn semantic_match(
    State(state): State<AppState>,
    Json(req): Json<SemanticMatchRequest>,
) -> impl IntoResponse {
    match state
        .semantic_matcher
        .resolve(
            &req.source_attrs,
            &req.candidate_attrs,
            req.algo_score,
            &req.entity_type,
        )
        .await
    {
        Ok(result) => (StatusCode::OK, Json(json!({ "success": true, "result": result }))),
        Err(e)     => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// =========================================================================
// EMBED ENTITY
// =========================================================================

#[derive(Debug, Deserialize)]
pub struct EmbedRequest {
    pub text: String,
}

#[allow(dead_code)]
#[derive(Debug, Serialize)]
pub struct EmbedResponse {
    pub embedding: Vec<f32>,
    pub dims:      usize,
}

pub async fn embed(
    State(state): State<AppState>,
    Json(req): Json<EmbedRequest>,
) -> impl IntoResponse {
    match state.encoder.encode(&req.text).await {
        Ok(embedding) => {
            let dims = embedding.len();
            (StatusCode::OK, Json(json!({ "success": true, "embedding": embedding, "dims": dims })))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// =========================================================================
// STEWARD FEEDBACK
// =========================================================================

pub async fn record_feedback(
    State(state): State<AppState>,
    Json(feedback): Json<StewardFeedback>,
) -> impl IntoResponse {
    match state.feedback.record(&feedback).await {
        Ok(id) => (StatusCode::CREATED, Json(json!({ "success": true, "feedback_id": id }))),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// =========================================================================
// RAG INDEX
// =========================================================================

#[derive(Debug, Deserialize)]
pub struct IndexDocRequest {
    pub tenant_id: Uuid,
    pub doc_type:  String,
    pub title:     String,
    pub content:   String,
}

pub async fn index_document(
    State(state): State<AppState>,
    Json(req): Json<IndexDocRequest>,
) -> impl IntoResponse {
    match state
        .rag_pipeline
        .index(req.tenant_id, &req.doc_type, &req.title, &req.content)
        .await
    {
        Ok(doc_id) => (StatusCode::CREATED, Json(json!({ "success": true, "doc_id": doc_id }))),
        Err(e)     => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// =========================================================================
// ADAPTIVE WEIGHT TUNING  — GET /weights/recommend?tenant_id=&min_samples=
// =========================================================================

#[derive(Debug, Deserialize)]
pub struct WeightRequest {
    pub tenant_id:   Uuid,
    pub min_samples: Option<i64>,
}

pub async fn recommend_weights(
    State(state): State<AppState>,
    axum::extract::Query(req): axum::extract::Query<WeightRequest>,
) -> impl IntoResponse {
    let tuner = WeightTuner::new(state.pool.clone());
    match tuner.recommend(req.tenant_id, req.min_samples.unwrap_or(50)).await {
        Ok(rec) => (StatusCode::OK, Json(json!({ "success": true, "recommendation": rec }))),
        Err(e)  => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// =========================================================================
// ANOMALY SCAN  — GET /anomalies?tenant_id=
// =========================================================================

#[derive(Debug, Deserialize)]
pub struct AnomalyScanRequest {
    pub tenant_id: Uuid,
}

pub async fn scan_anomalies(
    State(state): State<AppState>,
    axum::extract::Query(req): axum::extract::Query<AnomalyScanRequest>,
) -> impl IntoResponse {
    use crate::anomaly::AnomalyDetector;
    let detector = AnomalyDetector::new(state.pool.clone());
    match detector.scan(req.tenant_id).await {
        Ok(anomalies) => (StatusCode::OK, Json(json!({
            "success": true,
            "anomaly_count": anomalies.len(),
            "anomalies": anomalies,
        }))),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}
