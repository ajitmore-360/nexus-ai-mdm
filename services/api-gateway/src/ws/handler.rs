use axum::{extract::WebSocketUpgrade, response::Response};

pub async fn websocket_handler(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(handle_socket)
}

async fn handle_socket(mut socket: axum::extract::ws::WebSocket) {
    tracing::debug!("WebSocket session started");

    while let Some(message) = socket.recv().await {
        match message {
            Ok(_msg) => { /* messages handled by notification-service */ }
            Err(err) => {
                tracing::warn!(error=%err, "WebSocket error");
                break;
            }
        }
    }

    tracing::debug!("WebSocket session ended");
}
