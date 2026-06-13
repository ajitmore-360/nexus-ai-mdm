use reqwest::StatusCode;
use serde_json::{json, Value};

use crate::state::AppState;

//
// ========================================
// 🚀 AI SERVICE PROXY
// ========================================
//

pub async fn proxy_ai_request(
    state: &AppState,
    payload: Value,
    tenant_id: Option<String>,
    user_id: Option<String>,
    role: Option<String>,
    correlation_id: Option<String>,
) -> Result<(StatusCode, Value), (StatusCode, Value)> {

    let url = format!("{}/mcp/query", state.settings.ai_service_url);

    let mut request = state
        .services
        .http
        .post(&url)
        .timeout(std::time::Duration::from_secs(60))
        .json(&payload);

    if let Some(v) = tenant_id {
        request = request.header("x-tenant-id", v);
    }
    if let Some(v) = user_id {
        request = request.header("x-user-id", v);
    }
    if let Some(v) = role {
        request = request.header("x-user-role", v);
    }
    if let Some(v) = correlation_id {
        request = request.header("x-correlation-id", v);
    }

    let response = request.send().await.map_err(|e| {
        tracing::error!(error=%e, "AI service unreachable");
        (
            StatusCode::BAD_GATEWAY,
            json!({ "success": false, "error": "AI upstream unavailable" }),
        )
    })?;

    let status = response.status();

    if !status.is_success() {
        let body = response
            .text()
            .await
            .unwrap_or_else(|_| "unknown upstream error".into());

        tracing::warn!(upstream_status=%status, "AI service returned non-success");
        return Err((
            status,
            json!({ "success": false, "error": body }),
        ));
    }

    let body = response.json::<Value>().await.map_err(|e| {
        tracing::error!(error=%e, "failed to parse AI service response");
        (
            StatusCode::BAD_GATEWAY,
            json!({ "success": false, "error": "invalid response from AI service" }),
        )
    })?;

    Ok((status, body))
}
