mod config;
mod engine;
mod handlers;
mod models;
mod rules;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::{delete, get, post},
    Router, Json,
};
use database::{config::DatabaseConfig, connection::create_pool};
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

use config::settings::PolicySettings;
use engine::{GdprEngine, OpaClient, PolicyEvaluator};
use handlers::{
    create_rule, delete_rule, evaluate, evaluate_merge,
    gdpr_access, gdpr_erasure, list_rules,
};
use rules::PolicyRepository;
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("policy_service=info".parse().unwrap()),
        )
        .init();

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Policy Service environment loaded");

    let settings = PolicySettings::from_env();
    tracing::info!("Policy Service starting on port {}", settings.port);

    // ── Database ─────────────────────────────────────────────────────────────
    let db_config = DatabaseConfig { database_url: settings.database_url.clone() };
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    // ── OPA client ───────────────────────────────────────────────────────────
    let opa = Arc::new(OpaClient::new(&settings.opa_url, settings.opa_timeout_secs));
    match opa.health_check().await {
        true  => tracing::info!("OPA connected at {}", settings.opa_url),
        false => tracing::warn!("OPA not available at {} — failing open", settings.opa_url),
    }

    // ── Service layer ─────────────────────────────────────────────────────────
    let evaluator = Arc::new(PolicyEvaluator::new(pool.clone(), Arc::clone(&opa)));
    let gdpr      = Arc::new(GdprEngine::new(pool.clone()));
    let rule_repo = Arc::new(PolicyRepository::new(pool.clone()));

    let state = Arc::new(AppState {
        settings: Arc::new(settings.clone()),
        evaluator,
        gdpr,
        rule_repo,
    });

    // ── Router ────────────────────────────────────────────────────────────────
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
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([CONTENT_TYPE, AUTHORIZATION, HeaderName::from_static("x-tenant-id"), HeaderName::from_static("x-request-id")])
        .allow_credentials(true);

    let app = Router::new()
        .route("/health",                  get(health))
        .route("/policy/evaluate",         post(evaluate))
        .route("/policy/evaluate/merge",   post(evaluate_merge))
        .route("/policy/rules",            get(list_rules).post(create_rule))
        .route("/policy/rules/:id",        delete(delete_rule))
        .route("/policy/gdpr/erasure",     post(gdpr_erasure))
        .route("/policy/gdpr/access",      post(gdpr_access))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], settings.port));
    tracing::info!("Policy Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind policy service");

    axum::serve(listener, app)
        .await
        .expect("policy service crashed");
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status":  "healthy",
        "service": "policy-service",
    }))
}
