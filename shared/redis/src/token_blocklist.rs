use std::time::Duration;

use anyhow::Result;
use deadpool_redis::Pool;
use redis::AsyncCommands;
use uuid::Uuid;

/// Redis-backed JWT revocation blocklist.
///
/// When a token is revoked (logout, forced expiry), its JTI is added with a
/// TTL equal to the token's remaining lifetime.  The auth middleware checks
/// this list before admitting requests.  Only revoked tokens are stored —
/// the happy path (no entry in Redis) requires zero round-trips.
///
/// Key format: `{prefix}:blocked_jti:{jti}`
#[derive(Clone)]
pub struct TokenBlocklist {
    pool:   Pool,
    prefix: String,
}

impl TokenBlocklist {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self { pool, prefix: prefix.into() }
    }

    /// Revoke a token by its JTI.  `ttl` should be the token's remaining
    /// validity period so the entry auto-expires once the token would have
    /// expired anyway.
    pub async fn revoke(&self, jti: Uuid, ttl: Duration) -> Result<()> {
        let key = self.key(jti);
        let mut conn = self.pool.get().await?;
        let _: () = conn.set_ex(&key, 1u8, ttl.as_secs()).await?;
        Ok(())
    }

    /// Returns `true` if the JTI has been revoked.
    pub async fn is_revoked(&self, jti: Uuid) -> Result<bool> {
        let key = self.key(jti);
        let mut conn = self.pool.get().await?;
        let exists: bool = conn.exists(&key).await?;
        Ok(exists)
    }

    fn key(&self, jti: Uuid) -> String {
        format!("{}:blocked_jti:{}", self.prefix, jti)
    }
}
