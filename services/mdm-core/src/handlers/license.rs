use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Extension,
    Json,
};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    middleware::tenant::TenantContext,
    AppState,
};

//
// ========================================
// REQUEST BODIES
// ========================================
//

#[derive(Debug, Deserialize)]
pub struct AdminLicenseBody {
    pub tier:  String,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ActivateLicenseBody {
    pub key: String,
}

//
// ========================================
// KEY â†’ TIER MAPPING (server-side only)
// ========================================
//
// These canonical key prefixes are validated on the server. The client never
// stores a local keyâ†’tier table — every key is authorised by this endpoint.
//

fn tier_from_key(key: &str) -> Option<&'static str> {
    let upper = key.trim().to_uppercase();
    // Environment-variable override: AZILE_LICENSE_MASTER_KEY=<key>:<tier>
    if let Ok(master) = std::env::var("AZILE_LICENSE_MASTER_KEY") {
        let parts: Vec<&str> = master.splitn(2, ':').collect();
        if parts.len() == 2 && parts[0] == upper {
            let tier = match parts[1] {
                "enterprise"   => "enterprise",
                "professional" => "professional",
                "trial"        => "trial",
                _              => "essentials",
            };
            return Some(tier);
        }
    }
    // Prefix-based tier assignment for well-known key formats.
    if upper.starts_with("NXS-ENT-") || upper.starts_with("NXS-FULL-") {
        Some("enterprise")
    } else if upper.starts_with("NXS-PRO-") {
        Some("professional")
    } else if upper.starts_with("NXS-TRIAL-") {
        Some("trial")
    } else {
        None
    }
}

//
// ========================================
// HELPERS
// ========================================
//

/// Build the combined license + usage JSON shape shared by the tenant
/// and internal endpoints.
async fn license_usage_json(
    state:     &AppState,
    tenant_id: Uuid,
) -> Result<serde_json::Value, (StatusCode, Json<serde_json::Value>)> {
    let license = state
        .license_service
        .get_license(tenant_id)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
        })?;

    let usage = state
        .license_service
        .get_usage(tenant_id)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
        })?;

    let license_json = match license {
        Some(l) => json!({
            "tier":         l.tier,
            "status":       l.status,
            "max_domains":  l.max_domains,
            "max_records":  l.max_records,
            "max_stewards": l.max_stewards,
            "features":     l.features,
            "expires_at":   l.expires_at,
        }),
        None => json!({
            "tier":         "essentials",
            "status":       "active",
            "max_domains":  1,
            "max_records":  500000,
            "max_stewards": 5,
            "features":     {},
            "expires_at":   null,
        }),
    };

    Ok(json!({
        "license": license_json,
        "usage": {
            "golden_records":  usage.golden_records,
            "active_domains":  usage.active_domains,
            "active_stewards": usage.active_stewards,
        }
    }))
}

//
// ========================================
// HANDLERS
// ========================================
//

/// GET /license
/// Returns the caller's tenant license and current usage counters.
pub async fn get_my_license(
    State(state):         State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match license_usage_json(&state, tenant_ctx.tenant_id).await {
        Ok(body)  => (StatusCode::OK, Json(body)).into_response(),
        Err(resp) => resp.into_response(),
    }
}

/// GET /internal/license/:tenant_id
/// No auth — internal gateway use only.
/// Returns the same license + usage shape for gateway feature-gating and caching.
pub async fn internal_get_license(
    State(state):          State<Arc<AppState>>,
    Path(tenant_id):       Path<Uuid>,
) -> impl IntoResponse {
    match license_usage_json(&state, tenant_id).await {
        Ok(body)  => (StatusCode::OK, Json(body)).into_response(),
        Err(resp) => resp.into_response(),
    }
}

/// POST /admin/tenants/:id/license
/// Admin-only: create or replace a tenant license, then trigger usage recompute.
pub async fn admin_upsert_license(
    State(state):    State<Arc<AppState>>,
    Path(tenant_id): Path<Uuid>,
    Json(body):      Json<AdminLicenseBody>,
) -> impl IntoResponse {
    let upsert_result = state
        .license_service
        .upsert_license(
            tenant_id,
            &body.tier,
            body.notes.as_deref(),
        )
        .await;

    let license_id = match upsert_result {
        Ok(id) => id,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            )
            .into_response();
        }
    };

    // Trigger usage recompute; log but do not fail the request if it errors.
    if let Err(e) = state
        .license_service
        .trigger_usage_recompute(tenant_id)
        .await
    {
        tracing::warn!(
            tenant_id = %tenant_id,
            error = %e,
            "Usage recompute trigger failed after license upsert"
        );
    }

    (
        StatusCode::OK,
        Json(json!({
            "success":    true,
            "license_id": license_id,
        })),
    )
    .into_response()
}

/// POST /license/activate
/// Tenant-initiated license key activation. Validates the key server-side
/// against the `tier_from_key` mapping (which checks the `AZILE_LICENSE_MASTER_KEY`
/// env override first, then well-known key prefixes). On success the tier is
/// upserted for the calling tenant and the updated license is returned.
pub async fn activate_license(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body):            Json<ActivateLicenseBody>,
) -> impl IntoResponse {
    let key = body.key.trim().to_uppercase();

    let tier = match tier_from_key(&key) {
        Some(t) => t,
        None => {
            return (
                StatusCode::PAYMENT_REQUIRED,
                Json(json!({
                    "success": false,
                    "error":   "Invalid or unrecognised license key. Contact support@nexusmdm.io for a valid key."
                })),
            ).into_response();
        }
    };

    match state.license_service.upsert_license(
        tenant_ctx.tenant_id,
        tier,
        Some(&format!("Activated via key {key}")),
    ).await {
        Ok(license_id) => {
            let _ = state.license_service.trigger_usage_recompute(tenant_ctx.tenant_id).await;
            (StatusCode::OK, Json(json!({
                "success":    true,
                "license_id": license_id,
                "tier":       tier,
            }))).into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    }
}
