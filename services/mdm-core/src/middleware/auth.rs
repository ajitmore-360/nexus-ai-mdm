use std::env;

use axum::{
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use nexus_auth::{Claims, Role, TokenPurpose};
use serde_json::json;
use uuid::Uuid;

/// Validates `Authorization: Bearer <token>` unless `AUTH_DISABLED=true`.
///
/// After validating the service token, synthesizes a `nexus_auth::Claims`
/// extension from the `x-user-id` and `x-user-role` headers injected by the
/// API gateway's `inject_user_context` middleware.  This lets mdm-core handlers
/// use `Extension<nexus_auth::Claims>` without parsing JWTs directly.
pub async fn auth_middleware(
    mut request: Request<axum::body::Body>,
    next: Next,
) -> Result<Response, Response> {
    let auth_disabled = env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if auth_disabled {
        // In AUTH_DISABLED mode inject a placeholder Claims so handlers don't panic.
        let claims = synthetic_claims(&request);
        request.extensions_mut().insert(claims);
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

    // Synthesize Claims from gateway-injected context headers.
    let claims = synthetic_claims(&request);
    request.extensions_mut().insert(claims);

    Ok(next.run(request).await)
}

/// Build a synthetic Claims from `x-user-id` / `x-user-role` headers.
/// Falls back to Analyst role and nil UUID when headers are absent.
fn synthetic_claims(request: &Request<axum::body::Body>) -> Claims {
    let sub = request
        .headers()
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("00000000-0000-0000-0000-000000000000")
        .to_string();

    let nxs_role: Role = request
        .headers()
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse().ok())
        .unwrap_or(Role::Analyst);

    Claims {
        sub,
        nxs_role,
        nxs_tenant_id: Uuid::nil(),
        nxs_email:     String::new(),
        nxs_purpose:   TokenPurpose::Access,
        nxs_jti:       Uuid::nil(),
        exp:           i64::MAX,
        iat:           0,
        iss:           "nexus-ai-mdm".to_string(),
    }
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
