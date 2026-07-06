use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

// Import the same AppState the router is built with.
// It lives in main.rs as a private struct, so we re-declare the pool access
// via the public field — but AppState is in the same crate so we just need
// to reference `crate::AppState` from this sub-module.
use crate::AppState;

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST / RESPONSE TYPES
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CreateTenantRequest {
    pub name:         String,
    pub subdomain:    String,
    pub plan:         Option<String>,
    // Accepted for API completeness; enforced by the billing layer, not the DB layer.
    #[allow(dead_code)]
    pub max_users:    Option<i32>,
    #[allow(dead_code)]
    pub max_entities: Option<i64>,
    #[allow(dead_code)]
    pub region:       Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateAdminUserRequest {
    pub email:     String,
    pub full_name: String,
    // Reserved for future password-reset flows; not stored here (auth service owns passwords).
    #[allow(dead_code)]
    pub temp_password: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ListUsersParams {
    pub tenant_id: Uuid,
    pub limit:     Option<i64>,
    pub offset:    Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct InviteUserRequest {
    pub tenant_id: Option<Uuid>, // optional — falls back to x-tenant-id header
    pub email:     String,
    pub full_name: Option<String>,
    pub role:      Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateRoleRequest {
    pub role: String,
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Validate that a role string is one of the recognised values.
fn validate_role(role: &str) -> Result<(), String> {
    match role {
        "super_admin" | "admin" | "steward" | "analyst" | "viewer" => Ok(()),
        _ => Err(format!(
            "invalid role '{}': must be one of super_admin, admin, steward, analyst, viewer",
            role
        )),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS
// ─────────────────────────────────────────────────────────────────────────────

/// GET /admin/tenants — list all tenants (super admin only)
///
/// Reads from `core_mdm.tenants`.  If that table does not yet exist the
/// handler returns an empty array rather than crashing.
pub async fn list_tenants(State(state): State<AppState>) -> Json<serde_json::Value> {
    let pool = &state.pool;

    // Guard: check the table exists before querying.
    let table_exists: bool = match sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS (
             SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'core_mdm' AND table_name = 'tenants'
         )",
    )
    .fetch_one(pool)
    .await
    {
        Ok(v) => v,
        Err(e) => return Json(json!({ "success": false, "error": e.to_string() })),
    };

    if !table_exists {
        return Json(json!({ "success": true, "data": [] }));
    }

    match sqlx::query_as::<_, (Uuid, String, String, Option<String>, String, chrono::DateTime<chrono::Utc>)>(
        "SELECT tenant_id, tenant_code, display_name, plan, status, created_at
         FROM core_mdm.tenants
         ORDER BY created_at DESC
         LIMIT 1000",
    )
    .fetch_all(pool)
    .await
    {
        Ok(rows) => {
            let tenants: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|(id, code, name, plan, status, created_at)| {
                    json!({
                        "tenant_id":   id,
                        "tenant_code": code,
                        "name":        name,
                        "plan":        plan,
                        "status":      status,
                        "created_at":  created_at,
                    })
                })
                .collect();
            Json(json!({ "success": true, "data": tenants }))
        }
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /admin/tenants — create a new tenant
///
/// Inserts into `core_mdm.tenants` using the same schema as the onboarding
/// service so the record is consistent with the rest of the platform.
pub async fn create_tenant(
    State(state): State<AppState>,
    Json(body): Json<CreateTenantRequest>,
) -> Json<serde_json::Value> {
    if body.name.trim().is_empty() {
        return Json(json!({ "success": false, "error": "name is required" }));
    }
    if body.subdomain.trim().is_empty() {
        return Json(json!({ "success": false, "error": "subdomain is required" }));
    }

    let plan      = body.plan.as_deref().unwrap_or("enterprise");
    let tenant_id = Uuid::new_v4();

    match sqlx::query(
        "INSERT INTO core_mdm.tenants (
             tenant_id, tenant_code, display_name, plan, status,
             settings, features, created_at, updated_at
         ) VALUES (
             $1, $2, $3, $4, 'active',
             '{}',
             '{\"ai_matching\":true,\"rag_copilot\":true,\"vector_blocking\":true}',
             NOW(), NOW()
         )",
    )
    .bind(tenant_id)
    .bind(&body.subdomain)
    .bind(&body.name)
    .bind(plan)
    .execute(&state.pool)
    .await
    {
        Ok(_) => Json(json!({
            "success": true,
            "data": {
                "tenant_id":   tenant_id,
                "tenant_code": body.subdomain,
                "name":        body.name,
                "plan":        plan,
                "status":      "active",
            }
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /admin/tenants/:id/admin-user — bootstrap the first admin user for a tenant
///
/// Inserts into `platform.tenant_users` with role='admin' and status='active'.
pub async fn create_admin_user(
    State(state): State<AppState>,
    Path(tenant_id): Path<Uuid>,
    Json(body): Json<CreateAdminUserRequest>,
) -> Json<serde_json::Value> {
    if body.email.trim().is_empty() {
        return Json(json!({ "success": false, "error": "email is required" }));
    }
    if body.full_name.trim().is_empty() {
        return Json(json!({ "success": false, "error": "full_name is required" }));
    }

    let user_id = Uuid::new_v4();

    match sqlx::query(
        "INSERT INTO platform.tenant_users (
             id, tenant_id, email, full_name, role, status, created_at, updated_at
         ) VALUES (
             $1, $2, $3, $4, 'admin', 'active', NOW(), NOW()
         )
         ON CONFLICT (tenant_id, email) DO UPDATE
             SET role       = 'admin',
                 status     = 'active',
                 updated_at = NOW()",
    )
    .bind(user_id)
    .bind(tenant_id)
    .bind(&body.email)
    .bind(&body.full_name)
    .execute(&state.pool)
    .await
    {
        Ok(_) => Json(json!({
            "success": true,
            "data": {
                "user_id":   user_id,
                "tenant_id": tenant_id,
                "email":     body.email,
                "full_name": body.full_name,
                "role":      "admin",
                "status":    "active",
            }
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /admin/users?tenant_id=&limit=&offset= — list users for a tenant
pub async fn list_users(
    State(state): State<AppState>,
    Query(params): Query<ListUsersParams>,
) -> Json<serde_json::Value> {
    let limit  = params.limit.unwrap_or(50).min(500);
    let offset = params.offset.unwrap_or(0).max(0);

    match sqlx::query_as::<_, (
        Uuid, Uuid, String, String, String, String,
        Option<chrono::DateTime<chrono::Utc>>,
        chrono::DateTime<chrono::Utc>,
    )>(
        "SELECT id, tenant_id, email, full_name, role, status, last_login_at, created_at
         FROM platform.tenant_users
         WHERE tenant_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3",
    )
    .bind(params.tenant_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.pool)
    .await
    {
        Ok(rows) => {
            let users: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|(id, tid, email, full_name, role, status, last_login_at, created_at)| {
                    json!({
                        "user_id":       id,
                        "tenant_id":     tid,
                        "email":         email,
                        "full_name":     full_name,
                        "role":          role,
                        "status":        status,
                        "last_login_at": last_login_at,
                        "created_at":    created_at,
                    })
                })
                .collect();
            Json(json!({ "success": true, "data": users }))
        }
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /admin/users/invite — invite a user to a tenant
///
/// Inserts into `platform.tenant_users` with status='invited' and a random
/// invite token (valid for 7 days).
pub async fn invite_user(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<InviteUserRequest>,
) -> Json<serde_json::Value> {
    // tenant_id: prefer body field, fall back to x-tenant-id header
    let tenant_id = match body.tenant_id.or_else(|| {
        headers.get("x-tenant-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
    }) {
        Some(id) => id,
        None => return Json(json!({ "success": false, "error": "tenant_id is required" })),
    };

    if body.email.trim().is_empty() {
        return Json(json!({ "success": false, "error": "email is required" }));
    }

    let role = body.role.as_deref().unwrap_or("viewer");
    if let Err(e) = validate_role(role) {
        return Json(json!({ "success": false, "error": e }));
    }

    let user_id      = Uuid::new_v4();
    let invite_token = Uuid::new_v4().to_string();
    let full_name    = body.full_name.as_deref().unwrap_or("").to_string();

    match sqlx::query(
        "INSERT INTO platform.tenant_users (
             id, tenant_id, email, full_name, role,
             invite_token, invite_expires,
             status, created_at, updated_at
         ) VALUES (
             $1, $2, $3, $4, $5,
             $6, NOW() + INTERVAL '7 days',
             'invited', NOW(), NOW()
         )
         ON CONFLICT (tenant_id, email) DO UPDATE
             SET role           = EXCLUDED.role,
                 invite_token   = EXCLUDED.invite_token,
                 invite_expires = NOW() + INTERVAL '7 days',
                 status         = 'invited',
                 updated_at     = NOW()",
    )
    .bind(user_id)
    .bind(tenant_id)
    .bind(&body.email)
    .bind(&full_name)
    .bind(role)
    .bind(&invite_token)
    .execute(&state.pool)
    .await
    {
        Ok(_) => Json(json!({
            "success": true,
            "data": {
                "user_id":      user_id,
                "tenant_id":    tenant_id,
                "email":        body.email,
                "full_name":    full_name,
                "role":         role,
                "status":       "invited",
                "invite_token": invite_token,
            }
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// PUT /admin/users/:id/role — update a user's role
pub async fn update_user_role(
    State(state): State<AppState>,
    Path(user_id): Path<Uuid>,
    Json(body): Json<UpdateRoleRequest>,
) -> Json<serde_json::Value> {
    if let Err(e) = validate_role(&body.role) {
        return Json(json!({ "success": false, "error": e }));
    }

    match sqlx::query_scalar::<_, Uuid>(
        "UPDATE platform.tenant_users
         SET role = $1, updated_at = NOW()
         WHERE id = $2
         RETURNING id",
    )
    .bind(&body.role)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some(id)) => Json(json!({
            "success": true,
            "data": {
                "user_id": id,
                "role":    body.role,
            }
        })),
        Ok(None) => Json(json!({
            "success": false,
            "error":   format!("user {} not found", user_id),
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}
