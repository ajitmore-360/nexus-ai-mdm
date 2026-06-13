use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::{broadcast, Mutex, RwLock};
use tracing::{debug, info, warn};
use uuid::Uuid;

/// A push notification sent to a connected client.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushNotification {
    pub notification_id: Uuid,
    pub tenant_id:       Uuid,
    pub notification_type: String,
    pub title:           String,
    pub body:            String,
    pub severity:        NotificationSeverity,
    pub entity_id:       Option<Uuid>,
    pub entity_type:     Option<String>,
    pub action_url:      Option<String>,
    pub metadata:        serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NotificationSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

/// A registered WebSocket client.
#[allow(dead_code)]
struct Client {
    tenant_id: Uuid,
    user_id:   Option<Uuid>,
    tx:        broadcast::Sender<String>,
}

/// Central WebSocket connection hub.
///
/// Maintains one `broadcast::Sender<String>` per tenant.  New connections
/// subscribe to their tenant's channel; the Redis subscriber forwards
/// incoming pub/sub messages by calling `broadcast()`.
#[derive(Clone)]
pub struct ConnectionHub {
    /// tenant_id → broadcast sender
    channels: Arc<RwLock<HashMap<Uuid, broadcast::Sender<String>>>>,
    /// client_id → Client metadata
    clients:  Arc<Mutex<HashMap<Uuid, Client>>>,
}

impl ConnectionHub {
    pub fn new() -> Self {
        Self {
            channels: Arc::new(RwLock::new(HashMap::new())),
            clients:  Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Broadcast a notification to all connected clients for a tenant.
    pub async fn broadcast(&self, notification: &PushNotification) {
        let payload = match serde_json::to_string(notification) {
            Ok(s)  => s,
            Err(e) => { warn!(error=%e, "failed to serialise notification"); return; }
        };

        let channels = self.channels.read().await;
        if let Some(tx) = channels.get(&notification.tenant_id) {
            let count = tx.receiver_count();
            if count > 0 {
                match tx.send(payload) {
                    Ok(_)  => debug!(tenant_id=%notification.tenant_id, clients=count, "broadcast sent"),
                    Err(e) => warn!(error=%e, "broadcast failed (no active receivers)"),
                }
            }
        }
    }

    /// Handle a new WebSocket connection for a specific tenant/user.
    pub async fn handle_connection(
        &self,
        socket:    WebSocket,
        tenant_id: Uuid,
        user_id:   Option<Uuid>,
    ) {
        // Ensure a broadcast channel exists for this tenant
        let rx = {
            let mut channels = self.channels.write().await;
            let tx = channels
                .entry(tenant_id)
                .or_insert_with(|| broadcast::channel::<String>(256).0);
            tx.subscribe()
        };

        let client_id = Uuid::new_v4();

        {
            let tx = {
                let channels = self.channels.read().await;
                channels.get(&tenant_id).cloned()
            };
            if let Some(tx) = tx {
                let mut clients = self.clients.lock().await;
                clients.insert(client_id, Client { tenant_id, user_id, tx });
            }
        }

        info!(
            client_id=%client_id,
            tenant_id=%tenant_id,
            "WebSocket client connected"
        );

        let (mut ws_sender, mut ws_receiver) = socket.split();
        let mut rx = rx;

        // Forward broadcast messages to this client
        let send_task = tokio::spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(msg) => {
                        if ws_sender.send(Message::Text(msg)).await.is_err() {
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Closed)   => break,
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        warn!(client_id=%client_id, "client lagged; dropping old messages");
                    }
                }
            }
        });

        // Drain incoming messages (pings / client-initiated close)
        while ws_receiver.next().await.is_some() {}

        send_task.abort();

        // Clean up
        self.clients.lock().await.remove(&client_id);

        info!(client_id=%client_id, "WebSocket client disconnected");
    }

    #[allow(dead_code)]
    pub async fn connected_count(&self, tenant_id: Uuid) -> usize {
        let channels = self.channels.read().await;
        channels
            .get(&tenant_id)
            .map(|tx| tx.receiver_count())
            .unwrap_or(0)
    }
}
