mod anomaly;
#[cfg(test)]
mod tests;
mod config;
mod embeddings;
mod feedback;
mod handlers;
mod llm;
mod matching;
mod mcp;
mod rag;
mod state;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::{
    routing::{get, post},
    Router,
};
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use axum::http::{HeaderName, HeaderValue, Method};
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};

use config::Settings;
use database::{config::DatabaseConfig, connection::create_pool as create_db_pool};
use embeddings::Encoder;
use feedback::FeedbackProcessor;
use llm::OllamaClient;
use matching::SemanticMatcher;
use nexus_redis::{create_pool as create_redis_pool, EntityCache, RedisConfig};
use rag::{RagPipeline, RagRetriever};
use state::AppState;

use handlers::{
    copilot, embed, health, index_document, record_feedback,
    recommend_weights, scan_anomalies, semantic_match,
};

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    // ---- Tracing + Metrics -------------------------------------------------
    nexus_telemetry::tracing_init::init_tracing("ai-service");
    nexus_telemetry::metrics::init_metrics("ai-service");

    let settings = Settings::from_env().unwrap_or_else(|e| {
        eprintln!("[FATAL] Configuration error: {e}");
        std::process::exit(1);
    });
    tracing::info!("AI Service starting on port {}", settings.port);

    // ---- Database ----------------------------------------------------------
    let db_config = DatabaseConfig::from_env();
    let pool = create_db_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    // ---- Redis -------------------------------------------------------------
    let redis_cfg   = RedisConfig::from_env();
    let redis_pool  = create_redis_pool(&redis_cfg).expect("failed to connect to Redis");
    let _cache = EntityCache::new(redis_pool.clone(), &redis_cfg.key_prefix);

    // ---- LLM (Ollama) ------------------------------------------------------
    let llm = Arc::new(OllamaClient::new(
        &settings.ollama_url,
        &settings.llm_model,
        &settings.embed_model,
        settings.llm_temperature,
        settings.llm_max_tokens,
        settings.llm_timeout(),
    ));

    // Verify Ollama is reachable (warn but continue if not — service degrades gracefully)
    match llm.health_check().await {
        Ok(true)  => tracing::info!("Ollama connected at {}", settings.ollama_url),
        Ok(false) => tracing::warn!("Ollama not reachable at {} — AI features degraded", settings.ollama_url),
        Err(e)    => tracing::warn!(error=%e, "Ollama health check failed"),
    }

    // ---- Encoder (embeddings) ----------------------------------------------
    let encoder = Arc::new(Encoder::new((*llm).clone()));

    // ---- RAG pipeline -------------------------------------------------------
    let retriever     = RagRetriever::new(pool.clone(), settings.rag_top_k, settings.rag_min_score);
    let rag_pipeline  = Arc::new(RagPipeline::new(
        Encoder::new((*llm).clone()),
        retriever,
        (*llm).clone(),
    ));

    // ---- Semantic matcher --------------------------------------------------
    let semantic_matcher = Arc::new(SemanticMatcher::new((*llm).clone()));

    // ---- Feedback processor ------------------------------------------------
    let feedback = Arc::new(FeedbackProcessor::new(pool.clone()));

    // ---- App state ---------------------------------------------------------
    let state = AppState {
        pool,
        llm,
        encoder,
        rag_pipeline,
        semantic_matcher,
        feedback,
    };

    // ---- CORS ---------------------------------------------------------------
    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
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
    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();
    let cors = CorsLayer::new()
        .allow_origin(allowed_origins)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([
            CONTENT_TYPE,
            AUTHORIZATION,
            HeaderName::from_static("x-tenant-id"),
            HeaderName::from_static("x-request-id"),
        ])
        .allow_credentials(true);

    // ---- Router ------------------------------------------------------------

    let app = Router::new()
        // Public
        .route("/health",          get(health))
        .route("/metrics",         get(|| async {
            nexus_telemetry::metrics::render_metrics()
                .unwrap_or_else(|e| format!("# metrics error: {}", e))
        }))
        // MCP copilot
        .route("/mcp/query",       post(copilot))
        // Semantic matching
        .route("/match/semantic",  post(semantic_match))
        // Embeddings
        .route("/embed",           post(embed))
        // Feedback
        .route("/feedback",              post(record_feedback))
        // RAG indexing
        .route("/rag/index",             post(index_document))
        // Adaptive weight tuning
        .route("/weights/recommend",     get(recommend_weights))
        // Anomaly detection
        .route("/anomalies",             get(scan_anomalies))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    // ---- Bind --------------------------------------------------------------
    let addr = SocketAddr::from(([0, 0, 0, 0], settings.port));
    tracing::info!("AI Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind AI service");

    axum::serve(listener, app)
        .await
        .expect("AI service crashed");
}
