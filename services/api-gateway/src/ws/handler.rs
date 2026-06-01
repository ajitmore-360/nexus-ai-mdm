use axum::{
    extract::WebSocketUpgrade,
    response::Response,
};

//
// ========================================
// WS HANDLER
// ========================================
//

pub async fn websocket_handler(
    ws: WebSocketUpgrade,
) -> Response {

    ws.on_upgrade(handle_socket)
}

//
// ========================================
// SOCKET SESSION
// ========================================
//

async fn handle_socket(
    mut socket: axum::extract::ws::WebSocket,
) {

    println!("✅ WebSocket connected");

    while let Some(message) = socket.recv().await {

        match message {

            Ok(msg) => {

                println!("Received WS message: {:?}", msg);
            }

            Err(err) => {

                println!("WS error: {:?}", err);

                break;
            }
        }
    }

    println!("❌ WebSocket disconnected");
}