use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::{tungstenite::Message, WebSocketStream};
use uuid::Uuid;

use super::manager::WsManager;

/// Handle a raw TCP WebSocket client (port-4000 server).
/// `tenant_id` must be extracted from the first authenticated message before
/// calling this function; callers that cannot authenticate should drop the stream.
pub async fn handle_client(
    ws:        WebSocketStream<TcpStream>,
    manager:   WsManager,
    tenant_id: Uuid,
) {
    let session_id = Uuid::new_v4();
    let (mut write, mut read) = ws.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    if !manager.register(session_id, tenant_id, tx) {
        // Tenant is at the per-tenant connection limit — close immediately.
        return;
    }
    tracing::debug!(%session_id, %tenant_id, "WS TCP client connected");

    // Adapt String → tungstenite Message and forward to the socket.
    let write_task = tokio::spawn(async move {
        while let Some(text) = rx.recv().await {
            if write.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Ping(_)) => {}    // tungstenite handles pong
            Ok(Message::Close(_)) | Err(_) => break,
            _ => {}
        }
    }

    manager.unregister(&session_id, &tenant_id);
    write_task.abort();
    tracing::debug!(%session_id, "WS TCP client disconnected");
}
