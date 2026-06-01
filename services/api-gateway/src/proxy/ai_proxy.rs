use reqwest::Client;
use serde_json::{json, Value};

use crate::state::AppState;

//
// ========================================
// 🚨 STANDARD PROXY ERROR
// ========================================
//

fn proxy_error(
    code: u16,
    message: impl Into<String>,
) -> Value {
    json!({
        "success": false,
        "error": {
            "code": code,
            "message": message.into()
        }
    })
}

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
) -> Result<Value, Value> {

    // ====================================
    // 🌐 TARGET URL
    // ====================================

    let url = format!(
        "{}/mcp/query",
        state.settings.ai_service_url
    );

    // ====================================
    // 🧠 SHARED CLIENT
    // ====================================

    let client: &Client = &state.services.http;

    // ====================================
    // 🚀 BUILD REQUEST
    // ====================================

    let mut request = client
        .post(&url)
        .timeout(std::time::Duration::from_secs(60))
        .json(&payload);

    // ====================================
    // 🔐 FORWARD HEADERS
    // ====================================

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

    // ====================================
    // 📡 EXECUTE REQUEST
    // ====================================

    let response = request.send().await.map_err(|e| {
        proxy_error(
            502,
            format!("AI upstream unavailable: {}", e),
        )
    })?;

    let status = response.status();

    // ====================================
    // ❌ NON SUCCESS
    // ====================================

    if !status.is_success() {

        let body = response
            .text()
            .await
            .unwrap_or_else(|_| "unknown upstream error".into());

        return Err(proxy_error(
            status.as_u16(),
            body,
        ));
    }

    // ====================================
    // ✅ JSON RESPONSE
    // ====================================

    let json_body = response
        .json::<Value>()
        .await
        .map_err(|e| {
            proxy_error(
                500,
                format!("invalid AI response: {}", e),
            )
        })?;

    Ok(json_body)
}