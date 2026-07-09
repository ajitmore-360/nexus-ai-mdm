mod connectors;
mod processor;

use std::net::SocketAddr;

use axum::{
    extract::{Path, Query},
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

async fn metrics_handler() -> String {
    azile_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}

/// POST /jobs  â€” enqueue a distribution job from another service
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

#[derive(Deserialize)]
struct ListJobsParams {
    tenant_id: Uuid,
    status:    Option<String>,
    limit:     Option<i64>,
    offset:    Option<i64>,
}

/// GET /jobs?tenant_id=&status=&limit=&offset=
async fn list_jobs(
    axum::extract::State(pool): axum::extract::State<sqlx::PgPool>,
    Query(params): Query<ListJobsParams>,
) -> Json<serde_json::Value> {
    let limit  = params.limit.unwrap_or(20).clamp(1, 100);
    let offset = params.offset.unwrap_or(0).max(0);

    let result = if let Some(ref status) = params.status {
        sqlx::query_as::<_, (Uuid, Uuid, Uuid, Uuid, String, String, i32, Option<String>, chrono::DateTime<chrono::Utc>)>(
            r#"
            SELECT job_id, tenant_id, connector_id, entity_id, entity_type,
                   status, attempts, error_message, created_at
            FROM platform.distribution_jobs
            WHERE tenant_id = $1 AND status = $2
            ORDER BY created_at DESC
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(params.tenant_id)
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(&pool)
        .await
    } else {
        sqlx::query_as::<_, (Uuid, Uuid, Uuid, Uuid, String, String, i32, Option<String>, chrono::DateTime<chrono::Utc>)>(
            r#"
            SELECT job_id, tenant_id, connector_id, entity_id, entity_type,
                   status, attempts, error_message, created_at
            FROM platform.distribution_jobs
            WHERE tenant_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(params.tenant_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&pool)
        .await
    };

    match result {
        Ok(rows) => {
            let jobs: Vec<serde_json::Value> = rows.into_iter().map(|(job_id, tenant_id, connector_id, entity_id, entity_type, status, attempts, error_message, created_at)| {
                serde_json::json!({
                    "job_id":        job_id,
                    "tenant_id":     tenant_id,
                    "connector_id":  connector_id,
                    "entity_id":     entity_id,
                    "entity_type":   entity_type,
                    "status":        status,
                    "attempts":      attempts,
                    "error_message": error_message,
                    "created_at":    created_at,
                })
            }).collect();
            Json(serde_json::json!({ "success": true, "data": { "items": jobs, "limit": limit, "offset": offset } }))
        }
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /jobs/:job_id?tenant_id=
async fn get_job(
    axum::extract::State(pool): axum::extract::State<sqlx::PgPool>,
    Path(job_id): Path<Uuid>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Json<serde_json::Value> {
    let tenant_id = match params.get("tenant_id").and_then(|s| Uuid::parse_str(s).ok()) {
        Some(id) => id,
        None => return Json(serde_json::json!({ "success": false, "error": "tenant_id is required" })),
    };

    match sqlx::query(
        r#"
        SELECT job_id, tenant_id, connector_id, entity_id, entity_type,
               payload, status, attempts, error_message, scheduled_at,
               completed_at, created_at
        FROM platform.distribution_jobs
        WHERE job_id = $1 AND tenant_id = $2
        "#,
    )
    .bind(job_id)
    .bind(tenant_id)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(row)) => {
            use sqlx::Row;
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "job_id":        row.try_get::<Uuid,_>("job_id").ok(),
                    "tenant_id":     row.try_get::<Uuid,_>("tenant_id").ok(),
                    "connector_id":  row.try_get::<Uuid,_>("connector_id").ok(),
                    "entity_id":     row.try_get::<Uuid,_>("entity_id").ok(),
                    "entity_type":   row.try_get::<String,_>("entity_type").ok(),
                    "payload":       row.try_get::<serde_json::Value,_>("payload").ok(),
                    "status":        row.try_get::<String,_>("status").ok(),
                    "attempts":      row.try_get::<i32,_>("attempts").ok(),
                    "error_message": row.try_get::<Option<String>,_>("error_message").ok().flatten(),
                    "scheduled_at":  row.try_get::<chrono::DateTime<chrono::Utc>,_>("scheduled_at").ok(),
                    "completed_at":  row.try_get::<Option<chrono::DateTime<chrono::Utc>>,_>("completed_at").ok().flatten(),
                    "created_at":    row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").ok(),
                }
            }))
        }
        Ok(None) => Json(serde_json::json!({ "success": false, "error": "job not found" })),
        Err(e)   => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    azile_telemetry::tracing_init::init_tracing("distribution-service");
    azile_telemetry::metrics::init_metrics("distribution-service");

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
            panic!(
                "SECURITY: FIELD_ENCRYPTION_KEY is not set in APP_ENV={}. \
                 PII data must be encrypted in production. \
                 Generate a 32-byte key: openssl rand -hex 32",
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
        .route("/health",     get(health))
        .route("/metrics",    get(metrics_handler))
        .route("/jobs",       get(list_jobs).post(enqueue_job))
        .route("/jobs/:id",   get(get_job))
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
