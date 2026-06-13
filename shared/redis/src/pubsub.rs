use anyhow::Result;
use deadpool_redis::Pool;
use redis::AsyncCommands;
use serde::Serialize;
use tracing::debug;

/// Channel names for real-time notifications.
pub mod channels {
    pub const MATCH_DETECTED:    &str = "nexus:match:detected";
    pub const MERGE_COMPLETED:   &str = "nexus:merge:completed";
    pub const ENTITY_UPDATED:    &str = "nexus:entity:updated";
    pub const GOLDEN_PUBLISHED:  &str = "nexus:golden:published";
    pub const QUALITY_ALERT:     &str = "nexus:quality:alert";
    pub const REVIEW_ASSIGNED:   &str = "nexus:review:assigned";

    /// Tenant-scoped channel (all events for a specific tenant).
    pub fn tenant_channel(tenant_id: &str) -> String {
        format!("nexus:tenant:{}", tenant_id)
    }
}

/// Publisher — broadcasts JSON-serialised events to Redis Pub/Sub channels.
///
/// Subscribers (the notification-service WebSocket hub) listen on these
/// channels and forward events to connected Flutter clients.
#[derive(Clone)]
pub struct PubSubClient {
    pool:   Pool,
    #[allow(dead_code)]
    prefix: String,
}

impl PubSubClient {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self {
            pool,
            prefix: prefix.into(),
        }
    }

    /// Publish a JSON-serialisable event to a channel.
    pub async fn publish<T: Serialize>(&self, channel: &str, event: &T) -> Result<()> {
        let payload = serde_json::to_string(event)?;
        let mut conn = self.pool.get().await?;
        let _: i64 = conn.publish(channel, &payload).await?;
        debug!(%channel, "event published");
        Ok(())
    }

    /// Publish to the tenant-scoped channel (UI subscribes to this).
    pub async fn publish_to_tenant<T: Serialize>(
        &self,
        tenant_id: &str,
        event: &T,
    ) -> Result<()> {
        let channel = channels::tenant_channel(tenant_id);
        self.publish(&channel, event).await
    }

    /// Publish a raw string payload (e.g. pre-serialised JSON).
    pub async fn publish_raw(&self, channel: &str, payload: &str) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let _: i64 = conn.publish(channel, payload).await?;
        Ok(())
    }
}
