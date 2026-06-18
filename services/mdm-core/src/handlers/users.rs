use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use nexus_auth::{hash_password, issue_tokens, verify_password, JwtConfig, Role};

use crate::AppState;

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST / RESPONSE TYPES
// ─────────────────────────────────────────────────────────────────────────────

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub email:     String,
    pub password:  String,
    pub tenant_id: Option<Uuid>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub email:        String,
    pub password:     String,
    pub display_name: String,
    pub tenant_id:    Uuid,
    pub role:         Option<String>,
}

/// Used by the POST /auth/change-password endpoint (planned).
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password:     String,
}

#[allow(dead_code)]
#[derive(Debug, Serialize)]
pub struct UserResponse {
    pub user_id:      Uuid,
    pub tenant_id:    Uuid,
    pub email:        String,
    pub display_name: String,
    pub role:         String,
    pub created_at:   String,
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/login
// ─────────────────────────────────────────────────────────────────────────────

pub async fn login(
    State(state): State<Arc<AppState>>,
    headers:      axum::http::HeaderMap,
    Json(req):    Json<LoginRequest>,
) -> Response {
    let email = req.email.trim().to_lowercase();

    if email.is_empty() || req.password.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "email and password are required" })),
        )
            .into_response();
    }

    // ── Brute-force protection ───────────────────────────────────────────────
    // Rate-limit login attempts per IP: max 10 attempts per 5-minute window.
    // This is intentionally BEFORE the DB lookup so we don't leak timing info
    // about whether the email exists.
    let client_ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(str::trim)
        .unwrap_or("unknown");

    let rate_key = format!("login:{}:{}", client_ip, &email[..email.len().min(64)]);

    if let Some(ref redis_limiter) = state.redis_rate_limiter {
        match redis_limiter.check(&rate_key).await {
            Ok(false) => {
                tracing::warn!(ip=%client_ip, "login rate limit exceeded");
                return (
                    StatusCode::TOO_MANY_REQUESTS,
                    Json(json!({
                        "success": false,
                        "error": "too many login attempts — try again in 5 minutes"
                    })),
                )
                    .into_response();
            }
            Ok(true)  => {}
            Err(e)    => {
                tracing::warn!(error=%e, "login rate limiter error — allowing request");
            }
        }
    }

    // Look up user in database
    let row = match sqlx::query(
        r#"
        SELECT user_id, tenant_id, email, display_name, role, password_hash
        FROM core_mdm.users
        WHERE email = $1 AND status = 'active'
        LIMIT 1
        "#,
    )
    .bind(&email)
    .fetch_optional(&state.db)
    .await
    {
        Ok(row) => row,
        Err(e) => {
            tracing::error!(error=%e, "DB error during login");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "authentication service error" })),
            )
                .into_response();
        }
    };

    // ── Constant-time auth (prevents account enumeration + timing oracle) ─────
    //
    // SECURITY: Whether the user exists or not, we ALWAYS perform a bcrypt
    // comparison before returning. This ensures:
    //   1. Response time is the same for "user not found" and "wrong password"
    //      (prevents timing-based account enumeration).
    //   2. The error message is identical in both cases ("invalid credentials"),
    //      so an attacker cannot distinguish between unknown email and wrong
    //      password by observing the response body.
    //   3. The SSO-only case also uses the same timing and error message.
    //
    // A real bcrypt $2b$ hash of "dummy-password-for-constant-time-comparison"
    // computed at bcrypt cost 12 — used when no real hash is available.
    const DUMMY_HASH: &str =
        "$2b$12$8p/jdF3aHVlQ1e5mvTVnxOX0AJfKf7C5Vd3Fz1Mj2hj5E9qWkLuC6";

    let (real_user, hash_to_check) = match row {
        None => (None, DUMMY_HASH.to_string()),
        Some(ref r) => {
            let h = r.try_get::<Option<String>, _>("password_hash")
                .ok()
                .flatten()
                .unwrap_or_else(|| DUMMY_HASH.to_string());
            (Some(r), h)
        }
    };

    let password_ok = verify_password(&req.password, &hash_to_check).unwrap_or(false);

    // If user doesn't exist OR password doesn't match — same response, same timing
    if real_user.is_none() || !password_ok {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": "invalid credentials" })),
        )
            .into_response();
    }

    // Safety: is_none() check above already returned early — row is guaranteed Some here.
    let row = match real_user {
        Some(r) => r,
        None => return (StatusCode::UNAUTHORIZED, Json(json!({ "success": false, "error": "invalid credentials" }))).into_response(),
    };
    let user_id: Uuid = match row.try_get("user_id") {
        Ok(v) => v,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": format!("db column error: {e}") }))).into_response(),
    };
    let tenant_id: Uuid = match row.try_get("tenant_id") {
        Ok(v) => v,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": format!("db column error: {e}") }))).into_response(),
    };
    let display_name: String = row.try_get("display_name").unwrap_or_default();
    let role_str:     String = row.try_get("role").unwrap_or_else(|_| "steward".to_string());

    // Issue tokens — password already verified above
    let role: Role = role_str.parse().unwrap_or(Role::Steward);
    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
                .into_response();
        }
    };

    let pair = match issue_tokens(&cfg, user_id, tenant_id, &email, role) {
        Ok(p) => p,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
                .into_response();
        }
    };

    // Update last_login_at
    let _ = sqlx::query("UPDATE core_mdm.users SET last_login_at = NOW() WHERE user_id = $1")
        .bind(user_id)
        .execute(&state.db)
        .await;

    tracing::info!(user_id=%user_id, tenant_id=%tenant_id, "user logged in");

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token":  pair.access_token,
            "refresh_token": pair.refresh_token,
            "token_type":    pair.token_type,
            "expires_in":    pair.expires_in,
            "user": {
                "user_id":      user_id,
                "tenant_id":    tenant_id,
                "email":        email,
                "display_name": display_name,
                "role":         role_str,
            }
        }
    })))
        .into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/register
// ─────────────────────────────────────────────────────────────────────────────

pub async fn register(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<RegisterRequest>,
) -> Response {
    let email = req.email.trim().to_lowercase();

    if email.is_empty() || req.password.len() < 8 {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "email required and password must be ≥ 8 characters" })),
        )
            .into_response();
    }

    // Check for existing user
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM core_mdm.users WHERE email = $1 AND tenant_id = $2)",
    )
    .bind(&email)
    .bind(req.tenant_id)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);

    if exists {
        return (
            StatusCode::CONFLICT,
            Json(json!({ "success": false, "error": "a user with this email already exists" })),
        )
            .into_response();
    }

    let hash = match hash_password(&req.password) {
        Ok(h) => h,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
                .into_response();
        }
    };

    let role = req.role.as_deref().unwrap_or("steward");
    let user_id = Uuid::new_v4();

    match sqlx::query(
        r#"
        INSERT INTO core_mdm.users
          (user_id, tenant_id, email, display_name, role, password_hash, status, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, 'active', NOW())
        "#,
    )
    .bind(user_id)
    .bind(req.tenant_id)
    .bind(&email)
    .bind(&req.display_name)
    .bind(role)
    .bind(&hash)
    .execute(&state.db)
    .await
    {
        Ok(_) => {}
        Err(e) => {
            tracing::error!(error=%e, "failed to create user");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to create user" })),
            )
                .into_response();
        }
    }

    // GDPR/PII: Do not log the email address — user_id is sufficient for audit correlation
    tracing::info!(user_id=%user_id, tenant_id=%req.tenant_id, "user registered");

    (StatusCode::CREATED, Json(json!({
        "success": true,
        "data": {
            "user_id":      user_id,
            "tenant_id":    req.tenant_id,
            "email":        email,
            "display_name": req.display_name,
            "role":         role,
        }
    })))
        .into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /users — list users for tenant
// ─────────────────────────────────────────────────────────────────────────────

pub async fn list_users(
    State(state):           State<Arc<AppState>>,
    axum::Extension(claims): axum::Extension<nexus_auth::Claims>,
) -> Response {
    let rows = sqlx::query(
        r#"
        SELECT user_id, tenant_id, email, display_name, role, status, created_at
        FROM core_mdm.users
        WHERE tenant_id = $1
        ORDER BY created_at DESC
        LIMIT 100
        "#,
    )
    .bind(claims.nxs_tenant_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let users: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "user_id":      r.try_get::<Uuid, _>("user_id").unwrap_or(Uuid::nil()),
                "email":        r.try_get::<String, _>("email").unwrap_or_default(),
                "display_name": r.try_get::<String, _>("display_name").unwrap_or_default(),
                "role":         r.try_get::<String, _>("role").unwrap_or_default(),
                "status":       r.try_get::<String, _>("status").unwrap_or_default(),
                "created_at":   r.try_get::<chrono::DateTime<Utc>, _>("created_at")
                                  .map(|d| d.to_rfc3339())
                                  .unwrap_or_default(),
            })
        })
        .collect();

    (StatusCode::OK, Json(json!({ "success": true, "data": users }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /users/:id/role — change user role (admin only)
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ChangeRoleRequest {
    pub role: String,
}

pub async fn change_role(
    State(state):           State<Arc<AppState>>,
    axum::Extension(claims): axum::Extension<nexus_auth::Claims>,
    Path(user_id):          Path<Uuid>,
    Json(req):              Json<ChangeRoleRequest>,
) -> Response {
    if !claims.nxs_role.can_admin() {
        return (
            StatusCode::FORBIDDEN,
            Json(json!({ "success": false, "error": "admin role required" })),
        )
            .into_response();
    }

    let valid_roles = ["viewer", "analyst", "steward", "admin"];
    if !valid_roles.contains(&req.role.as_str()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "invalid role" })),
        )
            .into_response();
    }

    let affected = sqlx::query(
        "UPDATE core_mdm.users SET role = $1 WHERE user_id = $2 AND tenant_id = $3",
    )
    .bind(&req.role)
    .bind(user_id)
    .bind(claims.nxs_tenant_id)
    .execute(&state.db)
    .await
    .map(|r| r.rows_affected())
    .unwrap_or(0);

    if affected == 0 {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "user not found" })),
        )
            .into_response();
    }

    (StatusCode::OK, Json(json!({ "success": true }))).into_response()
}
