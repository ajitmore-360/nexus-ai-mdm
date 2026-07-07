use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, sse::{Event, KeepAlive, Sse}},
    Json,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::feedback::{StewardFeedback, WeightTuner};
use crate::llm::{sanitize_user_query, Prompts};
use crate::mcp::{McpRequest, RoleContext, route};
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
    headers:      HeaderMap,
    Json(request): Json<McpRequest>,
) -> impl IntoResponse {
    // Cross-tenant isolation: body tenant_id must match the JWT-derived header
    let header_tid = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<Uuid>().ok());

    if let Some(hdr_tid) = header_tid {
        if hdr_tid != request.tenant_id {
            tracing::warn!(
                body_tid  = %request.tenant_id,
                hdr_tid   = %hdr_tid,
                user_id   = ?request.user_id,
                "tenant_id mismatch — possible gateway bypass"
            );
            return (
                StatusCode::FORBIDDEN,
                Json(json!({ "success": false, "error": "tenant_id mismatch" })),
            ).into_response();
        }
    }

    // Role from the JWT-derived gateway header (never from the request body)
    let role = headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("viewer")
        .to_string();

    // Steward scope: look up assigned entity types from DB
    let entity_types: Vec<String> = if role == "steward" {
        if let Some(uid) = request.user_id {
            sqlx::query_scalar::<_, String>(
                "SELECT entity_type_code FROM core_mdm.entity_type_assignments \
                 WHERE identity_id = $1 AND tenant_id = $2",
            )
            .bind(uid)
            .bind(request.tenant_id)
            .fetch_all(&state.pool)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!(error=%e, "entity type lookup failed; using empty scope");
                vec![]
            })
        } else {
            vec![]
        }
    } else {
        vec![]
    };

    // Resolve format — default to "auto" so keyword detection runs when client omits the field
    let raw_fmt = request.response_format.as_deref().unwrap_or("auto");
    let fmt = if raw_fmt == "auto" {
        Prompts::detect_response_format(request.prompt.as_deref().unwrap_or("")).to_string()
    } else {
        raw_fmt.to_string()
    };

    let ctx = RoleContext { role, entity_types, fmt };
    let response = route(&state, request, ctx).await;
    (StatusCode::OK, Json(response)).into_response()
}

// =========================================================================
// MCP COPILOT — STREAMING  (additive: /mcp/stream, existing /mcp/query unchanged)
// =========================================================================

/// SSE streaming handler for free-form copilot prompts.
/// Tool calls are NOT supported on the streaming path; they still use /mcp/query.
pub async fn copilot_stream(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(request): Json<McpRequest>,
) -> axum::response::Response {
    // Cross-tenant isolation
    let header_tid = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<Uuid>().ok());

    if let Some(hdr_tid) = header_tid {
        if hdr_tid != request.tenant_id {
            tracing::warn!(
                body_tid = %request.tenant_id,
                hdr_tid  = %hdr_tid,
                "stream tenant_id mismatch — possible gateway bypass"
            );
            return (
                StatusCode::FORBIDDEN,
                Json(json!({ "success": false, "error": "tenant_id mismatch" })),
            ).into_response();
        }
    }

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
        let tracker_key = request.user_id
            .map(|u| u.to_string())
            .unwrap_or_else(|| request.tenant_id.to_string());
        let rate_exceeded = state.record_injection_attempt(&tracker_key);
        tracing::warn!(
            tenant_id     = %request.tenant_id,
            user_id       = ?request.user_id,
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

    // Role from JWT-derived gateway header
    let role = headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("viewer")
        .to_string();

    let entity_types: Vec<String> = if role == "steward" {
        if let Some(uid) = request.user_id {
            sqlx::query_scalar::<_, String>(
                "SELECT entity_type_code FROM core_mdm.entity_type_assignments \
                 WHERE identity_id = $1 AND tenant_id = $2",
            )
            .bind(uid)
            .bind(request.tenant_id)
            .fetch_all(&state.pool)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!(error=%e, "entity type lookup failed in stream");
                vec![]
            })
        } else {
            vec![]
        }
    } else {
        vec![]
    };

    let raw_fmt = request.response_format.as_deref().unwrap_or("auto");
    let fmt = if raw_fmt == "auto" {
        Prompts::detect_response_format(&prompt).to_string()
    } else {
        raw_fmt.to_string()
    };

    let tenant_name = state.tenant_name(request.tenant_id).await;

    // Embed + retrieve + format prompt (fast; ~100-300ms)
    let augmented_prompt = match state
        .rag_pipeline
        .build_prompt(request.tenant_id, &tenant_name, &prompt, None, &role, &entity_types, &fmt)
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

    // Start the streaming LLM generation (JSON mode when table format is expected)
    let token_stream = match state.llm.generate_stream(&augmented_prompt, fmt == "table").await {
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

// =========================================================================
// INTERNAL SUGGEST  — internal only, called by mdm-core on Docker network
// Privacy: caller strips PII before sending. This handler is stateless.
// =========================================================================

#[derive(Deserialize)]
pub struct SuggestRequest {
    pub suggestion_type: String,
    pub entity_type:     String,
    pub safe_fields:     serde_json::Map<String, serde_json::Value>,
    #[serde(default)]
    pub target_fields:   Vec<String>,
}

pub async fn internal_suggest(
    State(state): State<AppState>,
    Json(req):    Json<SuggestRequest>,
) -> impl IntoResponse {
    let prompt = build_suggest_prompt(&req);
    match state.llm.generate(&prompt, true).await {
        Ok(raw) => {
            let (suggestions, rationale) = parse_suggest_response(&raw);
            (StatusCode::OK, Json(json!({
                "success":     true,
                "suggestions": suggestions,
                "rationale":   rationale,
            })))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

fn build_suggest_prompt(req: &SuggestRequest) -> String {
    let fields_json = serde_json::to_string_pretty(&req.safe_fields).unwrap_or_default();
    let targets = if req.target_fields.is_empty() {
        "all fields that appear incomplete or inconsistent".to_string()
    } else {
        req.target_fields.join(", ")
    };

    match req.suggestion_type.as_str() {
        "address_parse" => format!(
            "You are a data quality assistant. Parse the raw address into structured fields.\n\
             Entity type: {etype}\nRaw data (non-PII): {fields}\n\n\
             Return ONLY JSON:\n\
             {{\"suggestions\":[{{\"field\":\"street\",\"proposed_value\":\"...\",\"confidence\":0.9,\"rationale\":\"...\"}}],\
             \"rationale\":\"...\"}}\n\
             Fields to extract: street, city, state, postal_code, country.\n\
             If a field cannot be determined set proposed_value to \"\" and confidence to 0.",
            etype  = req.entity_type,
            fields = fields_json,
        ),
        "anomaly" => format!(
            "You are a data quality analyst. Review this entity for anomalies.\n\
             Entity type: {etype}\nField values (non-PII): {fields}\n\n\
             Return ONLY JSON:\n\
             {{\"suggestions\":[{{\"field\":\"name\",\"proposed_value\":\"fix\",\"confidence\":0.85,\"rationale\":\"why\"}}],\
             \"rationale\":\"...\"}}\n\
             Only flag genuine data issues. Return empty suggestions array if data looks correct.",
            etype  = req.entity_type,
            fields = fields_json,
        ),
        _ => format!(
            "You are a data enrichment assistant. Suggest values for missing fields.\n\
             Entity type: {etype}\nKnown non-PII fields: {fields}\n\
             Missing fields needing values: {targets}\n\n\
             Return ONLY JSON:\n\
             {{\"suggestions\":[{{\"field\":\"name\",\"proposed_value\":\"value\",\"confidence\":0.8,\"rationale\":\"source\"}}],\
             \"rationale\":\"...\"}}\n\
             Only suggest values you can reasonably infer from context.",
            etype   = req.entity_type,
            fields  = fields_json,
            targets = targets,
        ),
    }
}

fn parse_suggest_response(raw: &str) -> (serde_json::Value, String) {
    let json_str = raw.find('{').and_then(|start| {
        let tail = &raw[start..];
        let mut depth = 0i32;
        let mut end   = None;
        for (i, c) in tail.char_indices() {
            match c {
                '{' => depth += 1,
                '}' => { depth -= 1; if depth == 0 { end = Some(i + 1); break; } }
                _   => {}
            }
        }
        end.map(|e| &tail[..e])
    }).unwrap_or("{}");

    if let Ok(v) = serde_json::from_str::<serde_json::Value>(json_str) {
        let rationale   = v["rationale"].as_str().unwrap_or("").to_string();
        let suggestions = v["suggestions"].clone();
        return (suggestions, rationale);
    }
    (serde_json::Value::Array(vec![]), "LLM response could not be parsed".to_string())
}
