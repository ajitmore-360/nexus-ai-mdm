use axum::http::HeaderMap;
use reqwest::Client;
use serde_json::Value;

/// Build the Authorization header value the mdm-core service expects.
/// mdm-core uses a static API_BEARER_TOKEN for service-to-service auth.
pub fn mdm_service_auth() -> String {
    let token = std::env::var("API_BEARER_TOKEN")
        .unwrap_or_else(|_| "nexus-local-dev-token".to_string());
    format!("Bearer {}", token)
}

pub async fn proxy_mdm_post(
    client: &Client,
    base_url: &str,
    path: &str,
    headers: &HeaderMap,
    payload: Value,
) -> Result<(reqwest::StatusCode, Value), reqwest::Error> {
    let url = format!(
        "{}/{}",
        base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    );

    // Use the service-to-service bearer token — not the client JWT.
    let mut request = client
        .post(url)
        .json(&payload)
        .header("authorization", mdm_service_auth());

    for (name, value) in headers.iter() {
        let key = name.as_str();
        // Forward context headers; skip authorization (already set above).
        if matches!(
            key,
            "x-tenant-id"
                | "x-user-id"
                | "x-user-role"
                | "x-correlation-id"
        ) {
            if let Ok(v) = value.to_str() {
                request = request.header(key, v);
            }
        }
    }

    let response = request.send().await?;
    let status = response.status();
    let body = response.json::<Value>().await?;

    Ok((status, body))
}
