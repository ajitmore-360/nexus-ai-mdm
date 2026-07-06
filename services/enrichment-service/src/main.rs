mod config;
mod consumer;
mod enricher;
mod handlers;
mod providers;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{routing::{get, post}, Router, Json};
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use axum::http::{HeaderName, HeaderValue, Method};
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};

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

    nexus_telemetry::tracing_init::init_tracing("enrichment-service");
    nexus_telemetry::metrics::init_metrics("enrichment-service");

    let settings = EnrichmentSettings::from_env().unwrap_or_else(|e| {
        eprintln!("[FATAL] Configuration error: {e}");
        std::process::exit(1);
    });
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

    // ── Startup safety checks ─────────────────────────────────────────────────
    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());

    if settings.mock_mode
        && matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage")
    {
        // A panic here is intentional: silently returning fake enrichment data
        // in production would corrupt master data records without any indication.
        // Set ENRICHMENT_MOCK_MODE=false and configure real API keys.
        panic!(
            "SAFETY: ENRICHMENT_MOCK_MODE=true in APP_ENV={}. \
             All enrichment results will be synthetic/fake. \
             Set ENRICHMENT_MOCK_MODE=false and provide DNB_API_KEY / EXPERIAN_API_KEY.",
            app_env
        );
    }

    // ── CORS ─────────────────────────────────────────────────────────────────
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

    // ── Router ──────────────────────────────────────────────────────────────

    let app = Router::new()
        .route("/health",              get(health))
        .route("/metrics",             get(metrics_handler))
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

async fn metrics_handler() -> String {
    nexus_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}
