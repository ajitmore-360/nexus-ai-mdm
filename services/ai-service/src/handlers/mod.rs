use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, sse::{Event, KeepAlive, Sse}},
    Json,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::feedback::{StewardFeedback, WeightTuner};
use crate::llm::sanitize_user_query;
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
// MCP COPILOT — STREAMING  (additive: /mcp/stream, existing /mcp/query unchanged)
// =========================================================================

/// SSE streaming handler for free-form copilot prompts.
/// Tool calls are NOT supported on the streaming path; they still use /mcp/query.
pub async fn copilot_stream(
    State(state): State<AppState>,
    Json(request): Json<McpRequest>,
) -> axum::response::Response {
    if request.tool.is_some() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "streaming is only available for free-form prompts, not tool calls" })),
        ).into_response();
    }

    let raw_prompt = request.prompt.as_deref().unwrap_or("").trim();
    if raw_prompt.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "'prompt' is required for streaming" })),
        ).into_response();
    }

    let prompt = sanitize_user_query(raw_prompt);
    if prompt.contains("redacted") {
        // Track injection attempts per user (or tenant if no user_id).
        let tracker_key = request.user_id
            .map(|u| u.to_string())
            .unwrap_or_else(|| request.tenant_id.to_string());
        let rate_exceeded = state.record_injection_attempt(&tracker_key);
        tracing::warn!(
            tenant_id    = %request.tenant_id,
            user_id      = ?request.user_id,
            rate_exceeded = rate_exceeded,
            "stream prompt injection attempt blocked"
        );
        if rate_exceeded {
            return (
                StatusCode::TOO_MANY_REQUESTS,
                Json(json!({ "success": false, "error": "too many prompt injection attempts — access suspended for 60 seconds" })),
            ).into_response();
        }
        return (
            StatusCode::FORBIDDEN,
            Json(json!({ "success": false, "error": "prompt injection pattern detected" })),
        ).into_response();
    }

    let tenant_name = state.tenant_name(request.tenant_id).await;

    // Embed + retrieve + format prompt (fast; ~100-300ms)
    let augmented_prompt = match state
        .rag_pipeline
        .build_prompt(request.tenant_id, &tenant_name, &prompt, None)
        .await
    {
        Err(e) => {
            tracing::error!(error=%e, "RAG build_prompt failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to build RAG context" })),
            ).into_response();
        }
        Ok(p) => p,
    };

    // Start the streaming LLM generation
    let token_stream = match state.llm.generate_stream(&augmented_prompt).await {
        Err(e) => {
            tracing::error!(error=%e, "LLM generate_stream failed to start");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to start LLM stream" })),
            ).into_response();
        }
        Ok(s) => s,
    };

    // Convert token stream → SSE events.  Each event carries {"chunk":"<token>"}.
    // The stream closes naturally when the LLM sends done:true.
    let sse_stream = token_stream.map(|result| -> Result<Event, anyhow::Error> {
        match result {
            Ok(chunk) => {
                let data = json!({ "chunk": chunk }).to_string();
                Ok(Event::default().data(data))
            }
            Err(e) => Err(e),
        }
    });

    Sse::new(sse_stream)
        .keep_alive(KeepAlive::default())
        .into_response()
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

#[tracing::instrument(skip(state, req), fields(tenant_id = %req.tenant_id))]
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
