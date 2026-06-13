use std::sync::Arc;

use anyhow::Result;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::hub::{ConnectionHub, PushNotification};

/// Subscribes to Redis pub/sub channels and forwards messages to WebSocket clients.
///
/// Listens on:
///   - `nexus:tenant:{tenant_id}` — per-tenant broadcast channel (from ai-service PubSubClient)
///   - `nexus:match:detected`     — match events (any tenant)
///   - `nexus:merge:completed`    — merge events
///   - `nexus:quality:alert`      — anomaly / DQ alerts
pub struct RedisListener {
    redis_url: String,
    hub:       Arc<ConnectionHub>,
}

impl RedisListener {
    pub fn new(redis_url: impl Into<String>, hub: Arc<ConnectionHub>) -> Self {
        Self {
            redis_url: redis_url.into(),
            hub,
        }
    }

    /// Start listening — runs forever, reconnects on error.
    pub async fn run(self) -> Result<()> {
        loop {
            match self.listen_once().await {
                Ok(())  => info!("Redis listener exited cleanly; restarting"),
                Err(e)  => {
                    error!(error=%e, "Redis listener error; reconnecting in 5s");
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                }
            }
        }
    }

    async fn listen_once(&self) -> Result<()> {
        let client = redis::Client::open(self.redis_url.as_str())?;
        let conn   = client.get_async_connection().await?;
        let mut pubsub = conn.into_pubsub();

        // Subscribe to global event channels
        pubsub.psubscribe("nexus:tenant:*").await?;
        pubsub.subscribe("nexus:match:detected").await?;
        pubsub.subscribe("nexus:merge:completed").await?;
        pubsub.subscribe("nexus:quality:alert").await?;
        pubsub.subscribe("nexus:review:assigned").await?;

        info!("Redis pub/sub listener started");

        use futures_util::StreamExt;
        let mut stream = pubsub.on_message();

        while let Some(msg) = stream.next().await {
            let channel: String = msg.get_channel_name().to_string();
            let payload: String = match msg.get_payload::<String>() {
                Ok(p)  => p,
                Err(e) => { warn!(error=%e, "failed to read pub/sub payload"); continue; }
            };

            debug!(channel=%channel, "pub/sub message received");

            // Try to deserialise as PushNotification first
            if let Ok(notif) = serde_json::from_str::<PushNotification>(&payload) {
                self.hub.broadcast(&notif).await;
                continue;
            }

            // Fall back: wrap raw JSON as a generic notification
            if let Ok(raw) = serde_json::from_str::<serde_json::Value>(&payload) {
                let tenant_id = raw
                    .get("tenant_id")
                    .and_then(|v| v.as_str())
                    .and_then(|s| Uuid::parse_str(s).ok())
                    .unwrap_or(Uuid::nil());

                if tenant_id.is_nil() {
                    debug!(channel=%channel, "skipping notification with no tenant_id");
                    continue;
                }

                let notif = PushNotification {
                    notification_id:   Uuid::new_v4(),
                    tenant_id,
                    notification_type: channel.clone(),
                    title:             channel_to_title(&channel),
                    body:              payload.clone(),
                    severity:          crate::hub::NotificationSeverity::Info,
                    entity_id:         raw.get("entity_id")
                        .and_then(|v| v.as_str())
                        .and_then(|s| Uuid::parse_str(s).ok()),
                    entity_type:       raw.get("entity_type")
                        .and_then(|v| v.as_str())
                        .map(str::to_owned),
                    action_url:        None,
                    metadata:          raw,
                };

                self.hub.broadcast(&notif).await;
            }
        }

        Ok(())
    }
}

fn channel_to_title(channel: &str) -> String {
    match channel {
        "nexus:match:detected"  => "New match detected".to_string(),
        "nexus:merge:completed" => "Merge completed".to_string(),
        "nexus:quality:alert"   => "Data quality alert".to_string(),
        "nexus:review:assigned" => "Review case assigned".to_string(),
        other                   => other.replace("nexus:", "").replace(':', " "),
    }
}
