use std::sync::Arc;

use dashmap::DashMap;
use azile_redis::{RedisRateLimiter, SessionStore, TokenBlocklist};
use uuid::Uuid;

use crate::{
    config::settings::Settings,
    middleware::{
        license::LicenseCacheEntry,
        rate_limit::InMemoryRateLimiter,
    },
    proxy::circuit_breaker::CircuitBreaker,
    services::ServiceClients,
    ws::manager::WsManager,
};

#[derive(Clone)]
pub struct AppState {
    pub settings:              Settings,
    pub services:              ServiceClients,
    /// In-memory fallback rate limiter (used when Redis is unavailable).
    pub rate_limiter:          InMemoryRateLimiter,
    /// Redis-backed rate limiter (preferred path).
    pub redis_rate_limiter:    Option<Arc<RedisRateLimiter>>,
    /// Redis-backed session store â€” reserved for stateful session management.
    #[allow(dead_code)]
    pub session_store:         Option<Arc<SessionStore>>,
    /// In-process license cache â€” keyed by tenant UUID, entries expire after 5 minutes.
    pub license_cache:         Arc<DashMap<Uuid, (LicenseCacheEntry, std::time::Instant)>>,
    /// Shared HTTP client for internal service calls (e.g. license endpoint).
    pub http_client:           Arc<reqwest::Client>,
    /// Tenant-aware WebSocket broadcast manager.
    pub ws_manager:            WsManager,
    /// Per-upstream circuit breakers.
    /// Opens after 5 consecutive failures; resets after 30 seconds.
    pub cb_mdm:                Arc<CircuitBreaker>,
    pub cb_ai:                 Arc<CircuitBreaker>,
    /// JWT revocation blocklist â€” stores JTIs of logged-out tokens until expiry.
    pub token_blocklist:       Option<Arc<TokenBlocklist>>,
}
