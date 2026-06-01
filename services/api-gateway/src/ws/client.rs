use futures_util::{SinkExt, StreamExt};

use tokio::net::TcpStream;
use tokio::sync::mpsc;

use tokio_tungstenite::{
    tungstenite::Message,
    WebSocketStream,
};

use uuid::Uuid;

use super::manager::WsManager;

pub async fn handle_client(
    ws: WebSocketStream<TcpStream>,
    manager: WsManager,
) {
    let session_id = Uuid::new_v4();

    let (mut write, mut read) = ws.split();

    let (tx, mut rx) = mpsc::unbounded_channel();

    manager.register(session_id, tx);

    println!("🔌 Client connected: {}", session_id);

    // =====================================
    // WRITE LOOP
    // =====================================
    let write_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if write.send(msg).await.is_err() {
                break;
            }
        }
    });

    // =====================================
    // READ LOOP
    // =====================================
    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                println!("📩 {}", text);
            }

            Ok(Message::Ping(payload)) => {
                println!("🏓 ping {:?}", payload);
            }

            Ok(Message::Close(_)) => {
                break;
            }

            _ => {}
        }
    }

    manager.unregister(&session_id);

    write_task.abort();

    println!("❌ Client disconnected: {}", session_id);
}