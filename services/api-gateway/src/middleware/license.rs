use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::{
    body::Body,
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use dashmap::DashMap;
use serde::Deserialize;
use uuid::Uuid;

use crate::{middleware::tenant::TenantContext, state::AppState};

const CACHE_TTL: Duration = Duration::from_secs(300); // 5 minutes

/// License information returned by mdm-core's /internal/license/{tenant_id} endpoint.
#[derive(Clone, Debug, Deserialize)]
pub struct LicenseCacheEntry {
    pub tier: String,
    pub features: serde_json::Value,
    pub max_records: i64,
    // Quota limits â€” deserialized for forward-compat; enforcement is handled by mdm-core.
    #[allow(dead_code)]
    pub max_domains: i32,
    #[allow(dead_code)]
    pub max_stewards: i32,
}

/// Outer wrapper matching the mdm-core response shape: `{ "license": {...}, "usage": {...} }`.
#[derive(Deserialize)]
struct LicenseApiResponse {
    license: LicenseCacheEntry,
}

/// In-process license cache type alias for use in AppState.
#[allow(dead_code)]
pub type LicenseCache = Arc<DashMap<Uuid, (LicenseCacheEntry, Instant)>>;

/// Returns the minimum tier required to use the given feature.
fn tier_for_feature(f: &str) -> &str {
    match f {
        "white_label" => "enterprise",
        _ => "professional",
    }
}

/// Determine the feature gate required for the given request path and method.
/// Returns `None` when no license gate applies.
///
/// Strips the `/v1` prefix before matching so this works for both versioned
/// (`/v1/copilot`) and unversioned (`/copilot`) paths.
fn required_feature(raw_path: &str, method: &axum::http::Method) -> Option<&'static str> {
    let path = raw_path.strip_prefix("/v1").unwrap_or(raw_path);

    if path.starts_with("/prism")
        || path.starts_with("/anomalies")
        || path.starts_with("/weights/recommend")
    {
        return Some("ai_copilot");
    }

    if (path.starts_with("/entities/") && path.contains("/relationships"))
        || path.starts_with("/relationships/")
        || path.starts_with("/relationship-types")
    {
        return Some("relationships");
    }

    if path.starts_with("/domain-policies") {
        return Some("domain_policies");
    }

    if path.starts_with("/distribution/") {
        return Some("distribution");
    }

    if path.starts_with("/analytics") {
        return Some("analytics");
    }

    if (path.starts_with("/governance") || path.starts_with("/audit"))
        && method == axum::http::Method::POST
    {
        return Some("governance");
    }

    // Only the write path is gated â€” tenants can always read their own branding.
    if path.starts_with("/tenant/branding")
        && (method == axum::http::Method::PUT || method == axum::http::Method::PATCH)
    {
        return Some("white_label");
    }

    None
}

/// Load the license entry for a tenant â€” from cache if fresh, or from mdm-core otherwise.
async fn load_license(
    tenant_id: Uuid,
    cache: &DashMap<Uuid, (LicenseCacheEntry, Instant)>,
    http_client: &reqwest::Client,
    mdm_core_url: &str,
) -> Result<LicenseCacheEntry, String> {
    // Check cache first.
    if let Some(entry) = cache.get(&tenant_id) {
        let (ref cached, ref ts) = *entry;
        if ts.elapsed() < CACHE_TTL {
            return Ok(cached.clone());
        }
    }

    // Fetch from mdm-core.
    let url = format!("{}/internal/license/{}", mdm_core_url, tenant_id);
    let response = http_client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("license fetch failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!(
            "license endpoint returned HTTP {}",
            response.status()
        ));
    }

    let body: LicenseApiResponse = response
        .json()
        .await
        .map_err(|e| format!("license parse failed: {}", e))?;

    let entry = body.license;
    cache.insert(tenant_id, (entry.clone(), Instant::now()));
    Ok(entry)
}

/// LicenseGuard middleware â€” gates feature access based on the tenant's license tier.
///
/// - Reads tenant_id from the TenantContext extension (injected by tenant_middleware).
/// - Determines which feature (if any) the current path requires.
/// - Fetches the license entry from mdm-core (with 5-minute in-process cache).
/// - Returns 402 Payment Required when the feature is not enabled on the license.
/// - Enterprise tenants (max_records == -1) bypass all feature checks.
pub async fn license_guard(
    State(state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    // Extract TenantContext â€” if missing, pass through (auth middleware will handle it).
    let tenant_id = match req.extensions().get::<TenantContext>() {
        Some(ctx) => ctx.tenant_id,
        None => return next.run(req).await,
    };

    // Determine the feature gate for this path + method.
    let path = req.uri().path().to_owned();
    let method = req.method().clone();
    let feature = required_feature(&path, &method);

    // No gate for this path â€” let it through immediately.
    let feature = match feature {
        Some(f) => f,
        None => return next.run(req).await,
    };

    // Fetch license (cached).
    let entry = match load_license(
        tenant_id,
        &state.license_cache,
        &state.http_client,
        &state.settings.mdm_core_url,
    )
    .await
    {
        Ok(e) => e,
        Err(err) => {
            // If we can't reach mdm-core, fail open with a 503 so the gateway
            // doesn't silently grant access on error.
            tracing::error!(
                tenant_id = %tenant_id,
                error = %err,
                "LicenseGuard: failed to load license â€” returning 503"
            );
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({
                    "success": false,
                    "error": "license_service_unavailable",
                    "message": "Unable to verify license. Please try again shortly."
                })),
            )
                .into_response();
        }
    };

    // Enterprise shortcut â€” max_records == -1 means unlimited / enterprise tier.
    if entry.max_records == -1 {
        return next.run(req).await;
    }

    // Check the specific feature flag.
    let is_licensed = entry
        .features
        .get(feature)
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !is_licensed {
        tracing::warn!(
            tenant_id = %tenant_id,
            tier = %entry.tier,
            feature = %feature,
            "LicenseGuard: feature not licensed â€” returning 402"
        );
        return (
            StatusCode::PAYMENT_REQUIRED,
            Json(serde_json::json!({
                "success": false,
                "error": "feature_not_licensed",
                "feature": feature,
                "upgrade_to": tier_for_feature(feature),
                "message": "This feature requires a Professional or higher subscription."
            })),
        )
            .into_response();
    }

    next.run(req).await
}
