use std::env;

use axum::{
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

use azile_auth::{validate_token, JwtConfig, TokenPurpose};
use uuid::Uuid;

use crate::state::AppState;

/// JWT-aware authentication middleware.
///
/// Accepts requests in two modes:
/// 1. **Auth disabled** (`AUTH_DISABLED=true`) â€” passes all requests.
///    For local dev only; never deploy with this flag set.
/// 2. **JWT mode** (production) â€” validates `Authorization: Bearer <jwt>`
///    using HS256 and the `JWT_SECRET` env var.  On success, the validated
///    `Claims` are injected as a request extension so downstream handlers
///    can access user_id, tenant_id, and role without re-parsing the token.
///
/// Legacy API bearer token is still supported when `JWT_SECRET` is absent
/// and `API_BEARER_TOKEN` is set (for CLI tooling / service-to-service calls).
pub async fn auth_middleware(
    State(state): State<AppState>,
    mut request:  Request<axum::body::Body>,
    next:         Next,
) -> Response {

    // â”€â”€ 1. Dev bypass â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    let auth_disabled = env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if auth_disabled {
        return next.run(request).await;
    }

    // â”€â”€ 2. Extract bearer token from Authorization header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

    // â”€â”€ 3a. Try JWT validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if let Ok(jwt_cfg) = JwtConfig::from_env() {
        match validate_token(&jwt_cfg, raw_token) {
            Ok(claims) => {
                // Reject tokens that have been explicitly revoked (e.g. via logout).
                // Fail-open on Redis errors so a Redis outage never locks out all users.
                if let Some(blocklist) = &state.token_blocklist {
                    match blocklist.is_revoked(claims.nxs_jti).await {
                        Ok(true) => {
                            return (
                                StatusCode::UNAUTHORIZED,
                                Json(json!({
                                    "success": false,
                                    "error":   "token has been revoked"
                                })),
                            ).into_response();
                        }
                        Err(e) => {
                            tracing::warn!(error=%e, "Redis JTI blocklist check failed; allowing request");
                        }
                        Ok(false) => {}
                    }
                }
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

    // â”€â”€ 3b. Legacy API bearer token fallback â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Used for service-to-service calls from trusted internal services only.
    // The client-supplied x-tenant-id header is still validated against JWT
    // in tenant_middleware when JWT claims are present.  On this path there
    // are no JWT claims, so tenant isolation relies on network-level trust
    // (K8s NetworkPolicy / VPC) â€” document this in your threat model.
    let expected_bearer = env::var("API_BEARER_TOKEN").unwrap_or_default();
    if !expected_bearer.is_empty() && raw_token == expected_bearer {
        // Inject a synthetic service identity so downstream middleware and
        // RBAC guards can distinguish service-to-service calls from real users.
        // This grants Steward-level access â€” enough for internal service calls
        // but not SuperAdmin or platform-admin operations.
        let service_claims = azile_auth::Claims {
            sub:           "service-account".to_string(),
            iss:           "nexus-ai-mdm".to_string(),
            exp:           i64::MAX,
            iat:           0,
            nxs_purpose:   TokenPurpose::Access,
            nxs_tenant_id: Uuid::nil(), // overridden by tenant_middleware from x-tenant-id header
            nxs_email:     "service@internal.azile".to_string(),
            nxs_role:      azile_auth::Role::Steward,
            nxs_jti:       Uuid::nil(),
        };
        request.extensions_mut().insert(service_claims);
        tracing::info!(
            path = %request.uri().path(),
            "service-to-service request via API_BEARER_TOKEN"
        );
        return next.run(request).await;
    }

    // â”€â”€ 4. Reject â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    (
        StatusCode::UNAUTHORIZED,
        Json(json!({
            "success": false,
            "error":   "invalid credentials â€” provide a valid JWT or API bearer token"
        })),
    )
        .into_response()
}
