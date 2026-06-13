use std::env;

use axum::{
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

/// Validates `Authorization: Bearer <token>` unless `AUTH_DISABLED=true`.
pub async fn auth_middleware(
    request: Request<axum::body::Body>,
    next: Next,
) -> Result<Response, Response> {
    let auth_disabled = env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if auth_disabled {
        return Ok(next.run(request).await);
    }

    let expected = env::var("API_BEARER_TOKEN").ok();

    let Some(expected) = expected else {
        return Err(unauthorized(
            "API_BEARER_TOKEN is not configured",
        ));
    };

    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let token = auth_header
        .strip_prefix("Bearer ")
        .or_else(|| auth_header.strip_prefix("bearer "))
        .unwrap_or("");

    if token.is_empty() || token != expected {
        return Err(unauthorized("invalid or missing bearer token"));
    }

    Ok(next.run(request).await)
}

fn unauthorized(message: &str) -> Response {
    (
        StatusCode::UNAUTHORIZED,
        Json(json!({
            "success": false,
            "error": message
        })),
    )
        .into_response()
}
