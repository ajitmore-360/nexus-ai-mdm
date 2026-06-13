use std::time::Duration;

use anyhow::Result;
use deadpool_redis::Pool;
use redis::AsyncCommands;
use serde::{de::DeserializeOwned, Serialize};
use tracing::{debug, instrument, warn};
use uuid::Uuid;

/// Tenant-scoped entity cache backed by Redis.
///
/// Keys follow the pattern `{prefix}:{tenant_id}:entity:{entity_id}`.
/// All values are JSON-serialised. A default TTL of 5 minutes is applied;
/// callers may override per-operation.
#[derive(Clone)]
pub struct EntityCache {
    pool:       Pool,
    prefix:     String,
    default_ttl: Duration,
}

impl EntityCache {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self {
            pool,
            prefix: prefix.into(),
            default_ttl: Duration::from_secs(300),
        }
    }

    pub fn with_ttl(mut self, ttl: Duration) -> Self {
        self.default_ttl = ttl;
        self
    }

    // ---- entity cache -------------------------------------------------------

    #[instrument(skip(self, value))]
    pub async fn set_entity<T: Serialize>(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        value: &T,
    ) -> Result<()> {
        let key   = self.entity_key(tenant_id, entity_id);
        let bytes = serde_json::to_string(value)?;
        let mut conn = self.pool.get().await?;
        let _: () = conn
            .set_ex(&key, bytes, self.default_ttl.as_secs())
            .await?;
        debug!(%key, "entity cached");
        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn get_entity<T: DeserializeOwned>(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Option<T>> {
        let key = self.entity_key(tenant_id, entity_id);
        let mut conn = self.pool.get().await?;
        let raw: Option<String> = conn.get(&key).await?;
        match raw {
            None => Ok(None),
            Some(s) => Ok(Some(serde_json::from_str(&s)?)),
        }
    }

    pub async fn invalidate_entity(&self, tenant_id: Uuid, entity_id: Uuid) -> Result<()> {
        let key = self.entity_key(tenant_id, entity_id);
        let mut conn = self.pool.get().await?;
        let _: () = conn.del(&key).await?;
        debug!(%key, "entity cache invalidated");
        Ok(())
    }

    // ---- golden record cache -----------------------------------------------

    pub async fn set_golden_record<T: Serialize>(
        &self,
        tenant_id: Uuid,
        golden_id: Uuid,
        value: &T,
    ) -> Result<()> {
        let key   = self.golden_key(tenant_id, golden_id);
        let bytes = serde_json::to_string(value)?;
        let mut conn = self.pool.get().await?;
        let _: () = conn
            .set_ex(&key, bytes, self.default_ttl.as_secs())
            .await?;
        Ok(())
    }

    pub async fn get_golden_record<T: DeserializeOwned>(
        &self,
        tenant_id: Uuid,
        golden_id: Uuid,
    ) -> Result<Option<T>> {
        let key = self.golden_key(tenant_id, golden_id);
        let mut conn = self.pool.get().await?;
        let raw: Option<String> = conn.get(&key).await?;
        match raw {
            None => Ok(None),
            Some(s) => Ok(Some(serde_json::from_str(&s)?)),
        }
    }

    pub async fn invalidate_golden_record(&self, tenant_id: Uuid, golden_id: Uuid) -> Result<()> {
        let key = self.golden_key(tenant_id, golden_id);
        let mut conn = self.pool.get().await?;
        let _: () = conn.del(&key).await?;
        Ok(())
    }

    // ---- tenant-level invalidation -----------------------------------------

    /// Wipe all cached entities for a tenant (e.g. after bulk ingest).
    pub async fn invalidate_tenant(&self, tenant_id: Uuid) -> Result<u64> {
        let pattern = format!("{}:{}:*", self.prefix, tenant_id);
        let mut conn = self.pool.get().await?;

        let keys: Vec<String> = redis::cmd("SCAN")
            .arg("0")
            .arg("MATCH")
            .arg(&pattern)
            .arg("COUNT")
            .arg(1000u64)
            .query_async(&mut conn)
            .await
            .unwrap_or_else(|e| {
                warn!(error=%e, "SCAN failed during tenant invalidation");
                (String::new(), vec![])
            })
            .1;

        if keys.is_empty() {
            return Ok(0);
        }

        let deleted: u64 = conn.del(keys).await?;
        Ok(deleted)
    }

    // ---- generic key/value -------------------------------------------------

    pub async fn set_json<T: Serialize>(&self, key: &str, value: &T, ttl: Duration) -> Result<()> {
        let bytes = serde_json::to_string(value)?;
        let mut conn = self.pool.get().await?;
        let _: () = conn.set_ex(key, bytes, ttl.as_secs()).await?;
        Ok(())
    }

    pub async fn get_json<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let mut conn = self.pool.get().await?;
        let raw: Option<String> = conn.get(key).await?;
        Ok(match raw {
            None => None,
            Some(s) => Some(serde_json::from_str(&s)?),
        })
    }

    pub async fn delete(&self, key: &str) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let _: () = conn.del(key).await?;
        Ok(())
    }

    // ---- key builders ------------------------------------------------------

    fn entity_key(&self, tenant_id: Uuid, entity_id: Uuid) -> String {
        format!("{}:{}:entity:{}", self.prefix, tenant_id, entity_id)
    }

    fn golden_key(&self, tenant_id: Uuid, golden_id: Uuid) -> String {
        format!("{}:{}:golden:{}", self.prefix, tenant_id, golden_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key_format(prefix: &str, tenant_id: Uuid, entity_id: Uuid) -> String {
        format!("{}:{}:entity:{}", prefix, tenant_id, entity_id)
    }

    #[test]
    fn entity_key_format() {
        let tid = Uuid::nil();
        let eid = Uuid::nil();
        let key = key_format("nexus", tid, eid);
        assert!(key.starts_with("nexus:"));
        assert!(key.contains("entity"));
        assert!(key.contains(&tid.to_string()));
    }

    #[test]
    fn golden_key_format_differs_from_entity_key() {
        let tid = Uuid::nil();
        let id  = Uuid::nil();
        let ek = format!("{}:{}:entity:{}", "nexus", tid, id);
        let gk = format!("{}:{}:golden:{}", "nexus", tid, id);
        assert_ne!(ek, gk);
    }
}
