mod config;
mod middleware;
mod proxy;
mod routes;
mod services;
mod state;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::{
    http::{HeaderValue, HeaderName, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    middleware as axum_middleware,
    routing::{delete, get, patch, post, put},
    Router,
};

use tower_http::cors::CorsLayer;

use config::settings::Settings;

use middleware::{
    auth::auth_middleware,
    logging::logging_middleware,
    rate_limit::{rate_limit_middleware, InMemoryRateLimiter},
    request_id::request_id_middleware,
    tenant::tenant_middleware,
};

use nexus_redis::{create_pool as create_redis_pool, RedisConfig, RedisRateLimiter, SessionStore};

use routes::{
    ai::copilot,
    auth::{login, me, refresh},
    health::{health, prometheus_metrics},
    mdm::{create_entity, execute_match},
    service_proxy::{
        // existing
        approve_match_candidate, autocomplete, create_policy_rule,
        dashboard_activity, dashboard_stats,
        enqueue_distribution, evaluate_policy, execute_merge, gdpr_access, gdpr_erasure,
        get_distribution_job, get_entity_by_id, get_entity_lineage,
        get_match_review_queue, get_policy_weights,
        ingest_batch, ingest_csv, ingest_entities,
        list_consent, list_distribution_jobs, list_entities, list_policy_rules,
        patch_entity, record_consent, recommend_weights,
        reject_match_candidate, scan_anomalies, search,
        update_policy_weights, withdraw_consent,
        // admin — tenant management
        admin_list_tenants, admin_create_tenant, admin_create_admin_user,
        admin_list_users, admin_invite_user, admin_update_user_role,
        // admin — entity types & attributes
        list_entity_types, create_entity_type, update_entity_type, delete_entity_type,
        list_attributes, create_attribute, delete_attribute, reorder_attributes, next_sequence,
        // admin — source systems
        list_source_systems, create_source_system, update_source_system,
        delete_source_system, test_source_system,
    },
};

use services::ServiceClients;
use state::AppState;

#[tokio::main]
async fn main() {

    dotenvy::dotenv().ok();

    // ---- Tracing -----------------------------------------------------------
    nexus_telemetry::tracing_init::init_tracing("api-gateway");

    // ---- Config ------------------------------------------------------------
    let settings = Settings::from_env();

    // ── Production safety guard ──────────────────────────────────────────────
    // Refuse to start with insecure configuration in non-development environments.
    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    let auth_disabled = std::env::var("AUTH_DISABLED")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if auth_disabled && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage") {
        panic!(
            "SECURITY: AUTH_DISABLED=true is not permitted in APP_ENV={}. \
             Set AUTH_DISABLED=false and configure JWT_SECRET.",
            app_env
        );
    }

    if auth_disabled {
        tracing::warn!(
            "⚠️  AUTH_DISABLED=true — all authentication checks are bypassed. \
             This MUST NOT be used in production."
        );
    }

    tracing::info!(app_env = %app_env, "API Gateway environment loaded");
    tracing::info!("API Gateway starting on port {}", settings.gateway_port);

    let allowed_origins_raw_gw = std::env::var("ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000".to_string());
    if matches!(app_env.as_str(), "production" | "prod" | "staging" | "stage") {
        if allowed_origins_raw_gw.contains("localhost") {
            panic!(
                "SECURITY: ALLOWED_ORIGINS contains 'localhost' in APP_ENV={}. Set to your production domain.",
                app_env
            );
        }
    }

    // ---- Redis (optional) --------------------------------------------------
    let redis_cfg = RedisConfig::from_env();
    let (redis_rate_limiter, session_store) =
        match create_redis_pool(&redis_cfg) {
            Ok(pool) => {
                tracing::info!("Redis connected at {}", redis_cfg.url);
                let limiter = Arc::new(RedisRateLimiter::new(
                    pool.clone(),
                    redis_cfg.key_prefix.clone(),
                    100,
                    60,
                ));
                let sessions = Arc::new(SessionStore::new(
                    pool,
                    redis_cfg.key_prefix.clone(),
                ));
                (Some(limiter), Some(sessions))
            }
            Err(e) => {
                tracing::warn!(error=%e, "Redis unavailable; using in-memory fallbacks");
                (None, None)
            }
        };

    // ---- Service clients ---------------------------------------------------
    let services = ServiceClients::new();

    // ---- App state ---------------------------------------------------------
    let state = AppState {
        settings:           settings.clone(),
        services,
        rate_limiter:       InMemoryRateLimiter::new(),
        redis_rate_limiter,
        session_store,
    };

    // ---- CORS --------------------------------------------------------------
    // ALLOWED_ORIGINS accepts a comma-separated list of origins, e.g.
    // "http://localhost:3000,http://localhost:4000"
    let allowed_origins: Vec<HeaderValue> = allowed_origins_raw_gw
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();

    let cors = CorsLayer::new()
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
        .allow_credentials(true)
        // Do not cache preflight in dev so origin list changes take effect immediately.
        // For production set this to a longer value (e.g. 600) via the env.
        .max_age(std::time::Duration::from_secs(
            std::env::var("CORS_MAX_AGE")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(0),
        ));

    // ---- Routes ------------------------------------------------------------
    // Middleware order (outermost applied last → executes first):
    //   request_id → logging → rate_limit → tenant → auth → handler
    let protected_routes = Router::new()
        // ── MDM Core ──────────────────────────────────────────────────
        .route("/entities",              get(list_entities).post(create_entity))
        .route("/entities/:id",          get(get_entity_by_id).patch(patch_entity))
        .route("/match",                 post(execute_match))
        .route("/match/review-queue",    get(get_match_review_queue))
        .route("/match/:rid/candidates/:cid/approve", post(approve_match_candidate))
        .route("/match/:rid/candidates/:cid/reject",  post(reject_match_candidate))
        // ── AI Copilot ────────────────────────────────────────────────
        .route("/copilot",               post(copilot))
        .route("/weights/recommend",     get(recommend_weights))
        .route("/anomalies",             get(scan_anomalies))
        // ── Dashboard ─────────────────────────────────────────────────
        .route("/dashboard/stats",       get(dashboard_stats))
        .route("/dashboard/activity",    get(dashboard_activity))
        // ── Search ────────────────────────────────────────────────────
        .route("/search",                get(search))
        .route("/search/autocomplete",   get(autocomplete))
        // ── Policy ────────────────────────────────────────────────────
        .route("/policy/evaluate",       post(evaluate_policy))
        .route("/policy/rules",          get(list_policy_rules).post(create_policy_rule))
        .route("/policy/gdpr/erasure",   post(gdpr_erasure))
        .route("/policy/gdpr/access",    post(gdpr_access))
        .route("/policy/weights",        get(get_policy_weights).patch(update_policy_weights))
        .route("/merge",                 post(execute_merge))
        // ── Ingest ────────────────────────────────────────────────────
        .route("/ingest/batch",          post(ingest_batch))
        .route("/ingest/entities",       post(ingest_entities))
        .route("/ingest/csv",            post(ingest_csv))
        // ── Distribution ─────────────────────────────────────────────
        .route("/distribution/jobs",             get(list_distribution_jobs).post(enqueue_distribution))
        .route("/distribution/jobs/:id",         get(get_distribution_job))
        // ── Consent ───────────────────────────────────────────────────
        .route("/policy/consent",                get(list_consent).post(record_consent))
        .route("/policy/consent/:id/withdraw",   post(withdraw_consent))
        // ── Lineage ───────────────────────────────────────────────────
        .route("/entities/:id/lineage",          get(get_entity_lineage))
        // ── Admin: Tenant Management ──────────────────────────────────
        .route("/admin/tenants",                 get(admin_list_tenants).post(admin_create_tenant))
        .route("/admin/tenants/:id/admin-user",  post(admin_create_admin_user))
        .route("/admin/users",                   get(admin_list_users))
        .route("/admin/users/invite",            post(admin_invite_user))
        .route("/admin/users/:id/role",          put(admin_update_user_role))
        // ── Admin: Entity Types & Attributes ──────────────────────────
        .route("/entity-types",                          get(list_entity_types).post(create_entity_type))
        .route("/entity-types/:id",                      patch(update_entity_type).delete(delete_entity_type))
        .route("/entity-types/:code/attributes",         get(list_attributes).post(create_attribute))
        .route("/entity-types/:code/attributes/order",   put(reorder_attributes))
        .route("/entity-types/:code/attributes/:id",     delete(delete_attribute))
        .route("/entity-types/:code/next-sequence",      get(next_sequence))
        // ── Admin: Source Systems ─────────────────────────────────────
        .route("/source-systems",        get(list_source_systems).post(create_source_system))
        .route("/source-systems/:id",    put(update_source_system).delete(delete_source_system))
        .route("/source-systems/:id/test", post(test_source_system))
        .layer(axum_middleware::from_fn_with_state(state.clone(), auth_middleware))
        .layer(axum_middleware::from_fn_with_state(state.clone(), tenant_middleware))
        .layer(axum_middleware::from_fn_with_state(state.clone(), rate_limit_middleware))
        .layer(axum_middleware::from_fn(logging_middleware))
        .layer(axum_middleware::from_fn(request_id_middleware));

    // Initialise metrics for Prometheus scraping
    nexus_telemetry::metrics::init_metrics("api-gateway");

    // Public routes — no auth required
    let public_routes = Router::new()
        .route("/health",       get(health))
        .route("/metrics",      get(prometheus_metrics))
        .route("/auth/login",   axum::routing::post(login))
        .route("/auth/refresh", axum::routing::post(refresh));

    // All business routes under /v1 — public ones at root for backward compat
    // Request body size limits — prevent DoS via oversized payloads
    // Normal MDM entities: typically < 64 KB
    // Batch ingest: handled separately with its own limit in ingest-service
    let body_limit = tower_http::limit::RequestBodyLimitLayer::new(
        10 * 1024 * 1024, // 10 MB hard limit on the gateway
    );

    let app = Router::new()
        .merge(public_routes)
        // v1 API — all versioned routes live here
        // Security headers applied to every response
        .nest("/v1", Router::new()
            .route("/auth/me",         get(me))
            .route("/auth/login",      axum::routing::post(login))
            .route("/auth/refresh",    axum::routing::post(refresh))
            .merge(protected_routes.clone())
        )
        // Legacy unversioned routes (no /v1 prefix) — kept for backward compat
        .route("/auth/me",  get(me))
        .nest("/", protected_routes)
        .with_state(state.clone())
        .layer(axum::middleware::from_fn(
            nexus_telemetry::security_headers::security_headers_middleware
        ))
        .layer(body_limit)
        .layer(cors);

    // ---- WebSocket ---------------------------------------------------------
    tokio::spawn(async move {
        if let Err(err) = ws::start_ws_server().await {
            tracing::error!("WS server failed: {:?}", err);
        }
    });

    // ---- Bind --------------------------------------------------------------
    let addr = SocketAddr::from(([0, 0, 0, 0], settings.gateway_port));
    tracing::info!("API Gateway listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind API Gateway");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("API Gateway crashed");
}

async fn shutdown_signal() {
    use tokio::signal;

    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("shutdown signal received");
}
