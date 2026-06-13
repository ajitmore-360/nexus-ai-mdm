use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::{tungstenite::Message, WebSocketStream};
use uuid::Uuid;

use super::manager::WsManager;

pub async fn handle_client(ws: WebSocketStream<TcpStream>, manager: WsManager) {
    let session_id = Uuid::new_v4();
    let (mut write, mut read) = ws.split();
    let (tx, mut rx) = mpsc::unbounded_channel();

    manager.register(session_id, tx);
    tracing::debug!(%session_id, "WS client connected");

    // Forward outbound messages to the WebSocket write half
    let write_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if write.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Drain inbound messages
    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                tracing::trace!(%session_id, text=%text, "WS text received");
            }
            Ok(Message::Ping(_)) => { /* handled by tungstenite automatically */ }
            Ok(Message::Close(_)) => break,
            Err(e) => {
                tracing::warn!(%session_id, error=%e, "WS read error");
                break;
            }
            _ => {}
        }
    }

    manager.unregister(&session_id);
    write_task.abort();
    tracing::debug!(%session_id, "WS client disconnected");
}
