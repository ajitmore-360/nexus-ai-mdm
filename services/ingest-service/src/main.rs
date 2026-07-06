mod config;
mod crypto;
mod jobs;
mod models;
mod pipeline;
mod processor;
mod scheduler;
mod source_systems;
mod sources;
mod state;

use std::{net::SocketAddr, sync::Arc};

use axum::{
    extract::{Extension, Path, Query, State},
    http::{HeaderName, HeaderValue, Method, Request, StatusCode, header::{AUTHORIZATION, CONTENT_TYPE}},
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{get, post, put},
    Router, Json,
};
use serde::Deserialize;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use nexus_auth::{Claims, jwt::JwtConfig};

use config::settings::IngestSettings;
use database::{config::DatabaseConfig, connection::create_pool};
use source_systems::{
    create_source_system, delete_source_system, list_source_systems,
    test_connection, update_source_system,
};
use sources::rest::{ingest_batch, ingest_csv, ingest_entities};
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    nexus_telemetry::tracing_init::init_tracing("ingest-service");
    nexus_telemetry::metrics::init_metrics("ingest-service");

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Ingest Service environment loaded");

    let settings = IngestSettings::from_env()
        .expect("failed to load ingest service settings");

    tracing::info!("Ingest Service starting on port {}", settings.port);

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
        if std::env::var("CONNECTION_CONFIG_KEY").is_err() {
            panic!(
                "SECURITY: CONNECTION_CONFIG_KEY is not set in APP_ENV={}. \
                 Source system credentials must be encrypted in production. \
                 Generate a base64-encoded 32-byte key: openssl rand -base64 32",
                app_env
            );
        }
    }

    let port = settings.port;

    let jwt_config = JwtConfig::from_env()
        .expect("JWT_SECRET must be set — ingest-service requires JWT authentication");

    let db_config = DatabaseConfig { database_url: settings.database_url.clone() };
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = Arc::new(AppState::new(settings, pool, jwt_config));

    // ── Scheduled REST pull loops ──────────────────────────────────────────────
    // Spawns one background task per REST connector configured with
    // sync_mode='scheduled'. No-op if none are registered.
    {
        let pool_for_sched = Arc::new(state.pool.clone());
        let proc_for_sched = Arc::clone(&state.processor);
        tokio::spawn(scheduler::start_scheduled_pulls(pool_for_sched, proc_for_sched));
    }

    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors = CorsLayer::new()
        .allow_origin(allowed_origins)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([CONTENT_TYPE, AUTHORIZATION, HeaderName::from_static("x-tenant-id"), HeaderName::from_static("x-request-id")])
        .allow_credentials(true);

    let protected = Router::new()
        .route("/ingest/batch",              post(ingest_batch))
        .route("/ingest/entities",           post(ingest_entities))
        .route("/ingest/csv",                post(ingest_csv))
        .route("/ingest/jobs",               get(list_ingest_jobs))
        .route("/ingest/jobs/:id",           get(get_ingest_job))
        .route("/source-systems",            get(list_source_systems).post(create_source_system))
        .route("/source-systems/:id",        put(update_source_system).delete(delete_source_system))
        .route("/source-systems/:id/test",   post(test_connection))
        .layer(axum::middleware::from_fn_with_state(Arc::clone(&state), jwt_auth_middleware));

    let app = Router::new()
        .route("/health",                    get(health))
        .route("/metrics",                   get(metrics_handler))
        .merge(protected)
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Ingest Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind ingest service");

    axum::serve(listener, app)
        .await
        .expect("ingest service crashed");
}

// ── Job status handlers ──────────────────────────────────────────────────────

#[derive(Deserialize)]
struct JobListParams {
    page:      Option<i64>,
    page_size: Option<i64>,
}

async fn list_ingest_jobs(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(params):     Query<JobListParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);

    match jobs::list_jobs(&state.pool, claims.nxs_tenant_id, page, page_size).await {
        Ok((items, total)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success":    true,
                "items":      items,
                "page":       page,
                "page_size":  page_size,
                "total":      total,
            })),
        ).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    }
}

async fn get_ingest_job(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(job_id):      Path<Uuid>,
) -> impl IntoResponse {
    match jobs::get_job(&state.pool, job_id, claims.nxs_tenant_id).await {
        Ok(Some(job)) => (
            StatusCode::OK,
            Json(serde_json::json!({ "success": true, "job": job })),
        ).into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({ "success": false, "error": "job not found" })),
        ).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "success": false, "error": e.to_string() })),
        ).into_response(),
    }
}

async fn jwt_auth_middleware(
    State(state): State<Arc<AppState>>,
    mut request:  Request<axum::body::Body>,
    next:         Next,
) -> Response {
    let token = request
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "));

    match token {
        None => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": "missing or malformed Authorization header" })),
        ).into_response(),
        Some(t) => match state.jwt_config.validate(t) {
            Err(_) => (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "invalid or expired token" })),
            ).into_response(),
            Ok(claims) => {
                request.extensions_mut().insert(claims);
                next.run(request).await
            }
        },
    }
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status":  "healthy",
        "service": "ingest-service",
    }))
}

async fn metrics_handler() -> String {
    nexus_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}
