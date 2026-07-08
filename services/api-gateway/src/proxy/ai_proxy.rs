use axum::body::Body;
use axum::response::IntoResponse;
use futures_util::TryStreamExt;
use reqwest::StatusCode;
use serde_json::{json, Value};

use crate::state::AppState;

const MAX_ATTEMPTS: u32 = 3;
const BACKOFF_BASE_MS: u64 = 150;

//
// ========================================
// 🚀 AI SERVICE PROXY
// ========================================
//

/// Proxy a non-streaming request to the AI service with circuit-breaker and
/// exponential-backoff retry.
pub async fn proxy_ai_request(
    state: &AppState,
    payload: Value,
    tenant_id: Option<String>,
    user_id: Option<String>,
    role: Option<String>,
    correlation_id: Option<String>,
    request_id: Option<String>,
) -> Result<(StatusCode, Value), (StatusCode, Value)> {
    let cb = &state.cb_ai;
    if cb.is_open() {
        tracing::warn!("AI service circuit is open; failing fast");
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            json!({ "success": false, "error": "AI service circuit open — temporarily unavailable" }),
        ));
    }

    let url = format!("{}/mcp/query", state.settings.ai_service_url);

    for attempt in 0..MAX_ATTEMPTS {
        if attempt > 0 {
            let delay_ms = BACKOFF_BASE_MS * (1 << (attempt - 1)); // 150, 300 ms
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
            tracing::warn!(attempt, "retrying AI service request");
        }

        let mut request = state
            .services
            .http
            .post(&url)
            .timeout(std::time::Duration::from_secs(60))
            .json(&payload);

        if let Some(ref v) = tenant_id       { request = request.header("x-tenant-id",       v); }
        if let Some(ref v) = user_id         { request = request.header("x-user-id",         v); }
        if let Some(ref v) = role            { request = request.header("x-user-role",        v); }
        if let Some(ref v) = correlation_id  { request = request.header("x-correlation-id",  v); }
        if let Some(ref v) = request_id      { request = request.header("x-request-id",      v); }

        let response = match request.send().await {
            Err(e) => {
                tracing::warn!(attempt, error=%e, "AI service unreachable");
                cb.record_failure();
                if attempt + 1 < MAX_ATTEMPTS { continue; }
                return Err((
                    StatusCode::BAD_GATEWAY,
                    json!({ "success": false, "error": "AI upstream unavailable" }),
                ));
            }
            Ok(r) => r,
        };

        let status = response.status();

        if status.is_server_error() {
            cb.record_failure();
            if attempt + 1 < MAX_ATTEMPTS {
                tracing::warn!(attempt, %status, "AI service 5xx; will retry");
                continue;
            }
        } else if status.is_success() {
            cb.record_success();
        }

        if !status.is_success() {
            let body = response.text().await.unwrap_or_else(|_| "unknown upstream error".into());
            tracing::warn!(upstream_status=%status, "AI service returned non-success");
            return Err((status, json!({ "success": false, "error": body })));
        }

        let body = response.json::<Value>().await.map_err(|e| {
            tracing::error!(error=%e, "failed to parse AI service response");
            (StatusCode::BAD_GATEWAY, json!({ "success": false, "error": "invalid response from AI service" }))
        })?;

        return Ok((status, body));
    }

    Err((StatusCode::BAD_GATEWAY, json!({ "success": false, "error": "AI upstream unavailable" })))
}

/// Proxy a streaming SSE request to the AI service's `/mcp/stream` endpoint.
///
/// Forwards the request body with the same identity headers as the non-streaming
/// proxy, then pipes the SSE byte stream back to the caller unchanged — no
/// buffering, so tokens reach the Flutter client as they leave Ollama.
pub async fn proxy_ai_stream(
    state: &AppState,
    payload: Value,
    tenant_id: Option<String>,
    user_id: Option<String>,
    role: Option<String>,
    correlation_id: Option<String>,
    request_id: Option<String>,
) -> axum::response::Response {
    let url = format!("{}/mcp/stream", state.settings.ai_service_url);

    let mut request = state
        .services
        .http
        .post(&url)
        // 180s — enough for the slowest CPU-only generation; streaming means
        // we see tokens continuously, so the "read timeout" is per-chunk.
        .timeout(std::time::Duration::from_secs(180))
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
    if let Some(v) = request_id {
        request = request.header("x-request-id", v);
    }

    let upstream = match request.send().await {
        Err(e) => {
            tracing::error!(error=%e, "AI service unreachable for streaming");
            return (
                StatusCode::BAD_GATEWAY,
                axum::Json(json!({ "success": false, "error": "AI upstream unavailable" })),
            )
                .into_response();
        }
        Ok(r) => r,
    };

    if !upstream.status().is_success() {
        let status = upstream.status();
        let body_text = upstream.text().await.unwrap_or_default();
        tracing::warn!(upstream_status=%status, "AI stream returned non-success");
        return (
            status,
            axum::Json(json!({ "success": false, "error": body_text })),
        )
            .into_response();
    }

    // Pipe the raw SSE bytes through; map reqwest errors to io::Error so axum
    // Body::from_stream can treat them as a BoxError.
    let bytes_stream = upstream
        .bytes_stream()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()));

    let body = Body::from_stream(bytes_stream);

    axum::http::Response::builder()
        .status(200)
        .header("content-type", "text/event-stream")
        .header("cache-control", "no-cache")
        .header("x-accel-buffering", "no")
        .body(body)
        .unwrap_or_else(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                axum::Json(json!({ "success": false, "error": "stream setup failed" })),
            )
                .into_response()
        })
}
