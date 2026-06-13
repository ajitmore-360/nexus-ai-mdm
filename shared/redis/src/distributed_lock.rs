use std::time::Duration;

use anyhow::{anyhow, Result};
use deadpool_redis::Pool;
use redis::AsyncCommands;
use tracing::{debug, warn};
use uuid::Uuid;

const DEFAULT_LOCK_TTL_MS: u64  = 30_000; // 30 s
const DEFAULT_RETRY_COUNT: u32  = 3;
const DEFAULT_RETRY_DELAY_MS: u64 = 200;

/// A guard that releases the lock when dropped (via explicit `.release()`).
///
/// This is NOT auto-released on drop because async drop is not stable in Rust.
/// Always call `.release().await` when done with the critical section.
pub struct LockGuard {
    pool:  Pool,
    key:   String,
    token: String,
}

impl LockGuard {
    /// Release the distributed lock.
    /// Uses a Lua script to ensure only the owner can delete the key.
    pub async fn release(self) -> Result<()> {
        let script = r#"
            if redis.call('get', KEYS[1]) == ARGV[1] then
                return redis.call('del', KEYS[1])
            else
                return 0
            end
        "#;
        let mut conn = self.pool.get().await?;
        let result: i64 = redis::Script::new(script)
            .key(&self.key)
            .arg(&self.token)
            .invoke_async(&mut conn)
            .await?;

        if result == 0 {
            warn!(key=%self.key, "lock release: key was already expired or stolen");
        } else {
            debug!(key=%self.key, "lock released");
        }
        Ok(())
    }

    pub fn key(&self) -> &str {
        &self.key
    }
}

/// Single-node distributed lock using Redis SET NX PX.
///
/// For production use at scale, replace with a multi-node Redlock implementation.
/// For a single-Redis-primary setup (including Redis Sentinel) this provides
/// sufficient correctness guarantees.
#[derive(Clone)]
pub struct DistributedLock {
    pool:        Pool,
    prefix:      String,
    lock_ttl:    Duration,
    retry_count: u32,
    retry_delay: Duration,
}

impl DistributedLock {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self {
            pool,
            prefix:      prefix.into(),
            lock_ttl:    Duration::from_millis(DEFAULT_LOCK_TTL_MS),
            retry_count: DEFAULT_RETRY_COUNT,
            retry_delay: Duration::from_millis(DEFAULT_RETRY_DELAY_MS),
        }
    }

    pub fn with_ttl(mut self, ttl: Duration) -> Self {
        self.lock_ttl = ttl;
        self
    }

    pub fn with_retries(mut self, count: u32, delay: Duration) -> Self {
        self.retry_count = count;
        self.retry_delay  = delay;
        self
    }

    /// Try to acquire the lock for `resource`. Retries `retry_count` times.
    ///
    /// Returns `Ok(LockGuard)` on success, `Err` if the lock is held throughout.
    pub async fn acquire(&self, resource: &str) -> Result<LockGuard> {
        let key   = self.lock_key(resource);
        let token = Uuid::new_v4().to_string();

        for attempt in 0..=self.retry_count {
            if attempt > 0 {
                tokio::time::sleep(self.retry_delay).await;
            }

            let mut conn = self.pool.get().await?;
            let acquired: bool = conn
                .set_options(
                    &key,
                    &token,
                    redis::SetOptions::default()
                        .conditional_set(redis::ExistenceCheck::NX)
                        .get(false)
                        .with_expiration(redis::SetExpiry::PX(
                            self.lock_ttl.as_millis() as usize
                        )),
                )
                .await
                .map(|r: Option<String>| r.is_some())
                .unwrap_or(false);

            if acquired {
                debug!(key=%key, attempt, "distributed lock acquired");
                return Ok(LockGuard {
                    pool:  self.pool.clone(),
                    key,
                    token,
                });
            }
        }

        Err(anyhow!(
            "could not acquire distributed lock for '{}' after {} retries",
            resource,
            self.retry_count
        ))
    }

    /// Acquire the lock or return `None` immediately (non-blocking).
    pub async fn try_acquire(&self, resource: &str) -> Result<Option<LockGuard>> {
        let key   = self.lock_key(resource);
        let token = Uuid::new_v4().to_string();

        let mut conn = self.pool.get().await?;
        let acquired: bool = conn
            .set_options(
                &key,
                &token,
                redis::SetOptions::default()
                    .conditional_set(redis::ExistenceCheck::NX)
                    .get(false)
                    .with_expiration(redis::SetExpiry::PX(
                        self.lock_ttl.as_millis() as usize
                    )),
            )
            .await
            .map(|r: Option<String>| r.is_some())
            .unwrap_or(false);

        if acquired {
            Ok(Some(LockGuard {
                pool: self.pool.clone(),
                key,
                token,
            }))
        } else {
            Ok(None)
        }
    }

    fn lock_key(&self, resource: &str) -> String {
        format!("{}:lock:{}", self.prefix, resource)
    }
}
