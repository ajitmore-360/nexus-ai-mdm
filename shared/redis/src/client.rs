use anyhow::{Context, Result};
use deadpool_redis::{Config as DeadpoolConfig, Pool, Runtime};

pub type RedisPool = Pool;

#[derive(Debug, Clone)]
pub struct RedisConfig {
    pub url:          String,
    pub max_size:     usize,
    pub key_prefix:   String,
}

impl RedisConfig {
    pub fn from_env() -> Self {
        Self {
            url:        std::env::var("REDIS_URL")
                            .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),
            max_size:   std::env::var("REDIS_POOL_SIZE")
                            .ok()
                            .and_then(|v| v.parse().ok())
                            .unwrap_or(20),
            key_prefix: std::env::var("REDIS_KEY_PREFIX")
                            .unwrap_or_else(|_| "nexus".to_string()),
        }
    }
}

pub fn create_pool(config: &RedisConfig) -> Result<RedisPool> {
    let mut cfg = DeadpoolConfig::from_url(&config.url);
    cfg.pool = Some(deadpool_redis::PoolConfig {
        max_size: config.max_size,
        ..Default::default()
    });

    cfg.create_pool(Some(Runtime::Tokio1))
        .context("failed to create Redis connection pool")
}
