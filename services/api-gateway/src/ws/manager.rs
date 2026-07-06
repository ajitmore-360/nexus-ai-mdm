use dashmap::DashMap;
use std::collections::HashSet;
use tokio::sync::mpsc::UnboundedSender;
use uuid::Uuid;

type SessionMap  = DashMap<Uuid, UnboundedSender<String>>;
type TenantIndex = DashMap<Uuid, HashSet<Uuid>>;

/// Maximum concurrent WebSocket sessions allowed per tenant.
/// Prevents a single tenant from exhausting all available WS slots.
const MAX_WS_SESSIONS_PER_TENANT: usize = 100;

#[derive(Clone, Default)]
pub struct WsManager {
    clients:      SessionMap,
    tenant_index: TenantIndex,
}

impl WsManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new WS session for `tenant_id`.
    ///
    /// Returns `false` and drops the sender if the tenant has already reached
    /// `MAX_WS_SESSIONS_PER_TENANT` — the caller must close the connection.
    pub fn register(&self, session_id: Uuid, tenant_id: Uuid, tx: UnboundedSender<String>) -> bool {
        {
            let count = self.tenant_index
                .get(&tenant_id)
                .map(|s| s.len())
                .unwrap_or(0);
            if count >= MAX_WS_SESSIONS_PER_TENANT {
                tracing::warn!(
                    %tenant_id,
                    count,
                    "WS session rejected — tenant at connection limit"
                );
                return false;
            }
        }
        self.clients.insert(session_id, tx);
        self.tenant_index
            .entry(tenant_id)
            .or_insert_with(HashSet::new)
            .insert(session_id);
        true
    }

    pub fn unregister(&self, session_id: &Uuid, tenant_id: &Uuid) {
        self.clients.remove(session_id);
        if let Some(mut sessions) = self.tenant_index.get_mut(tenant_id) {
            sessions.remove(session_id);
        }
    }

    /// Push a JSON string to every active WS client belonging to `tenant_id`.
    pub fn broadcast_to_tenant(&self, tenant_id: &Uuid, message: String) {
        if let Some(sessions) = self.tenant_index.get(tenant_id) {
            for session_id in sessions.iter() {
                if let Some(tx) = self.clients.get(session_id) {
                    let _ = tx.send(message.clone());
                }
            }
        }
    }

    pub fn active_count(&self) -> usize {
        self.clients.len()
    }
}
