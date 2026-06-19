mod engine;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{Query, State},
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use database::{config::DatabaseConfig, connection::create_pool};
use engine::{SearchEngine, SearchRequest};

#[derive(Clone)]
struct AppState {
    engine: Arc<SearchEngine>,
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "search-service" }))
}

async fn metrics_handler() -> String {
    nexus_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}

/// GET /search?tenant_id=&query=&entity_type=&limit=&offset=
async fn search(
    State(state): State<AppState>,
    Query(req):   Query<SearchRequest>,
) -> Json<serde_json::Value> {
    match state.engine.search(&req).await {
        Ok(result) => Json(serde_json::json!({ "success": true, "result": result })),
        Err(e)     => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /search/autocomplete?tenant_id=&prefix=
#[derive(Deserialize)]
struct AutocompleteParams {
    tenant_id: Uuid,
    prefix:    String,
}

async fn autocomplete(
    State(state): State<AppState>,
    Query(params): Query<AutocompleteParams>,
) -> Json<serde_json::Value> {
    match state.engine.autocomplete(params.tenant_id, &params.prefix).await {
        Ok(suggestions) => Json(serde_json::json!({ "success": true, "suggestions": suggestions })),
        Err(e)          => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    nexus_telemetry::tracing_init::init_tracing("search-service");
    nexus_telemetry::metrics::init_metrics("search-service");

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Search Service environment loaded");

    let port = std::env::var("SEARCH_SERVICE_PORT")
        .ok()
        .and_then(|v| v.parse::<u16>().ok())
        .unwrap_or(8085);

    tracing::info!("Search Service starting on port {}", port);

    let allowed_origins_raw = std::env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000,http://localhost:4000".to_string());
    if matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage") {
        if allowed_origins_raw.contains("localhost") {
            panic!(
                "SECURITY: ALLOWED_ORIGINS contains 'localhost' in APP_ENV={}. Set to your production domain.",
                app_env
            );
        }
    }

    let db_config = DatabaseConfig::from_env();
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = AppState {
        engine: Arc::new(SearchEngine::new(pool)),
    };

    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors = CorsLayer::new()
        .allow_origin(allowed_origins)
        .allow_methods([Method::GET, Method::OPTIONS])
        .allow_headers([CONTENT_TYPE, AUTHORIZATION, HeaderName::from_static("x-tenant-id"), HeaderName::from_static("x-request-id")])
        .allow_credentials(true);

    let app = Router::new()
        .route("/health",             get(health))
        .route("/metrics",            get(metrics_handler))
        .route("/search",             get(search))
        .route("/search/autocomplete", get(autocomplete))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Search Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind search service");

    axum::serve(listener, app)
        .await
        .expect("search service crashed");
}
