use axum::{
    extract::State,
    http::HeaderMap,
    Json,
};

use serde_json::{json, Value};

use contracts::ai::mcp::MCPRequest;

use crate::{
    proxy::ai_proxy::proxy_ai_request,
    state::AppState,
};

//
// ========================================
// 🚀 AI COPILOT ROUTE
// ========================================
//

pub async fn copilot(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<MCPRequest>,
) -> Json<Value> {

    // ====================================
    // 🔐 CONTEXT HEADERS
    // ====================================

    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let user_id = headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let role = headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let correlation_id = headers
        .get("x-correlation-id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    // ====================================
    // 🔁 PROXY
    // ====================================

    let payload_json = match serde_json::to_value(payload) {

        Ok(v) => v,

        Err(e) => {
            return Json(json!({
                "success": false,
                "error": format!(
                    "serialization failed: {}",
                    e
                )
            }));
        }
    };

    let result = proxy_ai_request(
        &state,
        payload_json,
        tenant_id,
        user_id,
        role,
        correlation_id,
    )
    .await;

    match result {

        Ok(response) => Json(response),

        Err(error) => Json(error),
    }
}