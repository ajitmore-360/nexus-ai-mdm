use anyhow::Result;
use deadpool_redis::Pool;
use tracing::debug;

/// Sliding-window rate limiter backed by Redis.
///
/// Uses a sorted set per client key.  Each request inserts a timestamped
/// member and removes entries older than the window.  The cardinality of the
/// set is the current request count.
///
/// A Lua script makes the whole operation atomic.
#[derive(Clone)]
pub struct RedisRateLimiter {
    pool:        Pool,
    prefix:      String,
    limit:       u64,
    window_secs: u64,
}

impl RedisRateLimiter {
    pub fn new(pool: Pool, prefix: impl Into<String>, limit: u64, window_secs: u64) -> Self {
        Self {
            pool,
            prefix: prefix.into(),
            limit,
            window_secs,
        }
    }

    /// Check whether `client_key` (e.g. IP address or user_id) is within the
    /// rate limit.
    ///
    /// Returns `Ok(true)` if the request is allowed, `Ok(false)` if throttled.
    pub async fn check(&self, client_key: &str) -> Result<bool> {
        let key = format!("{}:ratelimit:{}", self.prefix, client_key);

        let script = r#"
            local key        = KEYS[1]
            local now        = tonumber(ARGV[1])
            local window     = tonumber(ARGV[2])
            local limit      = tonumber(ARGV[3])
            local member     = ARGV[4]
            local cutoff     = now - window * 1000

            -- Remove entries outside the window
            redis.call('ZREMRANGEBYSCORE', key, '-inf', cutoff)

            local count = redis.call('ZCARD', key)

            if count >= limit then
                return 0
            end

            -- Record this request
            redis.call('ZADD', key, now, member)
            redis.call('PEXPIRE', key, window * 1000)

            return 1
        "#;

        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;

        let member = format!("{}:{}", now_ms, uuid::Uuid::new_v4());

        let mut conn = self.pool.get().await?;
        let allowed: i64 = redis::Script::new(script)
            .key(&key)
            .arg(now_ms)
            .arg(self.window_secs)
            .arg(self.limit)
            .arg(&member)
            .invoke_async(&mut conn)
            .await?;

        let ok = allowed == 1;
        if !ok {
            debug!(client=%client_key, "rate limit exceeded");
        }
        Ok(ok)
    }

    /// Return the remaining request budget for `client_key` in the current window.
    pub async fn remaining(&self, client_key: &str) -> Result<u64> {
        let key = format!("{}:ratelimit:{}", self.prefix, client_key);
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;
        let cutoff = now_ms.saturating_sub(self.window_secs * 1000);

        let mut conn = self.pool.get().await?;
        let _: () = redis::cmd("ZREMRANGEBYSCORE")
            .arg(&key)
            .arg("-inf")
            .arg(cutoff)
            .query_async(&mut conn)
            .await?;

        let count: u64 = redis::cmd("ZCARD")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .unwrap_or(0);

        Ok(self.limit.saturating_sub(count))
    }
}
