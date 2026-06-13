use axum::{
    extract::State,
    http::{
        HeaderValue,
        Method,
        StatusCode,
    },
    middleware as axum_middleware,
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
mod middleware;
mod services;
mod survivorship;

use std::sync::Arc;

use handlers::{
    dashboard::{get_activity_feed, get_dashboard_stats},
    entities::{create_entity, get_entity_by_id, list_entities, patch_entity},
    matching::execute_match,
    merge::execute_merge,
    policy::{get_weights, update_weights},
    users::{change_role, list_users, login, register},
};
use middleware::{
    auth::auth_middleware,
    tenant::tenant_middleware,
};
use services::{
    entity_service::EntityService,
    golden_record_service::GoldenRecordService,
    matching_service::MatchingService,
    merge_service::MergeService,
    review_service::ReviewService,
    survivorship_service::SurvivorshipService,
};
use matching::{
    Matcher,
    MatchingPolicy,
};

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

    pub matching_service:
        Arc<MatchingService>,

    pub entity_service:
        Arc<EntityService>,

    pub merge_service:
        Arc<MergeService>,

    pub golden_record_service:
        Arc<GoldenRecordService>,

    pub survivorship_service:
        Arc<SurvivorshipService>,

    pub review_service:
        Arc<ReviewService>,

    /// Live matching policy — can be updated at runtime via PATCH /policy/weights
    /// without restarting the service.
    pub matching_policy: Arc<std::sync::RwLock<matching::MatchingPolicy>>,

    /// Optional Redis-backed rate limiter for brute-force protection on /auth/login.
    pub redis_rate_limiter: Option<Arc<nexus_redis::RedisRateLimiter>>,
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

    let protected = Router::new()
        .route("/entities",     get(list_entities).post(create_entity))
        .route("/entities/:id", get(get_entity_by_id).patch(patch_entity))
        .route("/match", post(execute_match))
        .route("/merge", post(execute_merge))
        // /search is served by the dedicated search-service via api-gateway
        .layer(axum_middleware::from_fn(tenant_middleware))
        .layer(axum_middleware::from_fn(auth_middleware));

    // Public auth routes — no tenant/auth middleware
    let auth_routes = Router::new()
        .route("/auth/login",    axum::routing::post(login))
        .route("/auth/register", axum::routing::post(register));

    // Protected user management + policy routes
    let management_routes = Router::new()
        .route("/users",                  axum::routing::get(list_users))
        .route("/users/:id/role",         axum::routing::patch(change_role))
        .route("/policy/weights",         axum::routing::get(get_weights).patch(update_weights))
        .route("/dashboard/stats",        axum::routing::get(get_dashboard_stats))
        .route("/dashboard/activity",     axum::routing::get(get_activity_feed))
        .layer(axum_middleware::from_fn(tenant_middleware))
        .layer(axum_middleware::from_fn(auth_middleware));

    Router::new()
        .route("/health",       get(health))
        .route("/health/live",  get(liveness))
        .route("/health/ready", get(readiness))
        .merge(auth_routes)
        .merge(management_routes)
        .merge(protected)
        .layer(TraceLayer::new_for_http())
        .layer(cors)
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
    // RUN MIGRATIONS
    // ====================================
    // mdm-core is the schema owner: it runs all SQLx migrations
    // before any repositories or services are initialised.
    // This is idempotent — already-applied migrations are skipped.
    //

    info!("Running database migrations...");

    database::migration::run_migrations(&db)
        .await
        .unwrap_or_else(|e| {
            // Log but do not panic — init scripts may have already
            // created tables, and the migration might report a
            // conflict that is actually safe to ignore in dev.
            tracing::warn!(error=%e, "migration step reported a warning (continuing)");
        });

    info!("Database migrations complete");

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

    let matching_repository_arc =
        Arc::new(matching_repository.clone());

    // Single live policy behind RwLock — shared by both Matcher (reads snapshots)
    // and AppState (PATCH /policy/weights updates it at runtime).
    // No frozen copy exists; every match execution reads the current weights.
    let live_policy = Arc::new(std::sync::RwLock::new(MatchingPolicy::default()));

    let matcher = Arc::new(Matcher::new(
        matching_repository_arc,
        Arc::clone(&live_policy),
    ));

    let matching_service =
        Arc::new(MatchingService::new(matcher));

    // Redis — entity cache, task queue, and login rate limiter (all optional)
    let (entity_cache, task_queue, login_rate_limiter) = {
        use nexus_redis::{create_pool, EntityCache, RedisConfig, RedisRateLimiter, TaskQueue};
        let cfg = RedisConfig::from_env();
        match create_pool(&cfg) {
            Ok(pool) => {
                let cache   = Arc::new(EntityCache::new(pool.clone(), &cfg.key_prefix));
                let queue   = Arc::new(TaskQueue::new(pool.clone(), cfg.key_prefix.clone()));
                // Login: max 10 attempts per 5-minute window per IP+email combo
                let limiter = Arc::new(RedisRateLimiter::new(pool, cfg.key_prefix.clone(), 10, 300));
                tracing::info!("Redis connected — entity cache, task queue, and login rate limiter enabled");
                (Some(cache), Some(queue), Some(limiter))
            }
            Err(e) => {
                tracing::warn!(error=%e, "Redis unavailable — login rate limiting disabled");
                (None, None, None)
            }
        }
    };
    let entity_cache = entity_cache;
    let task_queue   = task_queue;

    let entity_service = Arc::new(
        EntityService::new(
            db.clone(),
            Arc::new(entity_repository.clone()),
            task_queue,
        )
        .with_cache_opt(entity_cache),
    );

    let merge_service = Arc::new(MergeService::new(
        db.clone(),
        Arc::new(entity_repository.clone()),
        Arc::new(golden_record_repository.clone()),
    ));

    let golden_record_service = Arc::new(GoldenRecordService::new(
        db.clone(),
        Arc::new(golden_record_repository.clone()),
    ));

    let survivorship_service = Arc::new(SurvivorshipService::new(
        Arc::new(survivorship_repository.clone()),
    ));

    let review_service = Arc::new(ReviewService::new(
        db.clone(),
        Arc::new(matching_repository.clone()),
    ));

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

            matching_service,
            entity_service,
            merge_service,
            golden_record_service,
            survivorship_service,
            review_service,
            matching_policy:    live_policy,
            redis_rate_limiter: login_rate_limiter,
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