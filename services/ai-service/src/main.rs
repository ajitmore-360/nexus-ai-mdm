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
use embeddings::{encoder::entity_to_text, Encoder};
use feedback::FeedbackProcessor;
use llm::OllamaClient;
use matching::SemanticMatcher;
use azile_redis::{
    create_pool as create_redis_pool,
    queue::{task_types, TaskQueue},
    EntityCache, RedisConfig,
};
use rag::{RagPipeline, RagRetriever};
use state::AppState;

use handlers::{
    copilot, copilot_stream, embed, health, index_document, internal_suggest,
    record_feedback, recommend_weights, scan_anomalies, semantic_match,
};

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    // ---- Tracing + Metrics -------------------------------------------------
    azile_telemetry::tracing_init::init_tracing("ai-service");
    azile_telemetry::metrics::init_metrics("ai-service");

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
    let _cache      = EntityCache::new(redis_pool.clone(), &redis_cfg.key_prefix);
    let task_queue  = Arc::new(TaskQueue::new(redis_pool.clone(), &redis_cfg.key_prefix));

    // ---- LLM (Ollama) ------------------------------------------------------
    let llm = Arc::new(OllamaClient::new(
        &settings.ollama_url,
        &settings.llm_model,
        &settings.embed_model,
        settings.llm_temperature,
        settings.llm_max_tokens,
        settings.llm_num_ctx,
        settings.llm_num_threads,
        settings.llm_timeout(),
    ));

    // Verify Ollama is reachable (warn but continue if not â€” service degrades gracefully)
    match llm.health_check().await {
        Ok(true)  => tracing::info!("Ollama connected at {}", settings.ollama_url),
        Ok(false) => tracing::warn!("Ollama not reachable at {} â€” AI features degraded", settings.ollama_url),
        Err(e)    => tracing::warn!(error=%e, "Ollama health check failed"),
    }

    // ---- Encoder (embeddings) ----------------------------------------------
    let encoder = Arc::new(Encoder::new((*llm).clone()));

    // ---- RAG pipeline -------------------------------------------------------
    let retriever     = RagRetriever::new(pool.clone(), settings.rag_top_k, settings.rag_min_score, settings.rag_max_doc_chars, settings.rag_max_context_chars);
    let rag_pipeline  = Arc::new(RagPipeline::new(
        Encoder::new((*llm).clone()),
        retriever,
        (*llm).clone(),
    ));

    // ---- Semantic matcher --------------------------------------------------
    let semantic_matcher = Arc::new(SemanticMatcher::new((*llm).clone()));

    // ---- Feedback processor ------------------------------------------------
    let feedback = Arc::new(FeedbackProcessor::new(pool.clone()));

    // ---- Embedding consumer loop ------------------------------------------
    // Dequeues entity.embed tasks produced by mdm-core on entity create/patch
    // and upserts the resulting vector into ai.entity_embeddings so that vector
    // blocking, semantic search, and survivorship ranking have live data.
    {
        let embed_encoder = Arc::clone(&encoder);
        let embed_pool    = pool.clone();
        let embed_queue   = Arc::clone(&task_queue);
        let embed_model   = settings.embed_model.clone();

        tokio::spawn(async move {
            tracing::info!("Embedding consumer loop started");
            loop {
                match embed_queue.dequeue(task_types::ENTITY_EMBED).await {
                    Ok(Some(task)) => {
                        let entity_id_str = task.payload
                            .get("entity_id").and_then(|v| v.as_str()).unwrap_or("");
                        let tenant_id_str = task.payload
                            .get("tenant_id").and_then(|v| v.as_str()).unwrap_or("");
                        let attrs = task.payload
                            .get("attributes").cloned().unwrap_or(serde_json::Value::Null);

                        let (entity_id, tenant_id) = match (
                            uuid::Uuid::parse_str(entity_id_str),
                            uuid::Uuid::parse_str(tenant_id_str),
                        ) {
                            (Ok(eid), Ok(tid)) => (eid, tid),
                            _ => {
                                tracing::warn!(task_id=%task.task_id, "embed task: invalid uuid(s); skipping");
                                continue;
                            }
                        };

                        let text = entity_to_text(&attrs);
                        if text.is_empty() {
                            tracing::debug!(%entity_id, "embed task: empty attribute text; skipping");
                            continue;
                        }

                        match embed_encoder.encode(&text).await {
                            Ok(vector) if !vector.is_empty() => {
                                // Format as PostgreSQL vector literal: [0.1,0.2,...]
                                let vec_lit = format!(
                                    "[{}]",
                                    vector.iter().map(|f| f.to_string()).collect::<Vec<_>>().join(",")
                                );
                                let result = sqlx::query(
                                    r#"
                                    INSERT INTO ai.entity_embeddings
                                        (tenant_id, entity_id, embedding_model, embedding)
                                    VALUES ($1, $2, $3, $4::vector)
                                    ON CONFLICT (tenant_id, entity_id, embedding_model)
                                    DO UPDATE SET
                                        embedding    = EXCLUDED.embedding,
                                        generated_at = NOW()
                                    "#,
                                )
                                .bind(tenant_id)
                                .bind(entity_id)
                                .bind(&embed_model)
                                .bind(&vec_lit)
                                .execute(&embed_pool)
                                .await;

                                match result {
                                    Ok(_)  => tracing::info!(%entity_id, "entity embedded successfully"),
                                    Err(e) => tracing::warn!(error=%e, %entity_id, "failed to upsert embedding"),
                                }
                            }
                            Ok(_)  => tracing::warn!(%entity_id, "encoder returned empty vector"),
                            Err(e) => tracing::warn!(error=%e, %entity_id, "encoder failed"),
                        }
                    }
                    Ok(None) => {
                        // Queue empty â€” poll again after a short back-off.
                        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                    }
                    Err(e) => {
                        tracing::warn!(error=%e, "embed queue: dequeue failed; retrying in 2s");
                        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                    }
                }
            }
        });
    }

    // ---- App state ---------------------------------------------------------
    let state = AppState {
        pool,
        llm,
        encoder,
        rag_pipeline,
        semantic_matcher,
        feedback,
        injection_tracker: Arc::new(dashmap::DashMap::new()),
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
            azile_telemetry::metrics::render_metrics()
                .unwrap_or_else(|e| format!("# metrics error: {}", e))
        }))
        // MCP copilot
        .route("/mcp/query",       post(copilot))
        .route("/mcp/stream",      post(copilot_stream))
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
        // Internal â€” mdm-core calls this on the Docker-internal network (no JWT required)
        .route("/internal/suggest",      post(internal_suggest))
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
