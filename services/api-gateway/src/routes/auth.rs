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
    // Proxy the login request to mdm-core which has the user repository.
    let url = format!("{}/auth/login", state.settings.mdm_core_url.trim_end_matches('/'));
    match state.services.http
        .post(&url)
        .json(&req)
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
/// Validates a refresh token and issues a new access token.
pub async fn refresh(
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

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token": access,
            "token_type":   "Bearer",
            "expires_in":   900u64,
        }
    }))).into_response()
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
