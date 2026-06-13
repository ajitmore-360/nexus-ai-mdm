mod connectors;
mod processor;

use std::net::SocketAddr;

use axum::{routing::get, Router, Json};
use serde::Deserialize;
use tower_http::cors::{Any, CorsLayer};
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

    let port = std::env::var("DISTRIBUTION_PORT")
        .ok()
        .and_then(|v| v.parse::<u16>().ok())
        .unwrap_or(8089);

    tracing::info!("Distribution Service starting on port {}", port);

    let db_config = DatabaseConfig::from_env();
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    // Spawn the background distribution worker
    let worker_pool = pool.clone();
    tokio::spawn(async move {
        DistributionWorker::new(worker_pool).run().await;
    });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

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
