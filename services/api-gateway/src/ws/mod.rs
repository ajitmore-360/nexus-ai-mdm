pub mod client;
pub mod events;
pub mod manager;
pub mod session;

use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;

use client::handle_client;
use manager::WsManager;

pub async fn start_ws_server() -> anyhow::Result<()> {

    let listener = TcpListener::bind("127.0.0.1:4000")
        .await
        .expect("WS bind failed");

    let manager = WsManager::new();

    println!("✅ Gateway WS running on ws://127.0.0.1:4000");

    while let Ok((stream, _)) = listener.accept().await {

        let manager_clone = manager.clone();

        tokio::spawn(async move {

            let ws = match accept_async(stream).await {
                Ok(ws) => ws,
                Err(e) => {
                    eprintln!("❌ WS handshake failed: {:?}", e);
                    return;
                }
            };

            handle_client(ws, manager_clone).await;
        });
    }

    Ok(())
}