mod config;
mod models;
mod pipeline;
mod processor;
mod sources;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::{get, post},
    Router, Json,
};
use tower_http::cors::CorsLayer;
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

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Ingest Service environment loaded");

    let settings = IngestSettings::from_env()
        .expect("failed to load ingest service settings");

    tracing::info!("Ingest Service starting on port {}", settings.port);

    let allowed_origins_raw = std::env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000,http://localhost:4000".to_string());
    if matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage") {
        if allowed_origins_raw.contains("localhost") {
            panic!(
                "SECURITY: ALLOWED_ORIGINS contains 'localhost' in APP_ENV={}. Set to your production domain.",
                app_env
            );
        }
        if std::env::var("FIELD_ENCRYPTION_KEY").is_err() {
            tracing::warn!(
                "SECURITY: FIELD_ENCRYPTION_KEY is not set in APP_ENV={}. PII data will be stored unencrypted.",
                app_env
            );
        }
    }

    let port  = settings.port;
    let state = Arc::new(AppState::new(settings));

    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors = CorsLayer::new()
        .allow_origin(allowed_origins)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([CONTENT_TYPE, AUTHORIZATION, HeaderName::from_static("x-tenant-id"), HeaderName::from_static("x-request-id")])
        .allow_credentials(true);

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
