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

pub async fn rate_limit_middleware(
    State(state): State<AppState>,
    req: Request<axum::body::Body>,
    next: Next,
) -> Response {
    let ip = req
        .headers()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

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
