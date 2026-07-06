use axum::http::HeaderMap;
use reqwest::{Client, StatusCode};
use serde_json::Value;

use crate::proxy::circuit_breaker::CircuitBreaker;

/// Maximum number of attempts for retryable proxy calls (1 initial + 2 retries).
const MAX_ATTEMPTS: u32 = 3;
/// Base backoff in milliseconds — doubles each retry.
const BACKOFF_BASE_MS: u64 = 100;

/// Build the Authorization header value the mdm-core service expects.
/// mdm-core uses a static API_BEARER_TOKEN for service-to-service auth.
pub fn mdm_service_auth() -> String {
    let token = std::env::var("API_BEARER_TOKEN").unwrap_or_default();
    format!("Bearer {}", token)
}

/// POST to the mdm-core service with circuit-breaker protection and exponential-backoff retry.
///
/// Fails fast when the circuit is open (after 5 consecutive failures).
/// Retries on network errors and 5xx upstream responses.
/// 4xx responses are returned immediately — they're client errors retrying can't fix.
pub async fn proxy_mdm_post(
    client: &Client,
    base_url: &str,
    path: &str,
    headers: &HeaderMap,
    payload: Value,
    cb: &CircuitBreaker,
) -> Result<(StatusCode, Value), reqwest::Error> {
    let url = format!(
        "{}/{}",
        base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    );

    // Fail fast when the circuit is open — don't attempt the network call.
    if cb.is_open() {
        tracing::warn!(%url, "mdm-core circuit is open; failing fast");
        return Ok((StatusCode::SERVICE_UNAVAILABLE, serde_json::json!({
            "success": false,
            "error": "mdm-core circuit open — upstream temporarily unavailable"
        })));
    }

    let mut last_err: Option<reqwest::Error> = None;

    for attempt in 0..MAX_ATTEMPTS {
        if attempt > 0 {
            let delay_ms = BACKOFF_BASE_MS * (1 << (attempt - 1)); // 100, 200 ms
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
            tracing::warn!(attempt, url=%url, "retrying mdm-core proxy request");
        }

        // Rebuild the request each attempt — RequestBuilder is consumed by send().
        let mut request = client
            .post(&url)
            .json(&payload)
            .header("authorization", mdm_service_auth());

        for (name, value) in headers.iter() {
            let key = name.as_str();
            if matches!(
                key,
                "x-tenant-id"
                    | "x-user-id"
                    | "x-user-role"
                    | "x-correlation-id"
                    | "x-request-id"
                    | "traceparent"
                    | "tracestate"
            ) {
                if let Ok(v) = value.to_str() {
                    request = request.header(key, v);
                }
            }
        }

        match request.send().await {
            Err(e) => {
                tracing::warn!(attempt, error=%e, "mdm-core network error");
                cb.record_failure();
                last_err = Some(e);
                // Network errors are always retryable.
            }
            Ok(response) => {
                let status = response.status();
                if status.is_server_error() {
                    cb.record_failure();
                    if attempt + 1 < MAX_ATTEMPTS {
                        tracing::warn!(attempt, %status, "mdm-core 5xx; will retry");
                        last_err = None;
                        continue;
                    }
                } else {
                    cb.record_success();
                }
                let body: Value = response
                    .text()
                    .await
                    .ok()
                    .and_then(|t| serde_json::from_str(&t).ok())
                    .unwrap_or_else(|| serde_json::json!({"success": false, "error": "upstream returned non-JSON response"}));
                return Ok((status, body));
            }
        }
    }

    // All attempts exhausted via network errors.
    Err(last_err.expect("loop exited without error — this is a bug"))
}
