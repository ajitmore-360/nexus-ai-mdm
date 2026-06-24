pub mod client;
pub mod events;
pub mod handler;
pub mod manager;
pub mod message;
pub mod session;

use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::{accept_async, tungstenite::Message};
use uuid::Uuid;

use client::handle_client;
use manager::WsManager;

/// Timeout before an unauthenticated TCP WS connection is closed.
const AUTH_TIMEOUT_SECS: u64 = 5;

/// Start the legacy TCP WebSocket server on port 4000.
///
/// Every connection must authenticate within `AUTH_TIMEOUT_SECS` by sending
/// a JSON first-message:
///
/// ```json
/// { "token": "Bearer <jwt>" }
/// ```
///
/// The JWT is validated with `nexus_auth`; on success the `nxs_tenant_id` claim
/// is extracted and the connection is handed to `handle_client`. Any failure
/// (bad JWT, timeout, malformed message) closes the socket immediately.
///
/// Set `DISABLE_LEGACY_WS=true` to skip starting this server entirely — the
/// authenticated Axum `/ws/notifications` endpoint is the preferred path.
pub async fn start_ws_server(jwt_config: Arc<nexus_auth::JwtConfig>) -> anyhow::Result<()> {
    if std::env::var("DISABLE_LEGACY_WS")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false)
    {
        tracing::info!("DISABLE_LEGACY_WS=true — TCP WS server on port 4000 not started");
        return Ok(());
    }

    let listener = TcpListener::bind("0.0.0.0:4000")
        .await
        .expect("TCP WS bind on port 4000 failed");

    let manager = WsManager::new();
    tracing::info!("Gateway TCP WS server listening on ws://0.0.0.0:4000 (legacy)");

    while let Ok((stream, peer)) = listener.accept().await {
        let manager_clone = manager.clone();
        let jwt_config    = Arc::clone(&jwt_config);

        tokio::spawn(async move {
            let mut ws = match accept_async(stream).await {
                Ok(ws) => ws,
                Err(e) => {
                    tracing::warn!(%peer, error=%e, "TCP WS handshake failed");
                    return;
                }
            };

            // ── First-message JWT auth (5-second window) ──────────────────
            let tenant_id = match tokio::time::timeout(
                Duration::from_secs(AUTH_TIMEOUT_SECS),
                ws.next(),
            )
            .await
            {
                Ok(Some(Ok(Message::Text(text)))) => {
                    match authenticate_first_message(&jwt_config, &text) {
                        Ok(tid) => tid,
                        Err(reason) => {
                            tracing::warn!(%peer, %reason, "TCP WS auth rejected");
                            let _ = ws
                                .send(Message::Close(None))
                                .await;
                            return;
                        }
                    }
                }
                Ok(_) => {
                    tracing::warn!(%peer, "TCP WS closed before auth message");
                    return;
                }
                Err(_) => {
                    tracing::warn!(%peer, "TCP WS auth timeout after {}s", AUTH_TIMEOUT_SECS);
                    let _ = ws.send(Message::Close(None)).await;
                    return;
                }
            };

            tracing::debug!(%peer, %tenant_id, "TCP WS authenticated");
            handle_client(ws, manager_clone, tenant_id).await;
        });
    }

    Ok(())
}

/// Parse and validate the auth first-message.
/// Expects `{ "token": "Bearer <jwt>" }` or `{ "token": "<raw-jwt>" }`.
fn authenticate_first_message(
    jwt_config: &nexus_auth::JwtConfig,
    text: &str,
) -> Result<Uuid, String> {
    let payload: serde_json::Value = serde_json::from_str(text)
        .map_err(|_| "auth message is not valid JSON".to_owned())?;

    let raw_token = payload
        .get("token")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "auth message missing 'token' field".to_owned())?;

    let token = raw_token
        .strip_prefix("Bearer ")
        .unwrap_or(raw_token);

    let claims = nexus_auth::validate_token(jwt_config, token)
        .map_err(|e| format!("invalid JWT: {e}"))?;

    Ok(claims.nxs_tenant_id)
}
