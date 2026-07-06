use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use nexus_auth::{hash_password, issue_tokens, verify_password, Claims, JwtConfig, Role};
use rand::distributions::Alphanumeric;
use rand::Rng;

use crate::services::audit_service::AuditEvent;
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
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password:     String,
}

#[derive(Debug, Deserialize)]
pub struct InviteUserRequest {
    pub email:                    String,
    pub display_name:             Option<String>,
    pub role:                     Option<String>,
    pub invited_by:               Option<String>,
    /// SuperAdmin-only: create the user in this tenant instead of the caller's tenant.
    pub target_tenant_id:         Option<String>,
    /// Entity type codes the steward is responsible for (only used when role == "steward").
    pub entity_type_assignments:  Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
pub struct AcceptInviteRequest {
    pub token:        String,
    pub password:     String,
    pub display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct InviteInfoQuery {
    pub token: String,
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

    // Resolve tenant: x-tenant-id header > body > auto-discover by email
    let tenant_id_explicit = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .or(req.tenant_id);

    let tenant_id = if let Some(tid) = tenant_id_explicit {
        tid
    } else {
        // No tenant supplied — look up all active memberships for this email.
        let rows = sqlx::query(
            r#"
            SELECT m.tenant_id, t.display_name AS tenant_name
            FROM   core_mdm.identities i
            JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
            JOIN   core_mdm.tenants t            ON t.tenant_id   = m.tenant_id
            WHERE  i.email  = $1
              AND  m.status = 'active'
            ORDER  BY t.display_name
            "#,
        )
        .bind(&email)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default();

        match rows.len() {
            0 => {
                // No active membership — return 401 to avoid account enumeration.
                return (
                    StatusCode::UNAUTHORIZED,
                    Json(json!({ "success": false, "error": "invalid credentials" })),
                ).into_response();
            }
            1 => rows[0].try_get::<Uuid, _>("tenant_id").unwrap_or(Uuid::nil()),
            _ => {
                // Multiple tenants — ask the client to specify one.
                let tenants: Vec<serde_json::Value> = rows.iter().map(|r| {
                    json!({
                        "tenant_id":   r.try_get::<Uuid,   _>("tenant_id")   .unwrap_or(Uuid::nil()),
                        "tenant_name": r.try_get::<String, _>("tenant_name") .unwrap_or_default(),
                    })
                }).collect();
                return (
                    StatusCode::OK,
                    Json(json!({
                        "success": false,
                        "requires_tenant_selection": true,
                        "tenants": tenants,
                    })),
                ).into_response();
            }
        }
    };

    // Look up identity + membership + tenant name in one query
    let row = match sqlx::query(
        r#"
        SELECT i.identity_id, i.email, i.display_name, i.password_hash,
               m.tenant_id, m.role,
               t.display_name AS tenant_name
        FROM   core_mdm.identities i
        JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
        JOIN   core_mdm.tenants t            ON t.tenant_id   = m.tenant_id
        WHERE  i.email     = $1
          AND  m.tenant_id = $2
          AND  m.status    = 'active'
        LIMIT 1
        "#,
    )
    .bind(&email)
    .bind(tenant_id)
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

    // ── Constant-time auth (prevents timing oracle + account enumeration) ────
    const DUMMY_HASH: &str =
        "$2b$12$8p/jdF3aHVlQ1e5mvTVnxOX0AJfKf7C5Vd3Fz1Mj2hj5E9qWkLuC6";

    let (real_row, hash_to_check) = match row {
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

    if real_row.is_none() || !password_ok {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": "invalid credentials" })),
        )
            .into_response();
    }

    let row = real_row.unwrap();
    let identity_id: Uuid = match row.try_get("identity_id") {
        Ok(v) => v,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": format!("db column error: {e}") }))).into_response(),
    };
    let display_name: String = row.try_get("display_name").unwrap_or_default();
    let role_str:     String = row.try_get("role").unwrap_or_else(|_| "steward".to_string());
    let tenant_name:  String = row.try_get("tenant_name").unwrap_or_default();

    let role: Role = role_str.parse().unwrap_or(Role::Steward);
    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    let pair = match issue_tokens(&cfg, identity_id, tenant_id, &email, role.clone()) {
        Ok(p) => p,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    let _ = sqlx::query("UPDATE core_mdm.identities SET last_login_at = NOW() WHERE identity_id = $1")
        .bind(identity_id)
        .execute(&state.db)
        .await;

    tracing::info!(identity_id=%identity_id, tenant_id=%tenant_id, "user logged in");

    // Stewards are scoped to specific entity types — include their assignments
    // in the login response so the client can filter data without a second round-trip.
    let assigned_entity_types: Vec<String> = if role == Role::Steward {
        sqlx::query_scalar(
            "SELECT entity_type_code FROM core_mdm.entity_type_assignments \
             WHERE tenant_id = $1 AND identity_id = $2 ORDER BY entity_type_code",
        )
        .bind(tenant_id)
        .bind(identity_id)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
    } else {
        vec![]
    };

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token":  pair.access_token,
            "refresh_token": pair.refresh_token,
            "token_type":    pair.token_type,
            "expires_in":    pair.expires_in,
            "user": {
                "user_id":               identity_id,
                "tenant_id":             tenant_id,
                "tenant_name":           tenant_name,
                "email":                 email,
                "display_name":          display_name,
                "role":                  role_str,
                "assigned_entity_types": assigned_entity_types,
            }
        }
    })))
        .into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /users — list users for tenant
// ─────────────────────────────────────────────────────────────────────────────

pub async fn list_users(
    State(state):      State<Arc<AppState>>,
    headers:           HeaderMap,
    Extension(claims): Extension<Claims>,
) -> Response {
    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    let Some(tenant_id) = tenant_id else {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "x-tenant-id header required" }))).into_response();
    };

    if !claims.nxs_role.can_admin() {
        return (StatusCode::FORBIDDEN, Json(json!({ "success": false, "error": "admin role required" }))).into_response();
    }

    let rows = sqlx::query(
        r#"
        SELECT i.identity_id, i.email, i.display_name, i.last_login_at,
               m.role, m.status, m.joined_at
        FROM   core_mdm.identities i
        JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
        WHERE  m.tenant_id = $1
        ORDER BY m.joined_at DESC
        LIMIT 100
        "#,
    )
    .bind(tenant_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let users: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "user_id":      r.try_get::<Uuid, _>("identity_id").unwrap_or(Uuid::nil()),
                "email":        r.try_get::<String, _>("email").unwrap_or_default(),
                "display_name": r.try_get::<String, _>("display_name").unwrap_or_default(),
                "role":         r.try_get::<String, _>("role").unwrap_or_default(),
                "status":       r.try_get::<String, _>("status").unwrap_or_default(),
                "created_at":   r.try_get::<chrono::DateTime<Utc>, _>("joined_at")
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
    State(state):      State<Arc<AppState>>,
    headers:           HeaderMap,
    Extension(claims): Extension<Claims>,
    Path(identity_id): Path<Uuid>,
    Json(req):         Json<ChangeRoleRequest>,
) -> Response {
    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    let Some(tenant_id) = tenant_id else {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "x-tenant-id header required" }))).into_response();
    };

    if !claims.nxs_role.can_admin() {
        return (StatusCode::FORBIDDEN, Json(json!({ "success": false, "error": "admin role required" }))).into_response();
    }

    let valid_roles = ["viewer", "analyst", "steward", "admin"];
    if !valid_roles.contains(&req.role.as_str()) {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "invalid role" }))).into_response();
    }

    let affected = sqlx::query(
        "UPDATE core_mdm.tenant_memberships SET role = $1, updated_at = NOW() \
         WHERE identity_id = $2 AND tenant_id = $3",
    )
    .bind(&req.role)
    .bind(identity_id)
    .bind(tenant_id)
    .execute(&state.db)
    .await
    .map(|r| r.rows_affected())
    .unwrap_or(0);

    if affected == 0 {
        return (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "user not found in this tenant" }))).into_response();
    }

    let actor_id = headers.get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    state.audit_service.log_background(AuditEvent {
        tenant_id:     tenant_id,
        event_type:    "user.role_changed".to_string(),
        actor_id,
        resource_type: "identity".to_string(),
        resource_id:   identity_id.to_string(),
        metadata:      json!({ "new_role": req.role }),
        before:        None,
        after:         None,
    });

    (StatusCode::OK, Json(json!({ "success": true }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /admin/users/invite
// ─────────────────────────────────────────────────────────────────────────────

pub async fn invite_user(
    State(state):      State<Arc<AppState>>,
    headers:           HeaderMap,
    Extension(claims): Extension<Claims>,
    Json(req):         Json<InviteUserRequest>,
) -> Response {
    let header_tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    let Some(header_tenant_id) = header_tenant_id else {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "x-tenant-id header required" }))).into_response();
    };

    if !claims.nxs_role.can_admin() {
        return (StatusCode::FORBIDDEN, Json(json!({ "success": false, "error": "admin role required to invite users" }))).into_response();
    }

    // SuperAdmin can target a different tenant via the request body.
    let tenant_id = if claims.nxs_role == Role::SuperAdmin {
        if let Some(ref tid) = req.target_tenant_id {
            match Uuid::parse_str(tid) {
                Ok(id) => id,
                Err(_) => return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "invalid target_tenant_id" }))).into_response(),
            }
        } else {
            header_tenant_id
        }
    } else {
        header_tenant_id
    };

    let email = req.email.trim().to_lowercase();
    if email.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "email required" }))).into_response();
    }

    let role = req.role.as_deref().unwrap_or("viewer");
    let valid_roles = ["admin", "business_admin", "steward", "analyst", "viewer"];
    if !valid_roles.contains(&role) {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "invalid role" }))).into_response();
    }

    let display_name = req.display_name.as_deref().unwrap_or("").to_string();

    // Steward quota check
    let counts_as_steward = matches!(role, "steward" | "admin");
    if counts_as_steward {
        match state.license_service.check_steward_quota(tenant_id).await {
            Ok(quota) if !quota.allowed => {
                return (
                    StatusCode::PAYMENT_REQUIRED,
                    Json(json!({
                        "success": false,
                        "error": format!(
                            "Steward quota exceeded ({}/{}).  Upgrade your plan to add more stewards.",
                            quota.current, quota.limit,
                        )
                    })),
                )
                    .into_response();
            }
            Err(e) => {
                tracing::warn!(error=%e, "steward quota check failed — proceeding without enforcement");
            }
            Ok(quota) => {
                let ns  = Arc::clone(&state.notification_service);
                let tid = tenant_id;
                let (cur, lim) = (quota.current, quota.limit);
                tokio::spawn(async move {
                    ns.check_and_notify_steward_quota(tid, cur, lim).await.ok();
                });
            }
        }
    }

    // Upsert identity — create if new email, or return existing identity_id
    let identity_id: Uuid = match sqlx::query_scalar(
        r#"
        INSERT INTO core_mdm.identities (email, display_name)
        VALUES ($1, $2)
        ON CONFLICT (email) DO UPDATE
            SET updated_at = NOW()
        RETURNING identity_id
        "#,
    )
    .bind(&email)
    .bind(&display_name)
    .fetch_one(&state.db)
    .await
    {
        Ok(id) => id,
        Err(e) => {
            tracing::error!(error=%e, "failed to upsert identity for invite");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to create user" }))).into_response();
        }
    };

    // Upsert membership — set status to 'invited' (re-invite is allowed)
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO core_mdm.tenant_memberships (identity_id, tenant_id, role, status)
        VALUES ($1, $2, $3, 'invited')
        ON CONFLICT (identity_id, tenant_id) DO UPDATE
            SET role = EXCLUDED.role, status = 'invited', updated_at = NOW()
        "#,
    )
    .bind(identity_id)
    .bind(tenant_id)
    .bind(role)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to upsert membership for invite");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to create membership" }))).into_response();
    }

    // Persist entity type assignments for steward invites.
    if role == "steward" {
        if let Some(ref codes) = req.entity_type_assignments {
            if !codes.is_empty() {
                // Clear any existing assignments so re-inviting updates the scope.
                let _ = sqlx::query(
                    r#"DELETE FROM core_mdm.entity_type_assignments
                       WHERE identity_id = $1 AND tenant_id = $2"#,
                )
                .bind(identity_id)
                .bind(tenant_id)
                .execute(&state.db)
                .await;

                for code in codes {
                    if let Err(e) = sqlx::query(
                        r#"INSERT INTO core_mdm.entity_type_assignments
                               (tenant_id, identity_id, entity_type_code)
                           VALUES ($1, $2, $3)
                           ON CONFLICT (tenant_id, identity_id, entity_type_code) DO NOTHING"#,
                    )
                    .bind(tenant_id)
                    .bind(identity_id)
                    .bind(code)
                    .execute(&state.db)
                    .await
                    {
                        tracing::warn!(
                            error=%e, code=%code,
                            "failed to insert entity_type_assignment for steward invite"
                        );
                    }
                }
            }
        }
    }

    // Generate secure invite token (48 alphanumeric chars)
    let invite_token: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(48)
        .map(char::from)
        .collect();

    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO core_mdm.user_invitations (identity_id, tenant_id, token, expires_at)
        VALUES ($1, $2, $3, NOW() + INTERVAL '7 days')
        "#,
    )
    .bind(identity_id)
    .bind(tenant_id)
    .bind(&invite_token)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to create invitation token");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to generate invitation" }))).into_response();
    }

    tracing::info!(identity_id=%identity_id, tenant_id=%tenant_id, "user invited");

    let actor_id = headers.get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    state.audit_service.log_background(AuditEvent {
        tenant_id,
        event_type:    "user.invited".to_string(),
        actor_id,
        resource_type: "identity".to_string(),
        resource_id:   identity_id.to_string(),
        metadata:      json!({ "email": email, "role": role }),
        before:        None,
        after:         None,
    });

    // Fire-and-forget invite email
    {
        let notif_url = std::env::var("NOTIFICATION_SERVICE_URL")
            .unwrap_or_else(|_| "http://localhost:8086".to_string());
        let app_url = std::env::var("APP_URL")
            .unwrap_or_else(|_| "http://localhost:3000".to_string());
        let activation_url = format!("{}/activate?token={}", app_url, invite_token);
        let email_to       = email.clone();
        let name           = if display_name.is_empty() { email.clone() } else { display_name.clone() };
        let invited_by     = req.invited_by.clone().unwrap_or_else(|| "Nexus AI MDM".to_string());

        tokio::spawn(async move {
            let body = serde_json::json!({
                "to":             email_to,
                "display_name":   name,
                "activation_url": activation_url,
                "invited_by":     invited_by,
            });
            match reqwest::Client::new()
                .post(format!("{}/internal/emails/invite", notif_url))
                .json(&body)
                .send()
                .await
            {
                Ok(r) if r.status().is_success() =>
                    tracing::info!(to=%body["to"], "invite email dispatched"),
                Ok(r) =>
                    tracing::warn!(status=%r.status(), to=%body["to"], "invite email endpoint returned error"),
                Err(e) =>
                    tracing::warn!(error=%e, to=%body["to"], "failed to reach notification service for invite email"),
            }
        });
    }

    (StatusCode::CREATED, Json(json!({
        "success": true,
        "data": {
            "user_id":      identity_id,
            "tenant_id":    tenant_id,
            "email":        email,
            "role":         role,
            "status":       "invited",
            "invite_token": invite_token,
        }
    })))
        .into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /auth/invite-info?token=XXX — peek at an invite without consuming it
// ─────────────────────────────────────────────────────────────────────────────

pub async fn invite_info(
    State(state): State<Arc<AppState>>,
    Query(params): Query<InviteInfoQuery>,
) -> Response {
    if params.token.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "token required" }))).into_response();
    }

    let row = sqlx::query(
        r#"
        SELECT i.email, i.display_name, m.role,
               t.display_name AS tenant_name
        FROM   core_mdm.user_invitations inv
        JOIN   core_mdm.identities i          ON i.identity_id = inv.identity_id
        JOIN   core_mdm.tenant_memberships m  ON m.identity_id = inv.identity_id
                                              AND m.tenant_id  = inv.tenant_id
        JOIN   core_mdm.tenants t             ON t.tenant_id   = inv.tenant_id
        WHERE  inv.token       = $1
          AND  inv.accepted_at IS NULL
          AND  inv.expires_at  > NOW()
        LIMIT 1
        "#,
    )
    .bind(&params.token)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(r)) => {
            let email:       String = r.try_get("email").unwrap_or_default();
            let display_name:String = r.try_get("display_name").unwrap_or_default();
            let role:        String = r.try_get("role").unwrap_or_default();
            let tenant_name: String = r.try_get("tenant_name").unwrap_or_default();

            (StatusCode::OK, Json(json!({
                "success": true,
                "data": {
                    "email":        email,
                    "display_name": display_name,
                    "role":         role,
                    "tenant_name":  tenant_name,
                }
            })))
                .into_response()
        }
        Ok(None) => {
            (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "invalid or expired invite token" }))).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, "DB error in invite_info");
            (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "server error" }))).into_response()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/accept-invite
// ─────────────────────────────────────────────────────────────────────────────

pub async fn accept_invite(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<AcceptInviteRequest>,
) -> Response {
    if req.token.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "invite token required" }))).into_response();
    }
    if req.password.len() < 8 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "password must be at least 8 characters" }))).into_response();
    }

    // Validate token — must exist, not yet accepted, not expired
    let invitation = match sqlx::query(
        r#"
        SELECT inv.identity_id, inv.tenant_id,
               i.email, i.display_name,
               m.role,
               t.display_name AS tenant_name
        FROM   core_mdm.user_invitations inv
        JOIN   core_mdm.identities i          ON i.identity_id = inv.identity_id
        JOIN   core_mdm.tenant_memberships m  ON m.identity_id = inv.identity_id
                                              AND m.tenant_id  = inv.tenant_id
        JOIN   core_mdm.tenants t             ON t.tenant_id   = inv.tenant_id
        WHERE  inv.token       = $1
          AND  inv.accepted_at IS NULL
          AND  inv.expires_at  > NOW()
        "#,
    )
    .bind(&req.token)
    .fetch_optional(&state.db)
    .await
    {
        Ok(Some(row)) => row,
        Ok(None) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "invalid or expired invitation token" })),
            )
                .into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "DB error during accept-invite lookup");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "server error" }))).into_response();
        }
    };

    let identity_id: Uuid   = invitation.get("identity_id");
    let tenant_id:   Uuid   = invitation.get("tenant_id");
    let email:       String = invitation.get("email");
    let tenant_name: String = invitation.try_get("tenant_name").unwrap_or_default();
    let display_name: String = req.display_name.clone()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| invitation.try_get("display_name").unwrap_or_default());
    let role: String = invitation.get("role");

    let hash = match hash_password(&req.password) {
        Ok(h) => h,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    // Set password + display name on identity
    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.identities \
         SET password_hash = $1, display_name = $2, is_verified = true, verified_at = NOW(), updated_at = NOW() \
         WHERE identity_id = $3",
    )
    .bind(&hash)
    .bind(&display_name)
    .bind(identity_id)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to activate identity");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to activate account" }))).into_response();
    }

    // Activate membership
    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.tenant_memberships \
         SET status = 'active', updated_at = NOW() \
         WHERE identity_id = $1 AND tenant_id = $2",
    )
    .bind(identity_id)
    .bind(tenant_id)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to activate membership");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to activate account" }))).into_response();
    }

    // Mark invitation as accepted (single-use)
    let _ = sqlx::query("UPDATE core_mdm.user_invitations SET accepted_at = NOW() WHERE token = $1")
        .bind(&req.token)
        .execute(&state.db)
        .await;

    tracing::info!(identity_id=%identity_id, tenant_id=%tenant_id, "user accepted invite");

    // Issue tokens immediately so the user lands in the app
    let parsed_role: Role = role.parse().unwrap_or(Role::Steward);
    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };
    let pair = match issue_tokens(&cfg, identity_id, tenant_id, &email, parsed_role) {
        Ok(p) => p,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token":  pair.access_token,
            "refresh_token": pair.refresh_token,
            "token_type":    pair.token_type,
            "expires_in":    pair.expires_in,
            "user": {
                "user_id":      identity_id,
                "tenant_id":    tenant_id,
                "tenant_name":  tenant_name,
                "email":        email,
                "display_name": display_name,
                "role":         role,
            }
        }
    })))
        .into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/change-password
// ─────────────────────────────────────────────────────────────────────────────

pub async fn change_password(
    State(state):            State<Arc<AppState>>,
    axum::Extension(claims): axum::Extension<nexus_auth::Claims>,
    headers:                 HeaderMap,
    Json(req):               Json<ChangePasswordRequest>,
) -> Response {
    if req.new_password.len() < 8 {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "new password must be at least 8 characters" })),
        )
        .into_response();
    }

    // Prefer x-user-id injected by the gateway's inject_user_context middleware:
    // when the gateway forwards with service-to-service auth, claims.sub is the
    // synthetic "service-account" identity — the real user ID arrives in x-user-id.
    let identity_id_owned = headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty() && *s != "service-account")
        .map(|s| s.to_string())
        .unwrap_or_else(|| claims.sub.clone());
    let identity_id = identity_id_owned.as_str();

    let row = match sqlx::query(
        "SELECT password_hash FROM core_mdm.identities WHERE identity_id = $1",
    )
    .bind(identity_id)
    .fetch_optional(&state.db)
    .await
    {
        Ok(Some(r)) => r,
        Ok(None) => {
            return (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "user not found" }))).into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "DB error fetching identity for change-password");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "server error" }))).into_response();
        }
    };

    let stored_hash: String = row.get("password_hash");

    match verify_password(&req.current_password, &stored_hash) {
        Ok(true) => {}
        Ok(false) => {
            return (StatusCode::UNAUTHORIZED, Json(json!({ "success": false, "error": "current password is incorrect" }))).into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "password verify error");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "server error" }))).into_response();
        }
    }

    let new_hash = match hash_password(&req.new_password) {
        Ok(h) => h,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.identities SET password_hash = $1, updated_at = NOW() WHERE identity_id = $2",
    )
    .bind(&new_hash)
    .bind(identity_id)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to update password");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to update password" }))).into_response();
    }

    tracing::info!(identity_id=%identity_id, "password changed");

    if let Ok(actor_uuid) = Uuid::parse_str(identity_id) {
        state.audit_service.log_background(AuditEvent {
            tenant_id:     headers
                .get("x-tenant-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| Uuid::parse_str(s).ok())
                .unwrap_or(Uuid::nil()),
            event_type:    "user.password_changed".to_string(),
            actor_id:      Some(actor_uuid),
            resource_type: "identity".to_string(),
            resource_id:   identity_id.to_string(),
            metadata:      json!({}),
            before:        None,
            after:         None,
        });
    }

    (StatusCode::OK, Json(json!({ "success": true }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/forgot-password
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ForgotPasswordRequest {
    pub email: String,
}

pub async fn request_password_reset(
    State(state): State<Arc<AppState>>,
    headers:      HeaderMap,
    Json(req):    Json<ForgotPasswordRequest>,
) -> Response {
    let email = req.email.trim().to_lowercase();

    let tenant_id = headers
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    let Some(tenant_id) = tenant_id else {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "x-tenant-id header required" }))).into_response();
    };

    // Always return 200 — no email enumeration
    let row = sqlx::query(
        r#"
        SELECT i.identity_id, i.display_name
        FROM   core_mdm.identities i
        JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
        WHERE  i.email     = $1
          AND  m.tenant_id = $2
          AND  m.status   != 'deactivated'
        LIMIT 1
        "#,
    )
    .bind(&email)
    .bind(tenant_id)
    .fetch_optional(&state.db)
    .await;

    let (identity_id, display_name) = match row {
        Ok(Some(r)) => (r.get::<Uuid, _>("identity_id"), r.get::<String, _>("display_name")),
        Ok(None) => {
            tracing::info!(email=%email, "password reset requested for unknown email");
            return (StatusCode::OK, Json(json!({ "success": true }))).into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "db error looking up identity for password reset");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "internal error" }))).into_response();
        }
    };

    let token: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(64)
        .map(char::from)
        .collect();

    let expires_at = Utc::now() + chrono::Duration::hours(1);

    let _ = sqlx::query(
        "DELETE FROM core_mdm.password_resets WHERE identity_id = $1 AND used_at IS NULL",
    )
    .bind(identity_id)
    .execute(&state.db)
    .await;

    if let Err(e) = sqlx::query(
        "INSERT INTO core_mdm.password_resets (identity_id, tenant_id, token, expires_at) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(identity_id)
    .bind(tenant_id)
    .bind(&token)
    .bind(expires_at)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to store password reset token");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "internal error" }))).into_response();
    }

    // Fire-and-forget reset email
    {
        let notif_url = std::env::var("NOTIFICATION_SERVICE_URL")
            .unwrap_or_else(|_| "http://localhost:8086".to_string());
        let app_url = std::env::var("APP_URL")
            .unwrap_or_else(|_| "http://localhost:3000".to_string());
        let reset_url = format!("{}/reset-password?token={}", app_url, token);
        let email_to  = email.clone();

        tokio::spawn(async move {
            let body = serde_json::json!({
                "to":        email_to,
                "name":      display_name,
                "reset_url": reset_url,
            });
            match reqwest::Client::new()
                .post(format!("{}/internal/emails/reset-password", notif_url))
                .json(&body)
                .send()
                .await
            {
                Ok(r) if r.status().is_success() =>
                    tracing::info!(to=%body["to"], "password reset email dispatched"),
                Ok(r) =>
                    tracing::warn!(status=%r.status(), to=%body["to"], "reset email endpoint returned error"),
                Err(e) =>
                    tracing::warn!(error=%e, to=%body["to"], "failed to reach notification service for reset email"),
            }
        });
    }

    tracing::info!(identity_id=%identity_id, "password reset token created");
    (StatusCode::OK, Json(json!({ "success": true }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/reset-password
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ResetPasswordRequest {
    pub token:        String,
    pub new_password: String,
}

pub async fn reset_password(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<ResetPasswordRequest>,
) -> Response {
    if req.new_password.len() < 8 {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "password must be at least 8 characters" }))).into_response();
    }

    let row = sqlx::query(
        "SELECT id, identity_id FROM core_mdm.password_resets \
         WHERE token = $1 AND used_at IS NULL AND expires_at > NOW() LIMIT 1",
    )
    .bind(&req.token)
    .fetch_optional(&state.db)
    .await;

    let (reset_id, identity_id) = match row {
        Ok(Some(r)) => (r.get::<Uuid, _>("id"), r.get::<Uuid, _>("identity_id")),
        Ok(None) => {
            return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "invalid or expired reset token" }))).into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "db error looking up reset token");
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "internal error" }))).into_response();
        }
    };

    let new_hash = match hash_password(&req.new_password) {
        Ok(h) => h,
        Err(e) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response();
        }
    };

    if let Err(e) = sqlx::query(
        "UPDATE core_mdm.identities SET password_hash = $1, updated_at = NOW() WHERE identity_id = $2",
    )
    .bind(&new_hash)
    .bind(identity_id)
    .execute(&state.db)
    .await
    {
        tracing::error!(error=%e, "failed to reset password");
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": "failed to update password" }))).into_response();
    }

    let _ = sqlx::query("UPDATE core_mdm.password_resets SET used_at = NOW() WHERE id = $1")
        .bind(reset_id)
        .execute(&state.db)
        .await;

    tracing::info!(identity_id=%identity_id, "password reset successfully");
    (StatusCode::OK, Json(json!({ "success": true }))).into_response()
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /auth/sso-exchange
//
// Validates an OAuth2 access token from a third-party OIDC provider by calling
// the provider's userinfo endpoint. On success it looks up the pre-registered
// user by email, verifies active membership, and issues Nexus JWT tokens.
//
// This endpoint intentionally does NOT auto-provision users. An admin must
// first invite the user (POST /admin/users/invite) so the account exists in
// the identity store. This matches enterprise expectations: SSO replaces the
// password, it does not bypass the provisioning step.
//
// Supported providers:
//   google — https://www.googleapis.com/oauth2/v3/userinfo
//   azure  — https://graph.microsoft.com/oidc/userinfo
//   okta   — {OKTA_ISSUER}/v1/userinfo  (set OKTA_ISSUER env var)
// ─────────────────────────────────────────────────────────────────────────────

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct SsoExchangeRequest {
    pub provider:     String,       // "google" | "azure" | "okta"
    pub access_token: String,
    pub tenant_id:    Option<Uuid>, // hint — used when provided, otherwise resolved from email
}

pub async fn sso_exchange(
    State(state): State<Arc<AppState>>,
    Json(req):    Json<SsoExchangeRequest>,
) -> Response {
    let provider = req.provider.trim().to_lowercase();

    if req.access_token.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "access_token required" })),
        ).into_response();
    }

    // ── 1. Call provider's userinfo endpoint ──────────────────────────────────
    let userinfo_url = match provider.as_str() {
        "google" => "https://www.googleapis.com/oauth2/v3/userinfo".to_string(),
        "azure"  => "https://graph.microsoft.com/oidc/userinfo".to_string(),
        "okta"   => {
            let issuer = std::env::var("OKTA_ISSUER").unwrap_or_default();
            if issuer.is_empty() {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "success": false, "error": "OKTA_ISSUER not configured on the server" })),
                ).into_response();
            }
            format!("{}/v1/userinfo", issuer.trim_end_matches('/'))
        }
        other => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": format!("unsupported SSO provider '{other}'") })),
            ).into_response();
        }
    };

    let http = reqwest::Client::new();
    let userinfo_resp = match http
        .get(&userinfo_url)
        .bearer_auth(&req.access_token)
        .send()
        .await
    {
        Ok(r)  => r,
        Err(e) => {
            tracing::error!(provider=%provider, error=%e, "userinfo request failed");
            return (
                StatusCode::BAD_GATEWAY,
                Json(json!({ "success": false, "error": "could not reach SSO provider to validate token" })),
            ).into_response();
        }
    };

    if !userinfo_resp.status().is_success() {
        tracing::warn!(provider=%provider, status=%userinfo_resp.status(), "userinfo request rejected");
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "success": false, "error": "SSO token was rejected by the provider — please try again" })),
        ).into_response();
    }

    let userinfo: serde_json::Value = match userinfo_resp.json().await {
        Ok(v)  => v,
        Err(e) => {
            tracing::error!(provider=%provider, error=%e, "failed to parse userinfo response");
            return (
                StatusCode::BAD_GATEWAY,
                Json(json!({ "success": false, "error": "unexpected response from SSO provider" })),
            ).into_response();
        }
    };

    // ── 2. Extract email from userinfo claims ──────────────────────────────────
    let email = userinfo
        .get("email")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty());

    let email = match email {
        Some(e) => e,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({ "success": false, "error": "SSO provider did not return an email address — ensure the 'email' scope is granted" })),
            ).into_response();
        }
    };

    // ── 3. Look up identity + membership in the DB ─────────────────────────────
    // If the caller gave us a tenant_id hint, use it directly.
    // Otherwise, resolve to the most recent active membership for this email.
    let row = if let Some(tenant_id) = req.tenant_id {
        sqlx::query(
            r#"
            SELECT i.identity_id, i.display_name,
                   m.tenant_id, m.role, m.status,
                   t.display_name AS tenant_name
            FROM   core_mdm.identities i
            JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
            JOIN   core_mdm.tenants t            ON t.tenant_id   = m.tenant_id
            WHERE  i.email     = $1
              AND  m.tenant_id = $2
              AND  m.status    = 'active'
            LIMIT  1
            "#,
        )
        .bind(&email)
        .bind(tenant_id)
        .fetch_optional(&state.db)
        .await
    } else {
        sqlx::query(
            r#"
            SELECT i.identity_id, i.display_name,
                   m.tenant_id, m.role, m.status,
                   t.display_name AS tenant_name
            FROM   core_mdm.identities i
            JOIN   core_mdm.tenant_memberships m ON m.identity_id = i.identity_id
            JOIN   core_mdm.tenants t            ON t.tenant_id   = m.tenant_id
            WHERE  i.email  = $1
              AND  m.status = 'active'
            ORDER  BY m.joined_at DESC
            LIMIT  1
            "#,
        )
        .bind(&email)
        .fetch_optional(&state.db)
        .await
    };

    let row = match row {
        Ok(Some(r)) => r,
        Ok(None) => {
            tracing::info!(email=%email, provider=%provider, "SSO login for unknown user");
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({
                    "success": false,
                    "error":   "No active account found for this email address. Contact your administrator to be invited to Nexus AI MDM."
                })),
            ).into_response();
        }
        Err(e) => {
            tracing::error!(error=%e, "DB error during SSO exchange lookup");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "authentication service error" })),
            ).into_response();
        }
    };

    let identity_id: Uuid   = row.try_get("identity_id").unwrap();
    let tenant_id:   Uuid   = row.try_get("tenant_id").unwrap();
    let display_name: String = row.try_get("display_name").unwrap_or_default();
    let role_str:    String  = row.try_get("role").unwrap_or_else(|_| "steward".to_string());
    let tenant_name: String  = row.try_get("tenant_name").unwrap_or_default();

    let role: Role = role_str.parse().unwrap_or(Role::Steward);

    let cfg = match JwtConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response();
        }
    };

    let pair = match issue_tokens(&cfg, identity_id, tenant_id, &email, role) {
        Ok(p) => p,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response();
        }
    };

    let _ = sqlx::query(
        "UPDATE core_mdm.identities SET last_login_at = NOW() WHERE identity_id = $1",
    )
    .bind(identity_id)
    .execute(&state.db)
    .await;

    tracing::info!(
        identity_id=%identity_id,
        tenant_id=%tenant_id,
        provider=%provider,
        "user logged in via SSO"
    );

    (StatusCode::OK, Json(json!({
        "success": true,
        "data": {
            "access_token":  pair.access_token,
            "refresh_token": pair.refresh_token,
            "token_type":    pair.token_type,
            "expires_in":    pair.expires_in,
            "user": {
                "user_id":      identity_id,
                "tenant_id":    tenant_id,
                "tenant_name":  tenant_name,
                "email":        email,
                "display_name": display_name,
                "role":         role_str,
            }
        }
    }))).into_response()
}
