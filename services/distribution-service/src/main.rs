mod connectors;
mod processor;

use std::net::SocketAddr;

use axum::{
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::get,
    Router, Json,
};
use serde::Deserialize;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use database::{config::DatabaseConfig, connection::create_pool};
use processor::DistributionWorker;

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "distribution-service" }))
}

/// POST /jobs  — enqueue a distribution job from another service
async fn enqueue_job(
    axum::extract::State(pool): axum::extract::State<sqlx::PgPool>,
    Json(req): Json<EnqueueJobRequest>,
) -> Json<serde_json::Value> {
    let job_id = Uuid::new_v4();

    match sqlx::query(
        r#"
        INSERT INTO platform.distribution_jobs
        (job_id, tenant_id, connector_id, entity_id, entity_type, payload)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#,
    )
    .bind(job_id)
    .bind(req.tenant_id)
    .bind(req.connector_id)
    .bind(req.entity_id)
    .bind(&req.entity_type)
    .bind(&req.payload)
    .execute(&pool)
    .await
    {
        Ok(_)  => Json(serde_json::json!({ "success": true, "job_id": job_id })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

#[derive(Deserialize)]
struct EnqueueJobRequest {
    tenant_id:    Uuid,
    connector_id: Uuid,
    entity_id:    Uuid,
    entity_type:  String,
    payload:      serde_json::Value,
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("distribution_service=info".parse().unwrap()),
        )
        .init();

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Distribution Service environment loaded");

    let port = std::env::var("DISTRIBUTION_PORT")
        .ok()
        .and_then(|v| v.parse::<u16>().ok())
        .unwrap_or(8089);

    tracing::info!("Distribution Service starting on port {}", port);

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

    let db_config = DatabaseConfig::from_env();
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    // Spawn the background distribution worker
    let worker_pool = pool.clone();
    tokio::spawn(async move {
        DistributionWorker::new(worker_pool).run().await;
    });

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
        .route("/health", get(health))
        .route("/jobs",   axum::routing::post(enqueue_job))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(pool);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Distribution Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind distribution service");

    axum::serve(listener, app)
        .await
        .expect("distribution service crashed");
}
