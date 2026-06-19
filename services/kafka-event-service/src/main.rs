use dotenvy::dotenv;

use sqlx::{
    postgres::PgPoolOptions,
    PgPool,
};

use std::{
    env,
    sync::{Arc, atomic::{AtomicBool, Ordering}},
    time::Duration,
};

use tracing::{
    error,
    info,
};

use tokio::signal;

use rdkafka::producer::FutureProducer;

mod kafka;
mod models;
mod outbox;
mod workers;

use kafka::producer::create_producer;
use workers::outbox_worker::start_outbox_worker;

//
// ========================================
// MAIN
// ========================================
//

#[tokio::main]
async fn main() -> anyhow::Result<()> {

    //
    // ====================================
    // LOAD ENVIRONMENT
    // ====================================
    //

    dotenv().ok();

    //
    // ====================================
    // INIT TRACING (structured + OTLP)
    // ====================================
    //

    nexus_telemetry::tracing_init::init_tracing("kafka-event-service");

    info!("Starting Kafka Event Service...");

    //
    // ====================================
    // DATABASE URL
    // ====================================
    //

    let database_url = env::var("DATABASE_URL")
        .expect("DATABASE_URL missing");

    //
    // ====================================
    // KAFKA BROKERS
    // ====================================
    //

    let kafka_brokers = env::var("KAFKA_BROKERS")
        .unwrap_or_else(|_| "localhost:9092".to_string());

    //
    // ====================================
    // CONNECT POSTGRES
    // ====================================
    //

    let pool: PgPool = PgPoolOptions::new()
        .max_connections(20)
        .min_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .connect(&database_url)
        .await?;

    info!("Connected to PostgreSQL");

    //
    // ====================================
    // CREATE KAFKA PRODUCER
    // ====================================
    //

    let producer: FutureProducer = create_producer(&kafka_brokers)?;

    info!("Kafka producer initialized");

    //
    // ====================================
    // WORKER HEALTH FLAG
    // ====================================
    // Shared atomic: health endpoint reports 503 if worker exits unexpectedly.
    //

    let worker_alive = Arc::new(AtomicBool::new(true));

    //
    // ====================================
    // START HEALTH SERVER
    // ====================================
    //

    let health_pool   = pool.clone();
    let health_flag   = worker_alive.clone();

    tokio::spawn(async move {
        if let Err(e) = start_health_server(health_pool, health_flag).await {
            error!("Health server crashed: {:?}", e);
        }
    });

    //
    // ====================================
    // START OUTBOX WORKER
    // ====================================
    //

    let worker_pool     = pool.clone();
    let worker_producer = producer.clone();
    let flag_clone      = worker_alive.clone();

    tokio::spawn(async move {
        if let Err(e) = start_outbox_worker(worker_pool, worker_producer).await {
            error!("Outbox worker crashed: {:?}", e);
        }
        flag_clone.store(false, Ordering::SeqCst);
    });

    info!("Outbox worker started");
    info!("Kafka Event Service is running");

    //
    // ====================================
    // GRACEFUL SHUTDOWN
    // ====================================
    //

    signal::ctrl_c().await?;

    info!("Shutdown signal received");

    // Flush OTLP spans before exit
    nexus_telemetry::tracing_init::shutdown_tracing();

    info!("Kafka Event Service stopped");

    Ok(())
}

// ── Health HTTP server ────────────────────────────────────────────────────────

async fn start_health_server(
    pool: PgPool,
    worker_alive: Arc<AtomicBool>,
) -> anyhow::Result<()> {
    use axum::{routing::get, Router};
    use std::net::SocketAddr;

    let health_port: u16 = std::env::var("HEALTH_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8087);

    nexus_telemetry::metrics::init_metrics("kafka-event-service");

    let app = Router::new()
        .route("/health",  get({
            let p = pool.clone();
            let f = worker_alive.clone();
            move || health_handler(p.clone(), f.clone())
        }))
        .route("/metrics", get(metrics_handler));

    let addr = SocketAddr::from(([0, 0, 0, 0], health_port));
    info!("Health/metrics endpoint on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_handler(
    pool: PgPool,
    worker_alive: Arc<AtomicBool>,
) -> impl axum::response::IntoResponse {
    use axum::http::StatusCode;
    use serde_json::json;

    let db_ok     = sqlx::query("SELECT 1").fetch_one(&pool).await.is_ok();
    let worker_ok = worker_alive.load(Ordering::SeqCst);
    let healthy   = db_ok && worker_ok;

    let status = if healthy {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    (
        status,
        axum::Json(json!({
            "status":  if healthy { "ok" } else { "degraded" },
            "service": "kafka-event-service",
            "checks": {
                "database":      db_ok,
                "outbox_worker": worker_ok
            }
        })),
    )
}

async fn metrics_handler() -> String {
    nexus_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}
