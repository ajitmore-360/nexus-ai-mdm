use axum::{
    extract::State,
    http::{
        HeaderValue,
        Method,
        StatusCode,
    },
    response::IntoResponse,
    routing::{
        get,
        post,
    },
    Json,
    Router,
};

use dotenvy::dotenv;

use serde_json::json;

use sqlx::{
    postgres::PgPoolOptions,
    PgPool,
};

use std::{
    env,
    net::SocketAddr,
    sync::Arc,
    time::Duration,
};

use tower_http::{
    cors::CorsLayer,
    trace::TraceLayer,
};

use tracing::{
    error,
    info,
};

use tracing_subscriber::{
    layer::SubscriberExt,
    util::SubscriberInitExt,
};

use uuid::Uuid;

use crate::db::repositories::{
    entity_repository::EntityRepository,
    event_repository::EventRepository,
    golden_record_repository::GoldenRecordRepository,
    matching_repository::MatchingRepository,
    survivorship_repository::SurvivorshipRepository,
    tenant_repository::TenantRepository,
};

mod db;
mod handlers;
mod matching;
mod survivorship;

//
// ========================================
// APPLICATION STATE
// ========================================
//

#[derive(Clone)]
pub struct AppState {

    //
    // PostgreSQL Pool
    //
    pub db:
        PgPool,

    //
    // Repositories
    //
    pub entity_repository:
        EntityRepository,

    pub event_repository:
        EventRepository,

    pub golden_record_repository:
        GoldenRecordRepository,

    pub matching_repository:
        MatchingRepository,

    pub survivorship_repository:
        SurvivorshipRepository,

    pub tenant_repository:
        TenantRepository,
}

//
// ========================================
// HEALTH RESPONSE
// ========================================
//

#[derive(serde::Serialize)]
pub struct HealthResponse {

    pub status:
        String,

    pub service:
        String,

    pub version:
        String,

    pub database:
        String,

    pub timestamp:
        String,
}

//
// ========================================
// HEALTH CHECK
// ========================================
//

async fn health(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {

    let database_status =
        match sqlx::query("SELECT 1")
            .execute(&state.db)
            .await
        {
            Ok(_) => "healthy",
            Err(_) => "unhealthy",
        };

    let response =
        HealthResponse {

            status:
                "UP".to_string(),

            service:
                "nexus-ai-mdm-core"
                    .to_string(),

            version:
                env!(
                    "CARGO_PKG_VERSION"
                )
                .to_string(),

            database:
                database_status
                    .to_string(),

            timestamp:
                chrono::Utc::now()
                    .to_rfc3339(),
        };

    (
        StatusCode::OK,
        Json(response),
    )
}

//
// ========================================
// READY CHECK
// ========================================
//

async fn readiness(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {

    match sqlx::query("SELECT 1")
        .execute(&state.db)
        .await
    {
        Ok(_) => (
            StatusCode::OK,
            Json(
                json!({
                    "status": "READY"
                })
            ),
        ),

        Err(error) => {

            error!(
                "Readiness check failed: {:?}",
                error
            );

            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(
                    json!({
                        "status": "NOT_READY"
                    })
                ),
            )
        }
    }
}

//
// ========================================
// LIVE CHECK
// ========================================
//

async fn liveness() -> impl IntoResponse {

    (
        StatusCode::OK,
        Json(
            json!({
                "status": "ALIVE"
            })
        ),
    )
}

//
// ========================================
// INIT TRACING
// ========================================
//

fn init_tracing() {

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::new(
                env::var("RUST_LOG")
                    .unwrap_or_else(|_| {
                        "info".to_string()
                    })
            )
        )
        .with(
            tracing_subscriber::fmt::layer()
        )
        .init();
}

//
// ========================================
// CREATE DATABASE POOL
// ========================================
//

async fn create_database_pool(
    database_url: &str,
) -> PgPool {

    PgPoolOptions::new()

        //
        // Maximum connections
        //
        .max_connections(50)

        //
        // Minimum idle connections
        //
        .min_connections(5)

        //
        // Acquire timeout
        //
        .acquire_timeout(
            Duration::from_secs(10)
        )

        //
        // Idle timeout
        //
        .idle_timeout(
            Duration::from_secs(600)
        )

        //
        // Connection max lifetime
        //
        .max_lifetime(
            Duration::from_secs(1800)
        )

        //
        // Connect
        //
        .connect(database_url)
        .await
        .unwrap_or_else(|error| {

            error!(
                "Database connection failed: {:?}",
                error
            );

            panic!(
                "Unable to connect PostgreSQL"
            );
        })
}

//
// ========================================
// BUILD ROUTER
// ========================================
//

fn build_router(
    state: Arc<AppState>,
) -> Router {

    //
    // CORS
    //

    let cors =
        CorsLayer::new()

            .allow_origin(
                HeaderValue::from_static("*")
            )

            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PUT,
                Method::DELETE,
            ])

            .allow_headers(
                tower_http::cors::Any
            );

    Router::new()

        //
        // ====================================
        // HEALTH APIs
        // ====================================
        //

        .route(
            "/health",
            get(health)
        )

        .route(
            "/health/live",
            get(liveness)
        )

        .route(
            "/health/ready",
            get(readiness)
        )

        //
        // ====================================
        // ENTITY APIs
        // ====================================
        //

        .route(
            "/merge",
            post(handlers::merge)
        )

        .route(
            "/search",
            post(handlers::search)
        )

        //
        // ====================================
        // OBSERVABILITY
        // ====================================
        //

        .layer(
            TraceLayer::new_for_http()
        )

        .layer(cors)

        //
        // ====================================
        // APPLICATION STATE
        // ====================================
        //

        .with_state(state)
}

//
// ========================================
// STARTUP VALIDATION
// ========================================
//

async fn validate_startup(
    pool: &PgPool,
) {

    info!(
        "Running startup validation"
    );

    //
    // Verify PostgreSQL
    //

    sqlx::query("SELECT 1")
        .execute(pool)
        .await
        .unwrap_or_else(|error| {

            error!(
                "Startup DB validation failed: {:?}",
                error
            );

            panic!(
                "Database startup validation failed"
            );
        });

    info!(
        "Startup validation completed"
    );
}

//
// ========================================
// MAIN
// ========================================
//

#[tokio::main]
async fn main() {

    //
    // ====================================
    // LOAD ENVIRONMENT
    // ====================================
    //

    dotenv().ok();

    //
    // ====================================
    // INIT LOGGING
    // ====================================
    //

    init_tracing();

    info!(
        "Starting Nexus AI MDM Core"
    );

    //
    // ====================================
    // DATABASE URL
    // ====================================
    //

    let database_url =
        env::var("DATABASE_URL")
            .expect(
                "DATABASE_URL is missing"
            );

    //
    // ====================================
    // CREATE DATABASE POOL
    // ====================================
    //

    let db =
        create_database_pool(
            &database_url
        )
        .await;

    info!(
        "PostgreSQL connection established"
    );

    //
    // ====================================
    // STARTUP VALIDATION
    // ====================================
    //

    validate_startup(&db)
        .await;

    //
    // ====================================
    // INITIALIZE REPOSITORIES
    // ====================================
    //

    let entity_repository =
        EntityRepository::new(
            db.clone()
        );

    let event_repository =
        EventRepository::new(
            db.clone()
        );

    let golden_record_repository =
        GoldenRecordRepository::new(
            db.clone()
        );

    let matching_repository =
        MatchingRepository::new(
            db.clone()
        );

    let survivorship_repository =
        SurvivorshipRepository::new(
            db.clone()
        );

    let tenant_repository =
        TenantRepository::new(
            db.clone()
        );

    //
    // ====================================
    // BUILD APPLICATION STATE
    // ====================================
    //

    let state = Arc::new(
        AppState {

            db,

            entity_repository,

            event_repository,

            golden_record_repository,

            matching_repository,

            survivorship_repository,

            tenant_repository,
        }
    );

    //
    // ====================================
    // BUILD ROUTER
    // ====================================
    //

    let app =
        build_router(state);

    //
    // ====================================
    // SERVER CONFIG
    // ====================================
    //

    let host =
        env::var("MDM_CORE_HOST")
            .unwrap_or_else(|_| {
                "0.0.0.0".to_string()
            });

    let port =
        env::var("MDM_CORE_PORT")
            .unwrap_or_else(|_| {
                "8081".to_string()
            });

    let addr_string =
        format!(
            "{}:{}",
            host,
            port
        );

    let addr: SocketAddr =
        addr_string
            .parse()
            .unwrap_or_else(|error| {

                error!(
                    "Invalid server address: {:?}",
                    error
                );

                panic!(
                    "Invalid server configuration"
                );
            });

    //
    // ====================================
    // TCP LISTENER
    // ====================================
    //

    let listener =
        tokio::net::TcpListener::bind(
            addr
        )
        .await
        .unwrap_or_else(|error| {

            error!(
                "Failed to bind server: {}",
                error
            );

            panic!(
                "Unable to bind TCP listener"
            );
        });

    info!(
        "MDM Core listening on {}",
        addr
    );

    info!(
        "Environment: {}",
        env::var("APP_ENV")
            .unwrap_or_else(|_| {
                "development"
                    .to_string()
            })
    );

    info!(
        "Instance ID: {}",
        Uuid::new_v4()
    );

    //
    // ====================================
    // START SERVER
    // ====================================
    //

    axum::serve(
        listener,
        app,
    )
    .await
    .unwrap_or_else(|error| {

        error!(
            "MDM Core server failed: {}",
            error
        );

        panic!(
            "MDM Core crashed"
        );
    });
}