mod config;
mod license;
mod onboarding;
mod schemas;

use std::net::SocketAddr;

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Router, Json,
};
use serde::Deserialize;
use sqlx::PgPool;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use config::TenantServiceSettings;
use database::{config::DatabaseConfig, connection::create_pool};
use license::{active_features, import_license, generate_dev_license, is_feature_enabled, LicenseTier};
use onboarding::{onboard_organization, OnboardOrganizationRequest};
use schemas::{add_custom_attribute, available_entity_types, get_schema, CreateAttributeRequest};

#[derive(Clone)]
struct AppState {
    pool: PgPool,
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS
// ─────────────────────────────────────────────────────────────────────────────

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "healthy", "service": "tenant-service" }))
}

/// POST /tenants/onboard — Create a new organisation with admin user + sequences
async fn onboard(
    State(state): State<AppState>,
    Json(req):    Json<OnboardOrganizationRequest>,
) -> Json<serde_json::Value> {
    match onboard_organization(&state.pool, req).await {
        Ok(result) => Json(serde_json::json!({ "success": true, "data": result })),
        Err(e)     => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

/// GET /tenants/entity-types — List all available entity types with metadata
async fn list_entity_types() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "data": available_entity_types()
    }))
}

/// GET /tenants/schemas/:entity_type?tenant_id= — Get merged attribute schema
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

/// POST /tenants/:tenant_id/schemas/:entity_type — Add custom attribute
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

/// POST /license/import — Import a signed license JWT
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

/// GET /license — Get current active license info
async fn get_license(State(state): State<AppState>) -> Json<serde_json::Value> {
    let features = active_features(&state.pool).await;
    Json(serde_json::json!({
        "success":  true,
        "data": { "active_features": features, "feature_count": features.len() }
    }))
}

/// GET /license/check?feature= — Check if a specific feature is enabled
#[derive(Deserialize)]
struct FeatureQuery { feature: String }

async fn check_feature(
    State(state): State<AppState>,
    Query(q):     Query<FeatureQuery>,
) -> Json<serde_json::Value> {
    let enabled = is_feature_enabled(&state.pool, &q.feature).await;
    Json(serde_json::json!({ "success": true, "data": { "feature": q.feature, "enabled": enabled } }))
}

/// POST /license/generate-dev — Generate a development license (admin only)
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

/// GET /tenants/:tenant_id/next-number/:entity_type — Get next business number
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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("tenant_service=info".parse().unwrap()),
        )
        .init();

    let settings = TenantServiceSettings::from_env();
    tracing::info!("Tenant Service starting on port {}", settings.port);

    let db_config = DatabaseConfig { database_url: settings.database_url.clone() };
    let pool = create_pool(&db_config)
        .await
        .expect("failed to connect to PostgreSQL");

    let state = AppState { pool };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health",                                     get(health))
        .route("/tenants/onboard",                            post(onboard))
        .route("/tenants/entity-types",                       get(list_entity_types))
        .route("/tenants/schemas/:entity_type",               get(get_entity_schema))
        .route("/tenants/:tenant_id/schemas/:entity_type",    post(add_attribute))
        .route("/tenants/:tenant_id/next-number/:entity_type",get(next_number))
        .route("/license",                                    get(get_license))
        .route("/license/import",                             post(import_license_handler))
        .route("/license/check",                              get(check_feature))
        .route("/license/generate-dev",                       post(generate_license))
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
