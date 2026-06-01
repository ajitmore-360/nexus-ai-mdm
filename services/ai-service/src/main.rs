mod explain;
mod mcp;

use axum::{
    routing::{get, post},
    Json,
    Router,
};

use std::net::SocketAddr;

use contracts::ai::mcp::{ MCPRequest, MCPResponse};


//
// ========================================
// HEALTH
// ========================================
//

async fn health() -> &'static str {
    "ai-service healthy"
}

//
// ========================================
// MCP ENDPOINT
// ========================================
//

async fn copilot(
    Json(payload): Json<MCPRequest>,
) -> Json<MCPResponse> {

    let response = mcp::process_mcp(payload).await;

    Json(response)
}

//
// ========================================
// MAIN
// ========================================
//

#[tokio::main]
async fn main() {

    let app = Router::new()
        .route("/health", get(health))
        .route("/copilot", post(copilot));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8082));

    println!("🚀 AI Service running on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind listener");

    axum::serve(listener, app)
        .await
        .expect("AI service failed");
}