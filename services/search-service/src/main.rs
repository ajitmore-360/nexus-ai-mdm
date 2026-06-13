mod engine;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use tower_http::cors::{Any, CorsLayer};
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

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("search_service=info".parse().unwrap()),
        )
        .init();

    let port = std::env::var("SEARCH_SERVICE_PORT")
        .ok()
        .and_then(|v| v.parse::<u16>().ok())
        .unwrap_or(8085);

    tracing::info!("Search Service starting on port {}", port);

    let db_config = DatabaseConfig::from_env();
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = AppState {
        engine: Arc::new(SearchEngine::new(pool)),
    };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health",             get(health))
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
