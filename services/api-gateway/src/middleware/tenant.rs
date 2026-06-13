use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct TenantContext {
    #[allow(dead_code)]
    pub tenant_id: Uuid,
}

/// Tenant context middleware — enforces that:
///
/// 1. `x-tenant-id` header is present and a valid UUID.
/// 2. If a validated JWT is present (injected by auth middleware as `nexus_auth::Claims`),
///    the tenant_id in the JWT **must match** the `x-tenant-id` header.
///    This prevents a valid token from one tenant being used to access another
///    tenant's data (horizontal privilege escalation / IDOR on multi-tenancy).
///
/// The check is skipped when `AUTH_DISABLED=true` (local dev only).
pub async fn tenant_middleware(
    mut request: Request,
    next: Next,
) -> Response {

    // Extract x-tenant-id header
    let tenant_id = match request
        .headers()
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "success": false,
                    "error": "x-tenant-id header is required and must be a valid UUID"
                })),
            )
                .into_response();
        }
    };

    // If a JWT is present, validate its tenant claim matches the header.
    // This prevents token-replay across tenants.
    let auth_disabled = std::env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if !auth_disabled {
        if let Some(claims) = request.extensions().get::<nexus_auth::Claims>() {
            if claims.nxs_tenant_id != tenant_id {
                tracing::warn!(
                    jwt_tenant  = %claims.nxs_tenant_id,
                    hdr_tenant  = %tenant_id,
                    user_id     = %claims.sub,
                    "tenant isolation violation: JWT tenant != x-tenant-id header"
                );
                return (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({
                        "success": false,
                        "error": "tenant ID in token does not match x-tenant-id header"
                    })),
                )
                    .into_response();
            }
        }
    }

    request.extensions_mut().insert(TenantContext { tenant_id });
    next.run(request).await
}
