use axum::{
    extract::{Query, State, WebSocketUpgrade},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use axum::extract::ws::Message;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;
use uuid::Uuid;

use nexus_auth::{validate_token, JwtConfig};

use crate::state::AppState;

#[derive(Deserialize)]
pub struct WsQuery {
    pub token:     Option<String>,
    pub tenant_id: Option<String>,
}

/// Authenticated Axum WebSocket upgrade handler.
///
/// Browsers cannot set custom headers on WebSocket connections, so this handler
/// accepts the JWT as a `?token=<jwt>` query parameter and validates it inline.
/// The `tenant_id` query param is used as a fallback when the JWT's tenant claim
/// is nil (service-account path — not expected for browser clients).
pub async fn websocket_handler(
    ws:              WebSocketUpgrade,
    State(state):    State<AppState>,
    Query(params):   Query<WsQuery>,
) -> Response {
    // Validate JWT from query param (browsers can't send Authorization header on WS)
    let token = match params.token.as_deref().filter(|t| !t.is_empty()) {
        Some(t) => t.to_owned(),
        None => {
            return (StatusCode::UNAUTHORIZED, "Missing ?token query parameter").into_response();
        }
    };

    let jwt_cfg = match JwtConfig::from_env() {
        Ok(cfg) => cfg,
        Err(_)  => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "JWT not configured").into_response();
        }
    };

    let claims = match validate_token(&jwt_cfg, &token) {
        Ok(c)  => c,
        Err(e) => {
            tracing::warn!(error=%e, "WS JWT validation failed");
            return (StatusCode::UNAUTHORIZED, "Invalid token").into_response();
        }
    };

    // Check revocation
    if let Some(blocklist) = &state.token_blocklist {
        if blocklist.is_revoked(claims.nxs_jti).await.unwrap_or(false) {
            return (StatusCode::UNAUTHORIZED, "Token has been revoked").into_response();
        }
    }

    let tenant_id  = if claims.nxs_tenant_id == Uuid::nil() {
        params.tenant_id
            .as_deref()
            .and_then(|s| Uuid::parse_str(s).ok())
            .unwrap_or(Uuid::nil())
    } else {
        claims.nxs_tenant_id
    };
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

    if !ws_manager.register(session_id, tenant_id, tx) {
        // Tenant is at the per-tenant connection limit — send close and return.
        let _ = sender.send(Message::Close(None)).await;
        return;
    }
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
