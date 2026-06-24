use axum::{
    extract::{State, WebSocketUpgrade},
    response::Response,
    Extension,
};
use axum::extract::ws::Message;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use uuid::Uuid;

use nexus_auth::Claims;

use crate::state::AppState;

/// Authenticated Axum WebSocket upgrade handler.
///
/// The JWT and tenant context have already been validated by `auth_middleware`
/// and `tenant_middleware` before this runs — we just extract the injected claims.
pub async fn websocket_handler(
    ws:                WebSocketUpgrade,
    State(state):      State<AppState>,
    Extension(claims): Extension<Claims>,
) -> Response {
    let tenant_id  = claims.nxs_tenant_id;
    let user_id    = Uuid::parse_str(&claims.sub).ok();
    let ws_manager = state.ws_manager.clone();
    ws.on_upgrade(move |socket| handle_socket(socket, ws_manager, tenant_id, user_id))
}

async fn handle_socket(
    socket:     axum::extract::ws::WebSocket,
    ws_manager: crate::ws::manager::WsManager,
    tenant_id:  Uuid,
    user_id:    Option<Uuid>,
) {
    let session_id = Uuid::new_v4();
    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    ws_manager.register(session_id, tenant_id, tx);
    tracing::info!(%session_id, %tenant_id, ?user_id, "WS session opened");

    let send_task = tokio::spawn(async move {
        while let Some(text) = rx.recv().await {
            if sender.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    // Drain inbound messages — server-push only; we only care about Close.
    while let Some(result) = receiver.next().await {
        match result {
            Ok(Message::Close(_)) | Err(_) => break,
            _ => {}
        }
    }

    ws_manager.unregister(&session_id, &tenant_id);
    send_task.abort();
    tracing::info!(%session_id, "WS session closed");
}
