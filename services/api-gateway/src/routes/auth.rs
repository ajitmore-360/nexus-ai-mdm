use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use nexus_auth::{
    issue_tokens, validate_token,
    Claims, JwtConfig, Role, TokenPurpose,
};

use crate::state::AppState;

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginRequest {
    pub email:     String,
    pub password:  String,
    pub tenant_id: Option<Uuid>,
}

/// POST /auth/login
///
/// Accepts email + password, validates against the user store in `core_mdm.users`,
/// and returns an access + refresh token pair.
///
/// In LOCAL DEV mode (`AUTH_DISABLED=true`), accepts any non-empty credentials
/// and returns a token for the default tenant.
pub async fn login(
    State(state): State<AppState>,
    headers:      axum::http::HeaderMap,
    Json(req):    Json<LoginRequest>,
) -> Response {
    if req.email.trim().is_empty() || req.password.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "email and password are required" })),
        )
            .into_response();
    }

    let auth_disabled = std::env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    // ── Dev bypass: accept any credentials ────────────────────────────────
    if auth_disabled {
        let cfg = match JwtConfig::from_env() {
            Ok(c) => c,
            Err(e) => {
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({ "success": false, "error": e.to_string() })),
                ).into_response();
            }
        };

        const SYSTEM_TENANT: Uuid = Uuid::from_bytes([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]);
        let tenant_id = req.tenant_id.unwrap_or(SYSTEM_TENANT);

        let pair = match issue_tokens(&cfg, Uuid::new_v4(), tenant_id, &req.email, Role::Admin) {
            Ok(p) => p,
            Err(e) => return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response(),
        };

        return (StatusCode::OK, Json(json!({
            "success": true,
            "data": {
                "access_token":  pair.access_token,
                "refresh_token": pair.refresh_token,
                "token_type":    pair.token_type,
                "expires_in":    pair.expires_in,
                "tenant_id":     tenant_id,
                "mode":          "dev_bypass",
            }
        }))).into_response();
    }

    // ── Production: validate against user store ────────────────────────────
    // Resolve tenant_id: body takes priority, then X-Tenant-ID header.
    let tenant_id = req.tenant_id.or_else(|| {
        headers
            .get("x-tenant-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<Uuid>().ok())
    });

    let forward_body = serde_json::json!({
        "email":     req.email.trim(),
        "password":  req.password,
        "tenant_id": tenant_id,
    });

    let url = format!("{}/auth/login", state.settings.mdm_core_url.trim_end_matches('/'));
    match state.services.http
        .post(&url)
        .json(&forward_body)
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            let body: serde_json::Value = resp.json().await.unwrap_or(json!({}));
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, "auth upstream call failed");
            (
                StatusCode::BAD_GATEWAY,
                Json(json!({ "success": false, "error": "authentication service unavailable" })),
            ).into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// REFRESH
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

/// POST /auth/refresh
///
/// Validates a refresh token and issues a new access token + rotated refresh token.
/// Rotating the refresh token on every use means a stolen token can only be used
/// once before the legitimate holder's next refresh invalidates it.
/// The old refresh JTI is added to the Redis blocklist so it cannot be reused even
/// if the rotation response was intercepted.
pub async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> Response {
    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    let claims = match validate_token(&cfg, &req.refresh_token) {
        Ok(c) => c,
        Err(e) => return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": format!("invalid refresh token: {}", e) })),
        ).into_response(),
    };

    if claims.nxs_purpose != TokenPurpose::Refresh {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": "token is not a refresh token" })),
        ).into_response();
    }

    // Check blocklist — fail-open on Redis errors so an outage never locks out all users.
    if let Some(blocklist) = &state.token_blocklist {
        match blocklist.is_revoked(claims.nxs_jti).await {
            Ok(true) => {
                tracing::warn!(jti=%claims.nxs_jti, "refresh token already revoked");
                return (
                    StatusCode::UNAUTHORIZED,
                    Json(json!({ "success": false, "error": "refresh token has been revoked" })),
                ).into_response();
            }
            Err(e) => tracing::warn!(error=%e, "Redis blocklist check failed; allowing refresh"),
            Ok(false) => {}
        }
    }

    let user_id = match claims.user_id() {
        Some(id) => id,
        None => return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": "invalid subject in refresh token" })),
        ).into_response(),
    };

    let access = match cfg.issue_access(
        user_id,
        claims.nxs_tenant_id,
        &claims.nxs_email,
        claims.nxs_role.clone(),
    ) {
        Ok(t) => t,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    // Rotate: issue a brand-new refresh token so the old one is superseded.
    let new_refresh = match cfg.issue_refresh(
        user_id,
        claims.nxs_tenant_id,
        &claims.nxs_email,
        claims.nxs_role,
    ) {
        Ok(t) => t,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    // Revoke the old refresh JTI so it cannot be reused after rotation.
    if let Some(blocklist) = &state.token_blocklist {
        let remaining_secs = (claims.exp as i64 - chrono::Utc::now().timestamp()).max(0) as u64;
        if remaining_secs > 0 {
            if let Err(e) = blocklist.revoke(claims.nxs_jti, std::time::Duration::from_secs(remaining_secs)).await {
                tracing::warn!(error=%e, jti=%claims.nxs_jti, "failed to revoke old refresh JTI after rotation");
            }
        }
    }

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token":  access,
            "refresh_token": new_refresh,
            "token_type":    "Bearer",
            "expires_in":    900u64,
        }
    }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT
// ─────────────────────────────────────────────────────────────────────────────

/// POST /auth/logout
///
/// Revokes BOTH the current access token and the supplied refresh token by
/// adding their JTIs to the Redis blocklist.  The TTL on each entry matches the
/// token's remaining validity so entries auto-expire naturally.
///
/// Body (optional): `{ "refresh_token": "<token>" }`
/// Omitting refresh_token still revokes the access token, but clients SHOULD
/// always send it so the refresh token cannot be replayed after logout.
#[derive(Debug, Deserialize)]
pub struct LogoutRequest {
    pub refresh_token: Option<String>,
}

pub async fn logout(
    State(state):            State<AppState>,
    axum::Extension(claims): axum::Extension<Claims>,
    body: Option<Json<LogoutRequest>>,
) -> Response {
    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    };

    if let Some(blocklist) = &state.token_blocklist {
        let now = chrono::Utc::now().timestamp();

        // Revoke access token.
        let access_secs = ((claims.exp as i64) - now).max(0) as u64;
        if access_secs > 0 {
            if let Err(e) = blocklist.revoke(claims.nxs_jti, std::time::Duration::from_secs(access_secs)).await {
                tracing::warn!(error=%e, jti=%claims.nxs_jti, "failed to revoke access token in Redis");
            }
        }

        // Revoke refresh token if supplied — validate it belongs to the same user.
        if let Some(rt) = body.and_then(|b| b.0.refresh_token) {
            match validate_token(&cfg, &rt) {
                Ok(rc) if rc.nxs_purpose == TokenPurpose::Refresh && rc.sub == claims.sub => {
                    let refresh_secs = ((rc.exp as i64) - now).max(0) as u64;
                    if refresh_secs > 0 {
                        if let Err(e) = blocklist.revoke(rc.nxs_jti, std::time::Duration::from_secs(refresh_secs)).await {
                            tracing::warn!(error=%e, jti=%rc.nxs_jti, "failed to revoke refresh token in Redis");
                        }
                    }
                }
                Ok(_) => {
                    tracing::warn!("logout: refresh token subject mismatch — refresh not revoked");
                }
                Err(e) => {
                    tracing::warn!(error=%e, "logout: invalid refresh token supplied — refresh not revoked");
                }
            }
        }
    } else {
        tracing::warn!("logout called but Redis is unavailable — tokens not revoked server-side");
    }

    (StatusCode::OK, Json(json!({ "success": true, "message": "logged out" }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// ME (current user info)
// ─────────────────────────────────────────────────────────────────────────────

/// GET /auth/me — returns the current user's claims from the JWT.
pub async fn me(
    axum::Extension(claims): axum::Extension<Claims>,
) -> Response {
    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "user_id":   claims.sub,
            "tenant_id": claims.nxs_tenant_id,
            "email":     claims.nxs_email,
            "role":      claims.nxs_role.to_string(),
        }
    }))).into_response()
}
