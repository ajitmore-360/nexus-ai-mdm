mod admin;
mod config;
mod license;
mod onboarding;
mod schemas;

use std::net::SocketAddr;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderName, HeaderValue, Method, header::{AUTHORIZATION, CONTENT_TYPE}},
    routing::{get, post, put},
    Router, Json,
};
use serde::Deserialize;
use sqlx::PgPool;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use config::TenantServiceSettings;
use database::{config::DatabaseConfig, connection::create_pool};
use license::{active_features, import_license, generate_dev_license, is_feature_enabled, LicenseTier};
use onboarding::{onboard_organization, OnboardOrganizationRequest};
use schemas::{add_custom_attribute, available_entity_types, get_schema, CreateAttributeRequest};

#[derive(Clone)]
pub(crate) struct AppState {
    pub(crate) pool: PgPool,
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// HANDLERS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "tenant-service" }))
}

async fn metrics_handler() -> String {
    azile_telemetry::metrics::render_metrics()
        .unwrap_or_else(|e| format!("# metrics error: {}", e))
}

/// POST /tenants/onboard â€” Create a new organisation with admin user + sequences
async fn onboard(
    State(state): State<AppState>,
    Json(req):    Json<OnboardOrganizationRequest>,
) -> Json<serde_json::Value> {
    match onboard_organization(&state.pool, req).await {
        Ok(result) => Json(serde_json::json!({ "success": true, "data": result })),
        Err(e)     => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /tenants/entity-types â€” List all available entity types with metadata
async fn list_entity_types() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "data": available_entity_types()
    }))
}

/// GET /tenants/schemas/:entity_type?tenant_id= â€” Get merged attribute schema
#[derive(Deserialize)]
struct SchemaQuery { tenant_id: Uuid }

async fn get_entity_schema(
    State(state): State<AppState>,
    Path(entity_type): Path<String>,
    Query(q): Query<SchemaQuery>,
) -> Json<serde_json::Value> {
    match get_schema(&state.pool, q.tenant_id, &entity_type).await {
        Ok(schema) => Json(serde_json::json!({ "success": true, "data": schema })),
        Err(e)     => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /tenants/:tenant_id/schemas/:entity_type â€” Add custom attribute
async fn add_attribute(
    State(state):      State<AppState>,
    Path((tid, etype)): Path<(Uuid, String)>,
    Json(req):         Json<CreateAttributeRequest>,
) -> Json<serde_json::Value> {
    match add_custom_attribute(&state.pool, tid, &etype, req).await {
        Ok(id) => Json(serde_json::json!({ "success": true, "data": { "schema_id": id } })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /license/import â€” Import a signed license JWT
#[derive(Deserialize)]
struct ImportLicenseRequest { token: String, imported_by: Option<Uuid> }

async fn import_license_handler(
    State(state): State<AppState>,
    Json(req):    Json<ImportLicenseRequest>,
) -> Json<serde_json::Value> {
    match import_license(&state.pool, &req.token, req.imported_by).await {
        Ok(id) => Json(serde_json::json!({ "success": true, "data": { "license_id": id } })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /license â€” Get current active license info
async fn get_license(State(state): State<AppState>) -> Json<serde_json::Value> {
    let features = active_features(&state.pool).await;
    Json(serde_json::json!({
        "success":  true,
        "data": { "active_features": features, "feature_count": features.len() }
    }))
}

/// GET /license/check?feature= â€” Check if a specific feature is enabled
#[derive(Deserialize)]
struct FeatureQuery { feature: String }

async fn check_feature(
    State(state): State<AppState>,
    Query(q):     Query<FeatureQuery>,
) -> Json<serde_json::Value> {
    let enabled = is_feature_enabled(&state.pool, &q.feature).await;
    Json(serde_json::json!({ "success": true, "data": { "feature": q.feature, "enabled": enabled } }))
}

/// POST /license/generate-dev â€” Generate a development license (admin only)
#[derive(Deserialize)]
struct GenLicenseRequest { organization: String, tier: String, days_valid: Option<u32> }

async fn generate_license(Json(req): Json<GenLicenseRequest>) -> Json<serde_json::Value> {
    let tier = match req.tier.to_lowercase().as_str() {
        "community"    => LicenseTier::Community,
        "professional" => LicenseTier::Professional,
        "oem"          => LicenseTier::Oem,
        _              => LicenseTier::Enterprise,
    };
    match generate_dev_license(&req.organization, tier, req.days_valid) {
        Ok(token) => Json(serde_json::json!({ "success": true, "data": { "token": token } })),
        Err(e)    => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /tenants/:tenant_id/next-number/:entity_type â€” Get next business number
async fn next_number(
    State(state): State<AppState>,
    Path((tid, etype)): Path<(Uuid, String)>,
) -> Json<serde_json::Value> {
    match sqlx::query_scalar::<_, String>(
        "SELECT core_mdm.next_entity_number($1, $2)"
    )
    .bind(tid)
    .bind(&etype)
    .fetch_one(&state.pool)
    .await
    {
        Ok(number) => Json(serde_json::json!({ "success": true, "data": { "number": number } })),
        Err(e)     => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// MAIN
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    azile_telemetry::tracing_init::init_tracing("tenant-service");
    azile_telemetry::metrics::init_metrics("tenant-service");

    let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());
    tracing::info!(app_env = %app_env, "Tenant Service environment loaded");

    let settings = TenantServiceSettings::from_env().unwrap_or_else(|e| {
        eprintln!("[FATAL] Configuration error: {e}");
        std::process::exit(1);
    });
    tracing::info!("Tenant Service starting on port {}", settings.port);

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

    let db_config = DatabaseConfig { database_url: settings.database_url.clone() };
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = AppState { pool };

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
        .route("/health",                                     get(health))
        .route("/metrics",                                    get(metrics_handler))
        .route("/tenants/onboard",                            post(onboard))
        .route("/tenants/entity-types",                       get(list_entity_types))
        .route("/tenants/schemas/:entity_type",               get(get_entity_schema))
        .route("/tenants/:tenant_id/schemas/:entity_type",    post(add_attribute))
        .route("/tenants/:tenant_id/next-number/:entity_type",get(next_number))
        .route("/license",                                    get(get_license))
        .route("/license/import",                             post(import_license_handler))
        .route("/license/check",                              get(check_feature))
        .route("/license/generate-dev",                       post(generate_license))
        // â”€â”€ Admin routes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        .route("/admin/tenants",                              get(admin::list_tenants).post(admin::create_tenant))
        .route("/admin/tenants/:id/admin-user",               post(admin::create_admin_user))
        .route("/admin/users",                                get(admin::list_users))
        .route("/admin/users/invite",                         post(admin::invite_user))
        .route("/admin/users/:id/role",                       put(admin::update_user_role))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], settings.port));
    tracing::info!("Tenant Service listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind tenant service");

    axum::serve(listener, app)
        .await
        .expect("tenant service crashed");
}
