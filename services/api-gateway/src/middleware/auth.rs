use std::env;

use axum::{
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

use nexus_auth::{validate_token, JwtConfig};

use crate::state::AppState;

/// JWT-aware authentication middleware.
///
/// Accepts requests in two modes:
/// 1. **Auth disabled** (`AUTH_DISABLED=true`) — passes all requests.
///    For local dev only; never deploy with this flag set.
/// 2. **JWT mode** (production) — validates `Authorization: Bearer <jwt>`
///    using HS256 and the `JWT_SECRET` env var.  On success, the validated
///    `Claims` are injected as a request extension so downstream handlers
///    can access user_id, tenant_id, and role without re-parsing the token.
///
/// Legacy API bearer token is still supported when `JWT_SECRET` is absent
/// and `API_BEARER_TOKEN` is set (for CLI tooling / service-to-service calls).
pub async fn auth_middleware(
    State(_state): State<AppState>,
    mut request:  Request<axum::body::Body>,
    next:         Next,
) -> Response {

    // ── 1. Dev bypass ────────────────────────────────────────────────────
    let auth_disabled = env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if auth_disabled {
        return next.run(request).await;
    }

    // ── 2. Extract bearer token from Authorization header ────────────────
    let raw_token = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|h| {
            h.strip_prefix("Bearer ")
             .or_else(|| h.strip_prefix("bearer "))
        })
        .unwrap_or("");

    if raw_token.is_empty() {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({
                "success": false,
                "error":   "Authorization header missing or malformed. Use: Bearer <token>"
            })),
        )
            .into_response();
    }

    // ── 3a. Try JWT validation ────────────────────────────────────────────
    if let Ok(jwt_cfg) = JwtConfig::from_env() {
        match validate_token(&jwt_cfg, raw_token) {
            Ok(claims) => {
                // Inject claims so downstream handlers can use them
                request.extensions_mut().insert(claims);
                return next.run(request).await;
            }
            Err(e) => {
                // Only reject if this LOOKS like a JWT (3 dot-separated parts)
                // so we can still fall through to legacy bearer check.
                if raw_token.matches('.').count() == 2 {
                    tracing::warn!(error=%e, "JWT validation failed");
                    return (
                        StatusCode::UNAUTHORIZED,
                        Json(json!({
                            "success": false,
                            "error":   format!("JWT invalid: {}", e)
                        })),
                    )
                        .into_response();
                }
            }
        }
    }

    // ── 3b. Legacy API bearer token fallback ─────────────────────────────
    // Used by CLI tools and service-to-service calls with a static token.
    let expected_bearer = env::var("API_BEARER_TOKEN").unwrap_or_default();
    if !expected_bearer.is_empty() && raw_token == expected_bearer {
        return next.run(request).await;
    }

    // ── 4. Reject ─────────────────────────────────────────────────────────
    (
        StatusCode::UNAUTHORIZED,
        Json(json!({
            "success": false,
            "error":   "invalid credentials — provide a valid JWT or API bearer token"
        })),
    )
        .into_response()
}
