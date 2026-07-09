use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension,
    Json,
};

use azile_auth::Claims;
use contracts::ai::mcp::MCPRequest;

use crate::{
    proxy::ai_proxy::{proxy_ai_request, proxy_ai_stream},
    state::AppState,
};

/// Maximum UTF-8 bytes accepted in a copilot prompt.
/// Prevents token-budget exhaustion attacks and OOM on the Ollama side.
const MAX_PROMPT_BYTES: usize = 8_000;

//
// ========================================
// ðŸš€ AI COPILOT ROUTE
// ========================================
//

pub async fn copilot(
    State(state):           State<AppState>,
    // SECURITY: user identity comes ONLY from the validated JWT, never from
    // caller-controlled headers (x-user-id, x-user-role are untrusted).
    claims_opt:             Option<Extension<Claims>>,
    headers:                HeaderMap,
    Json(payload):          Json<MCPRequest>,
) -> impl IntoResponse {

    // Tenant ID from the header â€” already validated against JWT in tenant_middleware
    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    // Identity from JWT claims only (never from caller-controlled headers)
    let (user_id, role) = match claims_opt {
        Some(Extension(ref claims)) => (
            Some(claims.sub.clone()),
            Some(claims.nxs_role.to_string()),
        ),
        None => (None, None),
    };

    let correlation_id = headers
        .get("x-correlation-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    let request_id = headers
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    // Reject prompts that exceed the byte cap â€” protects Ollama from OOM and
    // prevents token-budget exhaustion by large untrusted inputs.
    if payload.prompt.as_deref().map(|p| p.len()).unwrap_or(0) > MAX_PROMPT_BYTES {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(serde_json::json!({
                "success": false,
                "error": format!("prompt exceeds the {} character limit", MAX_PROMPT_BYTES)
            })),
        )
            .into_response();
    }

    let mut payload_json = match serde_json::to_value(payload) {
        Ok(v) => v,
        Err(e) => {
            tracing::error!(error=%e, "failed to serialize MCP request");
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "success": false,
                    "error": "invalid request payload"
                })),
            )
                .into_response();
        }
    };

    // Inject gateway-sourced identity into the forwarded payload.
    // The AI service McpRequest requires tenant_id and optionally user_id;
    // these come from the validated JWT/header rather than the caller-supplied body.
    if let Some(map) = payload_json.as_object_mut() {
        if let Some(ref tid) = tenant_id {
            map.insert("tenant_id".to_string(), serde_json::Value::String(tid.clone()));
        }
        if let Some(ref uid) = user_id {
            map.insert("user_id".to_string(), serde_json::Value::String(uid.clone()));
        }
        if let Some(ref cid) = correlation_id {
            map.insert("correlation_id".to_string(), serde_json::Value::String(cid.clone()));
        }
    }

    match proxy_ai_request(&state, payload_json, tenant_id, user_id, role, correlation_id, request_id).await {
        Ok((status, body)) => (status, Json(body)).into_response(),
        Err((status, body)) => (status, Json(body)).into_response(),
    }
}

//
// ========================================
// ðŸš€ AI COPILOT â€” STREAMING  (additive: /prism/stream)
// ========================================
//

pub async fn copilot_stream(
    State(state):  State<AppState>,
    claims_opt:    Option<Extension<Claims>>,
    headers:       HeaderMap,
    Json(payload): Json<MCPRequest>,
) -> axum::response::Response {
    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    let (user_id, role) = match claims_opt {
        Some(Extension(ref claims)) => (
            Some(claims.sub.clone()),
            Some(claims.nxs_role.to_string()),
        ),
        None => (None, None),
    };

    let correlation_id = headers
        .get("x-correlation-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    let request_id = headers
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    if payload.prompt.as_deref().map(|p| p.len()).unwrap_or(0) > MAX_PROMPT_BYTES {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(serde_json::json!({
                "success": false,
                "error": format!("prompt exceeds the {} character limit", MAX_PROMPT_BYTES)
            })),
        )
            .into_response();
    }

    let mut payload_json = match serde_json::to_value(payload) {
        Ok(v) => v,
        Err(e) => {
            tracing::error!(error=%e, "failed to serialize MCP stream request");
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "success": false,
                    "error": "invalid request payload"
                })),
            )
                .into_response();
        }
    };

    if let Some(map) = payload_json.as_object_mut() {
        if let Some(ref tid) = tenant_id {
            map.insert("tenant_id".into(), serde_json::Value::String(tid.clone()));
        }
        if let Some(ref uid) = user_id {
            map.insert("user_id".into(), serde_json::Value::String(uid.clone()));
        }
        if let Some(ref cid) = correlation_id {
            map.insert("correlation_id".into(), serde_json::Value::String(cid.clone()));
        }
    }

    proxy_ai_stream(&state, payload_json, tenant_id, user_id, role, correlation_id, request_id).await
}
