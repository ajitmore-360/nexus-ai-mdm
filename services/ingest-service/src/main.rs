mod config;
mod models;
mod pipeline;
mod processor;
mod sources;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{routing::{get, post}, Router, Json};
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use config::settings::IngestSettings;
use sources::rest::{ingest_batch, ingest_csv, ingest_entities};
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("ingest_service=info".parse().unwrap()),
        )
        .init();

    let settings = IngestSettings::from_env()
        .expect("failed to load ingest service settings");

    tracing::info!("Ingest Service starting on port {}", settings.port);

    let port  = settings.port;
    let state = Arc::new(AppState::new(settings));

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health",          get(health))
        .route("/ingest/batch",    post(ingest_batch))
        .route("/ingest/entities", post(ingest_entities))
        .route("/ingest/csv",      post(ingest_csv))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Ingest Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind ingest service");

    axum::serve(listener, app)
        .await
        .expect("ingest service crashed");
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status":  "healthy",
        "service": "ingest-service",
    }))
}
