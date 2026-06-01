use dashmap::DashMap;
use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

#[derive(Clone)]
pub struct WsManager {
    pub clients: DashMap<Uuid, UnboundedSender<Message>>,
}

impl WsManager {
    pub fn new() -> Self {
        Self {
            clients: DashMap::new(),
        }
    }

    pub fn register(
        &self,
        session_id: Uuid,
        tx: UnboundedSender<Message>,
    ) {
        self.clients.insert(session_id, tx);
    }

    pub fn unregister(&self, session_id: &Uuid) {
        self.clients.remove(session_id);
    }

    pub fn broadcast(&self, message: String) {
        for client in self.clients.iter() {
            let _ = client.send(
                Message::Text(message.clone())
            );
        }
    }
}