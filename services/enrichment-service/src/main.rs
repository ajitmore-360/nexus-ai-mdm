mod config;
mod consumer;
mod enricher;
mod handlers;
mod providers;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{routing::{get, post}, Router, Json};
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use config::settings::EnrichmentSettings;
use consumer::EnrichmentConsumer;
use enricher::EnrichmentOrchestrator;
use handlers::{enrich_batch, enrich_entity};
use providers::{
    address::AddressProvider,
    dnb::DunBradstreetProvider,
    experian::ExperianProvider,
    EnrichmentProvider,
};
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("enrichment_service=info".parse().unwrap()),
        )
        .init();

    let settings = EnrichmentSettings::from_env();
    tracing::info!("Enrichment Service starting on port {}", settings.port);

    // ── Build providers ─────────────────────────────────────────────────────
    let mut providers: Vec<Arc<dyn EnrichmentProvider>> = vec![
        Arc::new(AddressProvider::new(settings.mock_mode, None)),
    ];

    if settings.enable_dnb {
        providers.push(Arc::new(DunBradstreetProvider::new(settings.mock_mode, settings.dnb_api_key.clone())));
    }
    if settings.enable_experian {
        providers.push(Arc::new(ExperianProvider::new(settings.mock_mode, settings.experian_api_key.clone())));
    }

    tracing::info!(
        providers    = providers.len(),
        mock_mode    = settings.mock_mode,
        dnb_enabled  = settings.enable_dnb,
        experian_enabled = settings.enable_experian,
        "enrichment providers initialised"
    );

    // ── Build orchestrator ──────────────────────────────────────────────────
    let orchestrator = Arc::new(EnrichmentOrchestrator::new(
        providers,
        settings.mdm_core_url.clone(),
    ));

    // ── Kafka consumer (background) ─────────────────────────────────────────
    if !settings.kafka_brokers.is_empty() {
        let orch_clone = Arc::clone(&orchestrator);
        let brokers    = settings.kafka_brokers.clone();
        let group      = settings.kafka_group_id.clone();

        tokio::spawn(async move {
            match EnrichmentConsumer::new(&brokers, &group, orch_clone) {
                Ok(consumer) => {
                    if let Err(e) = consumer.run().await {
                        tracing::error!(error=%e, "Kafka consumer exited with error");
                    }
                }
                Err(e) => {
                    tracing::warn!(error=%e, "failed to start Kafka consumer — REST-only mode");
                }
            }
        });
    } else {
        tracing::warn!("KAFKA_BROKERS not configured — running in REST-only mode");
    }

    let state = AppState { orchestrator };

    // ── Router ──────────────────────────────────────────────────────────────
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health",              get(health))
        .route("/enrich/:entity_id",   post(enrich_entity))
        .route("/enrich/batch",        post(enrich_batch))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], settings.port));
    tracing::info!("Enrichment Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind enrichment service");

    axum::serve(listener, app)
        .await
        .expect("enrichment service crashed");
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "enrichment-service" }))
}
