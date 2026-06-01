use axum::{
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    http::Request,
};

use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use tokio::sync::Mutex;

//
// =========================================
// SIMPLE IN-MEMORY RATE LIMITER
// =========================================
//

#[derive(Clone)]
pub struct RateLimiter {
    pub requests: Arc<Mutex<HashMap<String, Vec<Instant>>>>,
}

impl RateLimiter {

    pub fn new() -> Self {
        Self {
            requests: Arc::new(
                Mutex::new(HashMap::new())
            ),
        }
    }
}

//
// =========================================
// RATE LIMIT MIDDLEWARE
// =========================================
//

pub async fn rate_limit_middleware(
    req: Request<axum::body::Body>,
    next: Next,
) -> Response {

    let ip = req
        .headers()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    static LIMIT: usize = 100;
    static WINDOW_SECS: u64 = 60;

    let limiter = RateLimiter::new();

    let mut map = limiter.requests.lock().await;

    let now = Instant::now();

    let entries = map
        .entry(ip.clone())
        .or_insert_with(Vec::new);

    entries.retain(|t| {
        now.duration_since(*t)
            < Duration::from_secs(WINDOW_SECS)
    });

    if entries.len() >= LIMIT {

        return (
            StatusCode::TOO_MANY_REQUESTS,
            "rate limit exceeded",
        )
            .into_response();
    }

    entries.push(now);

    drop(map);

    next.run(req).await
}