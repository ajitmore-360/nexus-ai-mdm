use std::sync::Arc;

use nexus_redis::{RedisRateLimiter, SessionStore};

use crate::{
    config::settings::Settings,
    middleware::rate_limit::InMemoryRateLimiter,
    services::ServiceClients,
};

#[derive(Clone)]
pub struct AppState {
    pub settings:              Settings,
    pub services:              ServiceClients,
    /// In-memory fallback rate limiter (used when Redis is unavailable).
    pub rate_limiter:          InMemoryRateLimiter,
    /// Redis-backed rate limiter (preferred path).
    pub redis_rate_limiter:    Option<Arc<RedisRateLimiter>>,
    /// Redis-backed session store — reserved for stateful session management.
    #[allow(dead_code)]
    pub session_store:         Option<Arc<SessionStore>>,
}
