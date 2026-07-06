use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use nexus_auth::{Claims, Role};

/// Block `SuperAdmin` (the platform IT admin / Product Admin role) from reaching
/// any tenant-data endpoint.
///
/// SuperAdmin is the internal operator role: they manage tenants and licenses
/// but must never see tenant entity data, match queues, or golden records.
/// This guard is applied to the tenant-data router group in main.rs.
///
/// Service-to-service calls (API_BEARER_TOKEN without JWT claims) are allowed
/// through because they originate from trusted internal services, not end users.
pub async fn block_super_admin(
    request: Request,
    next:    Next,
) -> Response {
    if let Some(claims) = request.extensions().get::<Claims>() {
        if claims.nxs_role == Role::SuperAdmin {
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "product admin role does not have access to tenant data — \
                               use a tenant admin or steward account to access this resource"
                })),
            )
                .into_response();
        }
    }
    next.run(request).await
}

/// Require `SuperAdmin` role for platform-level administration routes.
///
/// This protects routes that manage tenants and platform-wide users — operations
/// that only the internal IT team (Product Admin) should perform.
/// Regular tenant admins and stewards are rejected with 403.
///
/// Service-to-service calls (no JWT claims) are allowed through.
pub async fn require_super_admin(
    request: Request,
    next:    Next,
) -> Response {
    if let Some(claims) = request.extensions().get::<Claims>() {
        if claims.nxs_role != Role::SuperAdmin {
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "this endpoint requires product admin privileges"
                })),
            )
                .into_response();
        }
    }
    next.run(request).await
}

/// Require at least `Admin` role for tenant administration routes.
///
/// Applied to routes like entity-types, source-systems, and user management that
/// only a Business Admin (or higher) should perform within their tenant.
#[allow(dead_code)]
pub async fn require_admin(
    request: Request,
    next:    Next,
) -> Response {
    if let Some(claims) = request.extensions().get::<Claims>() {
        if !claims.nxs_role.can_admin() {
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "admin role required for this operation"
                })),
            )
                .into_response();
        }
    }
    next.run(request).await
}

/// Require at least `Steward` or `BusinessAdmin` for match approve/reject.
///
/// BusinessAdmin has data-governance oversight authority and can approve or reject
/// match candidates without being a full data steward (they cannot create or edit
/// entity records directly).
pub async fn require_approve(
    request: Request,
    next:    Next,
) -> Response {
    if let Some(claims) = request.extensions().get::<Claims>() {
        if !claims.nxs_role.can_approve() {
            tracing::warn!(
                role = %claims.nxs_role,
                user = %claims.sub,
                path = %request.uri().path(),
                "steward or business_admin role required — access denied"
            );
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "data steward or business admin role is required to approve or reject matches"
                })),
            )
                .into_response();
        }
    }
    next.run(request).await
}

/// Require at least `Steward` role for data-mutation operations.
///
/// Applied to merge and bulk match operations that permanently alter master data.
/// BusinessAdmin, Viewers and Analysts are rejected — they can read but not mutate.
pub async fn require_steward(
    request: Request,
    next:    Next,
) -> Response {
    if let Some(claims) = request.extensions().get::<Claims>() {
        if !claims.nxs_role.can_write() {
            tracing::warn!(
                role = %claims.nxs_role,
                user = %claims.sub,
                path = %request.uri().path(),
                "steward role required — access denied"
            );
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "success": false,
                    "error":   "data steward role or higher is required to perform this operation"
                })),
            )
                .into_response();
        }
    }
    next.run(request).await
}
