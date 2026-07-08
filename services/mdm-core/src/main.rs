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
mod workers;

#[cfg(test)]
mod tests;

use std::sync::Arc;

use handlers::{
    data_governance::{
        approve_entity, bulk_approve_entities, bulk_reject_entities,
        create_assignment, delete_assignment, list_assignments,
        list_pending_approvals, my_assigned_types, reject_entity, submit_for_review,
    },
    branding::{get_branding, upsert_branding},
    bulk::{bulk_export_entities, bulk_tag_entities, bulk_update_entity_status},
    comments::{add_entity_comment, delete_entity_comment, edit_entity_comment, list_entity_comments},
    distribution::{
        cancel_distribution_job, create_distribution_job, get_distribution_job,
        list_distribution_jobs, queue_distribution_job,
    },
    hierarchy::{
        get_entity_ancestors, get_entity_children, get_entity_subtree,
        get_hierarchy_roots, set_entity_parent,
    },
    notifications::{
        list_notifications, mark_all_read, mark_notification_read, unread_count,
    },
    admin::embed_migration,
    license::{activate_license, admin_upsert_license, get_my_license, internal_get_license},
    audit::list_audit_events,
    dashboard::{get_activity_feed, get_dashboard_stats, get_steward_performance, get_quality_dimensions},
    domain_policies::{
        delete_domain_policy, get_domain_policy, list_domain_policies, upsert_domain_policy,
    },
    entities::{create_entity, gdpr_erase_entity, get_entity_by_id, list_entities, patch_entity},
    entity_types::{
        create_attribute, create_entity_type, delete_attribute, delete_entity_type,
        list_attributes, list_entity_types, next_sequence, reorder_attributes,
        update_entity_type,
    },
    golden_records::{
        get_golden_record, list_golden_records, patch_golden_record_attributes,
    },
    lineage::{get_entity_lineage, lineage_graph, lineage_stats, list_lineage, record_lineage},
    matching::execute_match,
    merge::execute_merge,
    policy::{get_weights, update_weights, get_survivorship_suggestions, list_gdpr_requests},
    quality_analytics::{
        get_dimension_breakdown, get_quality_trends, get_source_quality_ranking,
        trigger_quality_snapshot,
    },
    relationships::{
        list_relationship_types, create_relationship_type, delete_relationship_type,
        list_entity_relationships, create_entity_relationship, delete_entity_relationship,
    },
    review::{
        approve_match, get_review_queue, reject_match,
        queue_metrics, bulk_approve_matches, bulk_reject_matches, defer_match, assign_review,
    },
    unmerge::{get_unmerge_history, unmerge_entity},
    users::{accept_invite, change_password, change_role, invite_info, invite_user, list_users,
            login, request_password_reset, reset_password, sso_exchange},
    submasters::{
        create_submaster_type, create_submaster_value, delete_submaster_value,
        list_submaster_types, list_submaster_values, update_submaster_type,
        update_submaster_value,
    },
    quality_rules::{
        list_quality_rules, create_quality_rule, update_quality_rule, delete_quality_rule,
        reorder_quality_rules, run_quality_rules,
        list_quality_violations, resolve_quality_violation, bulk_resolve_violations,
    },
    ai_suggestions::{
        trigger_address_parse, trigger_anomaly, trigger_enrichment,
        list_suggestions, approve_suggestion, reject_suggestion,
    },
    data_profiling::{get_profile, run_profile},
    reference_data::{
        list_reference_lists, create_reference_list,
        get_reference_values, upsert_reference_value, bulk_import_values, delete_reference_value,
    },
    tasks::{list_tasks, create_task, update_task, check_sla_breaches},
    temporal::{get_version_history, get_entity_as_of, get_entity_bitemporal},
    xref::{delete_entity_xref, list_entity_xrefs, lookup_by_xref, upsert_entity_xref},
};
use middleware::{
    auth::auth_middleware,
    tenant::tenant_middleware,
};
use services::{
    ai_suggestion_service::AiSuggestionService,
    audit_service::AuditService,
    branding_service::BrandingService,
    bulk_service::BulkService,
    comment_service::CommentService,
    data_quality_service::DataQualityService,
    distribution_service::DistributionService,
    hierarchy_service::HierarchyService,
    license_service::LicenseService,
    notification_service::NotificationService,
    domain_policy_service::DomainPolicyService,
    entity_service::EntityService,
    golden_record_service::GoldenRecordService,
    matching_service::MatchingService,
    merge_service::MergeService,
    data_profile_service::DataProfileService,
    quality_analytics_service::QualityAnalyticsService,
    reference_data_service::ReferenceDataService,
    relationship_service::RelationshipService,
    review_service::ReviewService,
    survivorship_service::SurvivorshipService,
    task_service::TaskService,
    temporal_service::TemporalService,
    unmerge_service::UnmergeService,
    xref_service::XrefService,
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

    pub domain_policy_service:
        Arc<DomainPolicyService>,

    pub relationship_service:
        Arc<RelationshipService>,

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

    pub audit_service:
        Arc<AuditService>,

    pub branding_service:
        Arc<BrandingService>,

    pub data_quality_service:
        Arc<DataQualityService>,

    pub ai_suggestion_service:
        Arc<AiSuggestionService>,

    pub distribution_service:
        Arc<DistributionService>,

    pub license_service:
        Arc<LicenseService>,

    pub notification_service:
        Arc<NotificationService>,

    pub bulk_service:
        Arc<BulkService>,

    pub comment_service:
        Arc<CommentService>,

    pub hierarchy_service:
        Arc<HierarchyService>,

    pub quality_analytics_service:
        Arc<QualityAnalyticsService>,

    pub data_profile_service:
        Arc<DataProfileService>,

    pub reference_data_service:
        Arc<ReferenceDataService>,

    pub task_service:
        Arc<TaskService>,

    pub temporal_service:
        Arc<TemporalService>,

    pub unmerge_service:
        Arc<UnmergeService>,

    pub xref_service:
        Arc<XrefService>,

    /// Live matching policy — can be updated at runtime via PATCH /policy/weights
    /// without restarting the service.
    pub matching_policy: Arc<std::sync::RwLock<matching::MatchingPolicy>>,

    /// Optional Redis-backed rate limiter for brute-force protection on /auth/login.
    pub redis_rate_limiter: Option<Arc<nexus_redis::RedisRateLimiter>>,

    /// Optional Redis task queue — used for re-embedding on PATCH and other async work.
    pub task_queue: Option<Arc<nexus_redis::TaskQueue>>,

    /// Optional Redis pub/sub publisher — broadcasts real-time events to the API gateway
    /// which fans them out to connected WebSocket clients on the `nexus:tenant:<id>` channel.
    pub pubsub: Option<Arc<nexus_redis::PubSubClient>>,

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
        // Hierarchy — static routes BEFORE /:id
        .route("/entities/hierarchy/roots",   get(get_hierarchy_roots))
        // Bulk operations — static routes BEFORE /:id to avoid route collision
        .route("/entities/bulk/status",       post(bulk_update_entity_status))
        .route("/entities/bulk/export",       post(bulk_export_entities))
        .route("/entities/bulk/tag",          post(bulk_tag_entities))
        // XRef lookup — static route BEFORE /:id
        .route("/xrefs/lookup",               get(lookup_by_xref))
        // Approval workflow — static routes BEFORE /:id to avoid Axum ambiguity
        .route("/entities/pending-approvals", get(list_pending_approvals))
        .route("/entities/bulk-approve",      post(bulk_approve_entities))
        .route("/entities/bulk-reject",       post(bulk_reject_entities))
        .route("/entities/:id/submit-for-review", post(submit_for_review))
        .route("/entities/:id/approve",           post(approve_entity))
        .route("/entities/:id/reject",            post(reject_entity))
        .route("/entities",               get(list_entities).post(create_entity))
        .route("/entities/:id",           get(get_entity_by_id).patch(patch_entity))
        .route("/entities/:id/gdpr-erase", delete(gdpr_erase_entity))
        .route("/entities/:id/lineage",   get(get_entity_lineage))
        .route("/lineage",                get(list_lineage).post(record_lineage))
        .route("/lineage/graph",          axum::routing::get(lineage_graph))
        .route("/lineage/stats",          axum::routing::get(lineage_stats))
        .route("/match",                  post(execute_match))
        .route("/match/review-queue",     get(get_review_queue))
        .route("/match/:request_id/candidates/:candidate_id/approve", axum::routing::post(approve_match))
        .route("/match/:request_id/candidates/:candidate_id/reject",  axum::routing::post(reject_match))
        .route("/match/queue-metrics",    get(queue_metrics))
        .route("/match/bulk-approve",     axum::routing::post(bulk_approve_matches))
        .route("/match/bulk-reject",      axum::routing::post(bulk_reject_matches))
        .route("/match/:request_id/candidates/:candidate_id/defer", axum::routing::post(defer_match))
        .route("/match/review-queue/:review_id/assign", patch(assign_review))
        .route("/merge",                  post(execute_merge))
        // Golden records — read + manual attribute override
        .route("/golden-records",         get(list_golden_records))
        .route("/golden-records/:id",     get(get_golden_record))
        .route("/golden-records/:id/attributes", patch(patch_golden_record_attributes))
        // Entity relationship routes
        .route("/entities/:id/relationships",     get(list_entity_relationships).post(create_entity_relationship))
        .route("/relationships/:id",              delete(delete_entity_relationship))
        // Cross-reference / ID mapping
        .route("/entities/:id/xrefs",             get(list_entity_xrefs).post(upsert_entity_xref))
        .route("/entities/:entity_id/xrefs/:xref_id", delete(delete_entity_xref))
        // Entity comments & collaboration
        .route("/entities/:id/comments",                           get(list_entity_comments).post(add_entity_comment))
        .route("/entities/:entity_id/comments/:comment_id",        patch(edit_entity_comment).delete(delete_entity_comment))
        // Unmerge / entity split
        .route("/entities/:id/unmerge",           post(unmerge_entity))
        .route("/entities/:id/unmerge-history",   get(get_unmerge_history))
        // Hierarchy
        .route("/entities/:id/children",          get(get_entity_children))
        .route("/entities/:id/ancestors",         get(get_entity_ancestors))
        .route("/entities/:id/subtree",           get(get_entity_subtree))
        .route("/entities/:id/parent",            patch(set_entity_parent))
        // Temporal / bitemporal records
        .route("/entities/:id/history",           get(get_version_history))
        .route("/entities/:id/as-of",             get(get_entity_as_of))
        .route("/entities/:id/bitemporal",        get(get_entity_bitemporal))
        // /search is served by the dedicated search-service via api-gateway
        .layer(axum_middleware::from_fn(tenant_middleware))
        .layer(axum_middleware::from_fn(auth_middleware));

    // Public auth routes — no tenant/auth middleware
    // NOTE: /auth/register intentionally omitted. Account creation requires an invite token
    // via /auth/accept-invite. Open self-registration is a security violation in a multi-tenant MDM.
    let auth_routes = Router::new()
        .route("/auth/login",            axum::routing::post(login))
        .route("/auth/accept-invite",    axum::routing::post(accept_invite))
        .route("/auth/invite-info",      axum::routing::get(invite_info))
        .route("/auth/forgot-password",  axum::routing::post(request_password_reset))
        .route("/auth/reset-password",   axum::routing::post(reset_password))
        .route("/auth/sso-exchange",     axum::routing::post(sso_exchange));

    // Protected user management + policy routes
    let management_routes = Router::new()
        .route("/auth/change-password",   axum::routing::post(change_password))
        .route("/users",                  axum::routing::get(list_users))
        .route("/users/invite",           axum::routing::post(invite_user))
        .route("/users/:id/role",         axum::routing::patch(change_role))
        .route("/policy/weights",                    axum::routing::get(get_weights).patch(update_weights))
        .route("/policy/survivorship-suggestions",   axum::routing::get(get_survivorship_suggestions))
        .route("/policy/gdpr/requests",              axum::routing::get(list_gdpr_requests))
        .route("/dashboard/stats",              axum::routing::get(get_dashboard_stats))
        .route("/dashboard/activity",           axum::routing::get(get_activity_feed))
        .route("/dashboard/steward-performance",   axum::routing::get(get_steward_performance))
        .route("/dashboard/quality-dimensions",    axum::routing::get(get_quality_dimensions))
        .route("/audit/events",           axum::routing::get(list_audit_events))
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
        // ── Domain-level policy overrides ─────────────────────────────────────
        .route("/domain-policies",
            get(list_domain_policies))
        .route("/domain-policies/:entity_type_code",
            get(get_domain_policy)
                .put(upsert_domain_policy)
                .delete(delete_domain_policy))
        // ── Relationship type config admin routes ─────────────────────────────
        .route("/relationship-types",
            get(list_relationship_types).post(create_relationship_type))
        .route("/relationship-types/:type_id",
            delete(delete_relationship_type))
        // ── License routes ────────────────────────────────────────────────────
        .route("/license",
            get(get_my_license))
        .route("/license/activate",
            post(activate_license))
        .route("/admin/tenants/:id/license",
            post(admin_upsert_license))
        .route("/admin/embed-migration",
            axum::routing::post(embed_migration))
        // ── Branding routes (Enterprise / white-label) ────────────────────────
        .route("/tenant/branding",
            get(get_branding).put(upsert_branding))
        // ── Notification inbox ────────────────────────────────────────────────
        .route("/notifications",
            get(list_notifications))
        .route("/notifications/unread-count",
            get(unread_count))
        .route("/notifications/:id/read",
            patch(mark_notification_read))
        .route("/notifications/read-all",
            post(mark_all_read))
        // ── Distribution jobs ─────────────────────────────────────────────────
        .route("/distribution/jobs",
            get(list_distribution_jobs).post(create_distribution_job))
        .route("/distribution/jobs/:id",
            get(get_distribution_job).delete(cancel_distribution_job))
        .route("/distribution/jobs/:id/queue",
            post(queue_distribution_job))
        // ── Submaster (reference data) management — Business Admin / Admin only ─
        .route("/submasters",
            get(list_submaster_types).post(create_submaster_type))
        .route("/submasters/:code",
            patch(update_submaster_type))
        .route("/submasters/:code/values",
            get(list_submaster_values).post(create_submaster_value))
        .route("/submasters/:code/values/:value_id",
            patch(update_submaster_value).delete(delete_submaster_value))
        // ── Data Governance — assignment CRUD (BusinessAdmin/Admin only) ──────
        .route("/governance/assignments",
            get(list_assignments).post(create_assignment))
        .route("/governance/assignments/my-types",
            get(my_assigned_types))
        .route("/governance/assignments/:id",
            delete(delete_assignment))
        // ── Quality analytics & trend scorecards ─────────────────────────────
        .route("/analytics/quality-trends",       axum::routing::get(get_quality_trends))
        .route("/analytics/quality-dimensions",   axum::routing::get(get_dimension_breakdown))
        .route("/analytics/source-quality",       axum::routing::get(get_source_quality_ranking))
        .route("/analytics/quality-snapshot",     axum::routing::post(trigger_quality_snapshot))
        // ── Quality rules & violations ────────────────────────────────────────
        .route("/quality-rules",
            get(list_quality_rules).post(create_quality_rule))
        .route("/quality-rules/reorder",
            post(reorder_quality_rules))
        .route("/quality-rules/run",
            post(run_quality_rules))
        .route("/quality-rules/:id",
            patch(update_quality_rule).delete(delete_quality_rule))
        .route("/quality-violations",
            get(list_quality_violations))
        .route("/quality-violations/bulk-resolve",
            post(bulk_resolve_violations))
        .route("/quality-violations/:id/resolve",
            patch(resolve_quality_violation))
        // ── AI suggestions (approval-gated LLM proposals) ─────────────────────
        .route("/ai-suggestions",
            get(list_suggestions))
        .route("/ai-suggestions/:id/approve",
            patch(approve_suggestion))
        .route("/ai-suggestions/:id/reject",
            patch(reject_suggestion))
        .route("/entities/:entity_id/ai-suggestions/address-parse",
            post(trigger_address_parse))
        .route("/entities/:entity_id/ai-suggestions/anomaly",
            post(trigger_anomaly))
        .route("/entities/:entity_id/ai-suggestions/enrichment",
            post(trigger_enrichment))
        // ── Data profiling (attribute-level statistics + outliers) ─────────────
        .route("/data-profiling/:entity_type",
            get(get_profile))
        .route("/data-profiling/:entity_type/run",
            post(run_profile))
        // ── Task assignment & SLA ─────────────────────────────────────────────
        .route("/tasks",
            get(list_tasks).post(create_task))
        .route("/tasks/:id",
            patch(update_task))
        .route("/tasks/check-sla",
            post(check_sla_breaches))
        // ── Reference data management (code lists) ────────────────────────────
        .route("/reference-data",
            get(list_reference_lists).post(create_reference_list))
        .route("/reference-data/:list_id/values",
            get(get_reference_values).post(upsert_reference_value))
        .route("/reference-data/:list_id/values/bulk",
            post(bulk_import_values))
        .route("/reference-data/:list_id/values/:value_id",
            delete(delete_reference_value))
        .layer(axum_middleware::from_fn(tenant_middleware))
        .layer(axum_middleware::from_fn(auth_middleware));

    // Internal no-auth route group — gateway-to-service only, not exposed publicly.
    let internal_routes = Router::new()
        .route("/internal/license/:tenant_id", get(internal_get_license));

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
        .merge(internal_routes)
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

    // Guard: reject known dev default JWT secret in non-dev environments.
    const KNOWN_DEV_JWT_SECRET: &str = "nexus-local-dev-jwt-secret-min-32-chars!!";
    let jwt_secret_val = env::var("JWT_SECRET").unwrap_or_default();
    if jwt_secret_val == KNOWN_DEV_JWT_SECRET
        && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage")
    {
        panic!(
            "SECURITY: JWT_SECRET is the well-known dev default. \
             Rotate it before deploying to APP_ENV={}. \
             Generate: openssl rand -hex 32",
            app_env
        );
    }

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

    match database::migration::run_migrations(&db).await {
        Ok(()) => {}
        Err(e) => {
            let msg = e.to_string();
            // Checksum mismatches mean a migration file was edited after being applied.
            // Tables still exist; log loudly and continue so the app can serve requests.
            // Any other migration error (connection failure, syntax error) is fatal.
            if msg.contains("checksum") || msg.contains("Checksum")
                || msg.contains("modified") || msg.contains("previously applied")
            {
                tracing::error!(
                    error = %e,
                    "Migration checksum mismatch — a migration file was modified after \
                     it was applied to this database. Re-run migrations against a clean DB \
                     or update the checksum in _sqlx_migrations to resolve. Continuing \
                     because tables were pre-applied."
                );
            } else {
                panic!("Database migration failed: {}", e);
            }
        }
    }

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

    // Optional SemanticClient — wired when AI_SERVICE_URL is set.
    // Falls back gracefully when absent: grey-zone candidates stay in RequiresReview.
    let semantic_client = env::var("AI_SERVICE_URL").ok().map(|url| {
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(35))
            .build()
            .expect("reqwest client build failed");
        crate::matching::SemanticClient::new(http, &url)
    });

    let matcher_base = Matcher::new(
        matching_repository_arc,
        Arc::clone(&live_policy),
    );
    let matcher = Arc::new(match semantic_client {
        Some(sc) => {
            info!("SemanticClient enabled — LLM grey-zone resolution active");
            matcher_base.with_semantic_client(sc)
        }
        None => {
            warn!("AI_SERVICE_URL not set — semantic matching disabled");
            matcher_base
        }
    });

    let matching_service =
        Arc::new(MatchingService::new(matcher));

    let domain_policy_service =
        Arc::new(DomainPolicyService::new(db.clone()));

    let relationship_service =
        Arc::new(RelationshipService::new(db.clone()));

    // Redis — entity cache, task queue, login rate limiter, and pub/sub publisher (all optional)
    let (entity_cache, task_queue, login_rate_limiter, pubsub_client) = {
        use nexus_redis::{create_pool, EntityCache, PubSubClient, RedisConfig, RedisRateLimiter, TaskQueue};
        let cfg = RedisConfig::from_env();
        match create_pool(&cfg) {
            Ok(pool) => {
                let cache   = Arc::new(EntityCache::new(pool.clone(), &cfg.key_prefix));
                let queue   = Arc::new(TaskQueue::new(pool.clone(), cfg.key_prefix.clone()));
                let pubsub  = Arc::new(PubSubClient::new(pool.clone(), cfg.key_prefix.clone()));
                // Login: max 10 attempts per 5-minute window per IP+email combo
                let limiter = Arc::new(RedisRateLimiter::new(pool, cfg.key_prefix.clone(), 10, 300));
                tracing::info!("Redis connected — entity cache, task queue, pub/sub, and login rate limiter enabled");
                (Some(cache), Some(queue), Some(limiter), Some(pubsub))
            }
            Err(e) => {
                tracing::warn!(error=%e, "Redis unavailable — login rate limiting disabled");
                (None, None, None, None)
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

    let task_queue_for_state = task_queue.clone();
    let entity_service = Arc::new(
        EntityService::new(
            db.clone(),
            Arc::new(entity_repository.clone()),
            task_queue,
        )
        .with_cache_opt(entity_cache)
        .with_encryption(field_encryption.clone()),
    );

    let merge_service = Arc::new({
        let svc = MergeService::new(
            db.clone(),
            Arc::new(entity_repository.clone()),
            Arc::new(golden_record_repository.clone()),
        );
        match task_queue_for_state.clone() {
            Some(q) => svc.with_task_queue(q),
            None    => svc,
        }
    });

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

    let license_service             = Arc::new(LicenseService::new(db.clone()));
    let branding_service            = Arc::new(BrandingService::new(db.clone()));
    let audit_service               = Arc::new(AuditService::new(db.clone()));
    let notification_service        = Arc::new(NotificationService::new(db.clone()));
    let data_quality_service        = Arc::new(DataQualityService::new(db.clone()));
    let distribution_service        = Arc::new(DistributionService::new(db.clone()));
    let bulk_service                = Arc::new(BulkService::new(db.clone()));
    let comment_service             = Arc::new(CommentService::new(db.clone()));
    let hierarchy_service           = Arc::new(HierarchyService::new(db.clone()));
    let quality_analytics_service   = Arc::new(QualityAnalyticsService::new(db.clone()));
    let unmerge_service             = Arc::new(UnmergeService::new(db.clone()));
    let xref_service                = Arc::new(XrefService::new(db.clone()));
    let data_profile_service        = Arc::new(DataProfileService::new(db.clone()));
    let reference_data_service      = Arc::new(ReferenceDataService::new(db.clone()));
    let task_service                = Arc::new(TaskService::new(db.clone()));
    let temporal_service            = Arc::new(TemporalService::new(db.clone()));
    let ai_service_url        = std::env::var("AI_SERVICE_URL")
        .unwrap_or_else(|_| "http://ai-service:8082".to_string());
    let ai_suggestion_service = Arc::new(AiSuggestionService::new(db.clone(), ai_service_url));

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

            domain_policy_service,
            relationship_service,
            matching_service,
            entity_service,
            merge_service,
            golden_record_service,
            survivorship_service,
            review_service,
            license_service,
            branding_service,
            audit_service,
            notification_service,
            data_quality_service,
            ai_suggestion_service,
            distribution_service,
            bulk_service,
            comment_service,
            hierarchy_service,
            quality_analytics_service,
            data_profile_service,
            reference_data_service,
            task_service,
            temporal_service,
            unmerge_service,
            xref_service,
            matching_policy:    live_policy,
            redis_rate_limiter: login_rate_limiter,
            task_queue:         task_queue_for_state,
            pubsub:             pubsub_client,
            field_encryption,
        }
    );

    // ── Background workers ─────────────────────────────────────────────────────
    // These run independently of the HTTP server; failures are logged but never
    // crash the process.

    // License expiry: check at startup + every 24 h; fires quota-proximity
    // notifications for tenants whose license expires within 30 days.
    tokio::spawn(workers::license_expiry::run(
        state.db.clone(),
        Arc::clone(&state.notification_service),
    ));

    // Webhook delivery: poll delivery_log every 10 s, POST with HMAC-SHA256,
    // update delivery status.
    tokio::spawn(workers::webhook_delivery::run(state.db.clone()));

    info!("Background workers started (license_expiry, webhook_delivery)");

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