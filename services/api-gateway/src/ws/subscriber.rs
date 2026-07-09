use futures_util::StreamExt;
use uuid::Uuid;

use super::manager::WsManager;

/// Subscribe to Redis tenant-scoped pub/sub channels and fan events to active
/// WebSocket sessions via the WsManager.
///
/// Channel pattern: `nexus:tenant:<tenant_uuid>`
/// Runs forever in a background task. On Redis disconnect, retries with backoff.
pub async fn run(redis_url: String, ws_manager: WsManager) {
    loop {
        if let Err(e) = subscribe_once(&redis_url, &ws_manager).await {
            tracing::warn!(error=%e, "Redis pub/sub disconnected; reconnecting in 5s");
        }
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }
}

async fn subscribe_once(redis_url: &str, ws_manager: &WsManager) -> anyhow::Result<()> {
    let client = redis::Client::open(redis_url)?;
    let conn   = client.get_async_connection().await?;
    let mut pubsub = conn.into_pubsub();

    pubsub.psubscribe("azile:tenant:*").await?;
    tracing::info!("Redis pub/sub subscribed to nexus:tenant:*");

    let mut stream = pubsub.into_on_message();
    while let Some(msg) = stream.next().await {
        let channel: String = msg.get_channel_name().to_string();
        let tenant_str = channel.strip_prefix("azile:tenant:").unwrap_or_default();
        let Ok(tenant_id) = Uuid::parse_str(tenant_str) else { continue; };
        let Ok(payload) = msg.get_payload::<String>() else { continue; };
        ws_manager.broadcast_to_tenant(&tenant_id, payload);
    }

    Err(anyhow::anyhow!("pub/sub stream ended"))
}
