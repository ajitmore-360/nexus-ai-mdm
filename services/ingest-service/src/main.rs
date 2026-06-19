mod config;
mod models;
mod pipeline;
mod processor;
mod source_systems;
mod sources;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::{get, post, put},
    Router, Json,
};
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

use config::settings::IngestSettings;
use database::{config::DatabaseConfig, connection::create_pool};
use source_systems::{
    create_source_system, delete_source_system, list_source_systems,
    test_connection, update_source_system,
};
use sources::rest::{ingest_batch, ingest_csv, ingest_entities};
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    nexus_telemetry::tracing_init::init_tracing("ingest-service");
    nexus_telemetry::metrics::init_metrics("ingest-service");

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
            panic!(
                "SECURITY: FIELD_ENCRYPTION_KEY is not set in APP_ENV={}. \
                 PII data must be encrypted in production. \
                 Generate a 32-byte key: openssl rand -hex 32",
                app_env
            );
        }
    }

    let port = settings.port;

    let db_config = DatabaseConfig { database_url: settings.database_url.clone() };
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = Arc::new(AppState::new(settings, pool));

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
        .route("/health",                    get(health))
        .route("/metrics",                   get(metrics_handler))
        .route("/ingest/batch",              post(ingest_batch))
        .route("/ingest/entities",           post(ingest_entities))
        .route("/ingest/csv",                post(ingest_csv))
        // ── Source system registry routes ────────────────────────────────────
        .route("/source-systems",            get(list_source_systems).post(create_source_system))
        .route("/source-systems/:id",        put(update_source_system).delete(delete_source_system))
        .route("/source-systems/:id/test",   post(test_connection))
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

async fn metrics_handler() -> String {
    nexus_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}
