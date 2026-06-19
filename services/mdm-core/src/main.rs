use axum::{
    extract::State,
    http::{
        HeaderName,
        HeaderValue,
        Method,
        StatusCode,
        header::{AUTHORIZATION, CONTENT_TYPE},
    },
    middleware as axum_middleware,
    response::IntoResponse,
    routing::{
        delete,
        get,
        patch,
        post,
        put,
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
    warn,
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
    entity_types::{
        create_attribute, create_entity_type, delete_attribute, delete_entity_type,
        list_attributes, list_entity_types, next_sequence, reorder_attributes,
        update_entity_type,
    },
    lineage::{get_entity_lineage, record_lineage},
    matching::execute_match,
    merge::execute_merge,
    policy::{get_weights, update_weights},
    review::{approve_match, get_review_queue, reject_match},
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

    /// AES-256-GCM field-level encryption for PII attributes (email, phone, tax_id, etc.).
    /// None when FIELD_ENCRYPTION_KEY is not set — PII stored plaintext (dev mode only).
    pub field_encryption: Option<Arc<nexus_security::encryption::field_encryption::FieldEncryptionService>>,
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
    // CORS — env-driven, no wildcard in production
    //

    let allowed_origins: Vec<HeaderValue> = std::env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000,http://localhost:4000".to_string())
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors =
        CorsLayer::new()
            .allow_origin(allowed_origins)
            .allow_methods([
                Method::GET,
                Method::POST,
                Method::PUT,
                Method::PATCH,
                Method::DELETE,
                Method::OPTIONS,
            ])
            .allow_headers([
                CONTENT_TYPE,
                AUTHORIZATION,
                HeaderName::from_static("x-tenant-id"),
                HeaderName::from_static("x-request-id"),
            ])
            .allow_credentials(true);

    let protected = Router::new()
        .route("/entities",               get(list_entities).post(create_entity))
        .route("/entities/:id",           get(get_entity_by_id).patch(patch_entity))
        .route("/entities/:id/lineage",   get(get_entity_lineage))
        .route("/lineage",                post(record_lineage))
        .route("/match",                  post(execute_match))
        .route("/match/review-queue",     get(get_review_queue))
        .route("/match/:request_id/candidates/:candidate_id/approve", axum::routing::post(approve_match))
        .route("/match/:request_id/candidates/:candidate_id/reject",  axum::routing::post(reject_match))
        .route("/merge",                  post(execute_merge))
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
        // ── Entity type config admin routes ──────────────────────────────────
        .route("/entity-types",
            get(list_entity_types).post(create_entity_type))
        .route("/entity-types/:id",
            patch(update_entity_type).delete(delete_entity_type))
        // Attribute order route must come before the :attr_id route to avoid
        // Axum treating "order" as a UUID path segment.
        .route("/entity-types/:code/attributes/order",
            put(reorder_attributes))
        .route("/entity-types/:code/attributes",
            get(list_attributes).post(create_attribute))
        .route("/entity-types/:code/attributes/:attr_id",
            delete(delete_attribute))
        .route("/entity-types/:code/next-sequence",
            get(next_sequence))
        .layer(axum_middleware::from_fn(tenant_middleware))
        .layer(axum_middleware::from_fn(auth_middleware));

    Router::new()
        .route("/health",       get(health))
        .route("/health/live",  get(liveness))
        .route("/health/ready", get(readiness))
        .route("/metrics",      get(|| async {
            nexus_telemetry::metrics::render_metrics()
                .unwrap_or_else(|e| format!("# metrics error: {}", e))
        }))
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

    nexus_telemetry::tracing_init::init_tracing("mdm-core");
    nexus_telemetry::metrics::init_metrics("mdm-core");

    info!(
        "Starting Nexus AI MDM Core"
    );

    //
    // ====================================
    // PRODUCTION SAFETY GUARD
    // ====================================
    //

    let app_env = env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    info!(app_env = %app_env, "MDM Core environment loaded");

    let allowed_origins_raw = env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000,http://localhost:4000".to_string());
    if matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage") {
        if allowed_origins_raw.contains("localhost") {
            panic!(
                "SECURITY: ALLOWED_ORIGINS contains 'localhost' in APP_ENV={}. Set to your production domain.",
                app_env
            );
        }
        if env::var("FIELD_ENCRYPTION_KEY").is_err() {
            panic!(
                "SECURITY: FIELD_ENCRYPTION_KEY is not set in APP_ENV={}. \
                 PII data must be encrypted in production. \
                 Generate a 32-byte key: openssl rand -hex 32",
                app_env
            );
        }
    }

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

    // ── Field-level encryption ─────────────────────────────────────────────────
    // FIELD_ENCRYPTION_KEY must be exactly 32 bytes (256-bit), hex-encoded (64 chars).
    // If absent, PII attributes are stored plaintext — acceptable only in development.
    let field_encryption = match env::var("FIELD_ENCRYPTION_KEY") {
        Ok(hex_key) => {
            match hex::decode(&hex_key) {
                Ok(key_bytes) if key_bytes.len() == 32 => {
                    let key: [u8; 32] = key_bytes.try_into().expect("key is 32 bytes");
                    info!("Field-level encryption enabled (AES-256-GCM)");
                    Some(Arc::new(nexus_security::encryption::field_encryption::FieldEncryptionService::new(&key)))
                }
                Ok(_) => {
                    warn!("FIELD_ENCRYPTION_KEY must be 64 hex chars (32 bytes) — encryption disabled");
                    None
                }
                Err(e) => {
                    warn!(error=%e, "FIELD_ENCRYPTION_KEY is not valid hex — encryption disabled");
                    None
                }
            }
        }
        Err(_) => {
            warn!("FIELD_ENCRYPTION_KEY not set — PII attributes stored plaintext. Set in production.");
            None
        }
    };

    let entity_service = Arc::new(
        EntityService::new(
            db.clone(),
            Arc::new(entity_repository.clone()),
            task_queue,
        )
        .with_cache_opt(entity_cache)
        .with_encryption(field_encryption.clone()),
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
            field_encryption,
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