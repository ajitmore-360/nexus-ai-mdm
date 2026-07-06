use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    extract::State,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    http::Request,
};
use tokio::sync::Mutex;

use crate::state::AppState;

const LIMIT: usize       = 100;
const WINDOW_SECS: u64   = 60;

/// Per-tenant limit on compute-heavy operations (match, merge, anomaly scan, etc.).
/// Lower than the general rate limit because these endpoints invoke ML scoring pipelines.
const OP_COST_LIMIT: usize  = 10;
const OP_COST_WINDOW: u64   = 60;

// ============================================================================
// IN-MEMORY FALLBACK (used when Redis is unavailable)
// ============================================================================

#[derive(Clone)]
pub struct InMemoryRateLimiter {
    pub requests: Arc<Mutex<HashMap<String, Vec<Instant>>>>,
}

impl InMemoryRateLimiter {
    pub fn new() -> Self {
        Self {
            requests: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

// ============================================================================
// MIDDLEWARE
// Uses Redis rate limiter if available, falls back to in-memory.
// ============================================================================

/// Extract the real client IP — never trust X-Forwarded-For (client-controlled).
/// Priority:
///   1. ConnectInfo<SocketAddr> — actual TCP peer from axum (most reliable)
///   2. X-Real-IP — set by a trusted ingress controller / nginx
///   3. "unknown" — fail-closed: a single bucket for unidentifiable clients
fn client_ip(req: &Request<axum::body::Body>) -> String {
    if let Some(ci) = req.extensions().get::<axum::extract::ConnectInfo<std::net::SocketAddr>>() {
        return ci.0.ip().to_string();
    }
    req.headers()
        .get("x-real-ip")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string()
}

pub async fn rate_limit_middleware(
    State(state): State<AppState>,
    req: Request<axum::body::Body>,
    next: Next,
) -> Response {
    let ip = client_ip(&req);

    // Prefer Redis-backed limiter
    if let Some(redis_limiter) = &state.redis_rate_limiter {
        match redis_limiter.check(&ip).await {
            Ok(true)  => return next.run(req).await,
            Ok(false) => return (StatusCode::TOO_MANY_REQUESTS, "rate limit exceeded").into_response(),
            Err(e)    => {
                tracing::warn!(error=%e, "Redis rate limiter error; falling back to in-memory");
            }
        }
    }

    // In-memory fallback
    let now     = Instant::now();
    let mut map = state.rate_limiter.requests.lock().await;
    let entries = map.entry(ip).or_insert_with(Vec::new);
    entries.retain(|t| now.duration_since(*t) < Duration::from_secs(WINDOW_SECS));

    if entries.len() >= LIMIT {
        return (StatusCode::TOO_MANY_REQUESTS, "rate limit exceeded").into_response();
    }

    entries.push(now);
    drop(map);

    next.run(req).await
}

// ============================================================================
// OPERATION-COST RATE LIMITER
// Per-tenant, tighter limits for compute-heavy endpoints (match, merge).
// ============================================================================

/// Apply per-tenant rate limiting for expensive compute operations.
///
/// Reads the `x-tenant-id` header injected by the tenant middleware and enforces
/// OP_COST_LIMIT (10) operations per OP_COST_WINDOW (60s) per tenant.
/// Falls back to per-IP keying when the header is absent.
pub async fn operation_cost_middleware(
    State(state): State<AppState>,
    req: Request<axum::body::Body>,
    next: Next,
) -> Response {
    // Prefer tenant-scoped key (validated by tenant middleware); fall back to
    // the real client IP — never trust X-Forwarded-For.
    let key = req
        .headers()
        .get("x-tenant-id")
        .and_then(|v| v.to_str().ok())
        .map(|t| format!("op:{}", t))
        .unwrap_or_else(|| format!("op:{}", client_ip(&req)));

    // Prefer Redis-backed limiter for cluster-safe counting.
    if let Some(redis_limiter) = &state.redis_rate_limiter {
        match redis_limiter.check(&key).await {
            Ok(true)  => return next.run(req).await,
            Ok(false) => {
                return (
                    StatusCode::TOO_MANY_REQUESTS,
                    axum::Json(serde_json::json!({
                        "success": false,
                        "error":   "operation rate limit exceeded",
                        "retry_after_secs": OP_COST_WINDOW,
                    })),
                ).into_response();
            }
            Err(e) => {
                tracing::warn!(error=%e, "Redis op-cost limiter error; falling back to in-memory");
            }
        }
    }

    // In-memory fallback (single-node only).
    let now     = Instant::now();
    let mut map = state.rate_limiter.requests.lock().await;
    let entries = map.entry(key).or_insert_with(Vec::new);
    entries.retain(|t| now.duration_since(*t) < Duration::from_secs(OP_COST_WINDOW));

    if entries.len() >= OP_COST_LIMIT {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            axum::Json(serde_json::json!({
                "success": false,
                "error":   "operation rate limit exceeded",
                "retry_after_secs": OP_COST_WINDOW,
            })),
        ).into_response();
    }

    entries.push(now);
    drop(map);

    next.run(req).await
}
