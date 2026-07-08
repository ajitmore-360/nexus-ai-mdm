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
    license::license_guard,
    logging::logging_middleware,
    rate_limit::{rate_limit_middleware, operation_cost_middleware, InMemoryRateLimiter},
    rbac::{require_admin, require_approve, require_steward, require_super_admin},
    request_id::request_id_middleware,
    tenant::tenant_middleware,
    user_context::inject_user_context,
};

use nexus_redis::{create_pool as create_redis_pool, RedisConfig, RedisRateLimiter, SessionStore};

use routes::{
    ai::{copilot, copilot_stream},
    auth::{login, logout, me, refresh},
    health::{health, prometheus_metrics},
    mdm::{create_entity, execute_match},
    service_proxy::{
        // existing
        accept_invite, change_password,
        approve_match_candidate, autocomplete, create_policy_rule,
        dashboard_activity, dashboard_stats, dashboard_steward_performance,
        dashboard_quality_dimensions,
        enqueue_distribution, evaluate_policy, execute_merge, gdpr_access, gdpr_erasure,
        get_distribution_job, get_entity_by_id, get_entity_lineage,
        get_match_review_queue, get_policy_weights,
        ingest_batch, ingest_csv, ingest_entities, list_ingest_jobs, get_ingest_job,
        // golden records
        list_golden_records, get_golden_record, patch_golden_record_attributes,
        // notification webhooks
        list_webhooks, create_webhook, delete_webhook,
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
        // audit
        list_audit_events,
        // lineage
        list_lineage_events, get_lineage_stats, get_lineage_graph,
        // domain policies
        list_domain_policies, get_domain_policy, upsert_domain_policy, delete_domain_policy,
        // relationship types
        list_relationship_types, create_relationship_type, delete_relationship_type,
        // entity relationships
        list_entity_relationships, create_entity_relationship, delete_entity_relationship,
        // review queue extras
        queue_metrics, bulk_approve_matches, bulk_reject_matches, defer_match, assign_review,
        // license + branding
        get_my_license, get_tenant_branding, upsert_tenant_branding,
        // password reset
        forgot_password, reset_password,
        // invite info (public)
        invite_info,
        // SSO token exchange (public)
        sso_exchange,
        // notification inbox
        list_notifications, notifications_unread_count,
        mark_notification_read, mark_all_notifications_read,
        // submasters (reference data)
        list_submaster_types, create_submaster_type, update_submaster_type,
        list_submaster_values, create_submaster_value, update_submaster_value, delete_submaster_value,
        // data governance
        list_governance_assignments, my_governance_assigned_types,
        create_governance_assignment, delete_governance_assignment,
        list_pending_entity_approvals, submit_entity_for_review,
        approve_entity_proxy, reject_entity_proxy,
        bulk_approve_entities_proxy, bulk_reject_entities_proxy,
        // policy rules (CRUD)
        update_policy_rule, delete_policy_rule, toggle_policy_rule,
        // survivorship suggestions + GDPR request log
        policy_survivorship_suggestions, policy_gdpr_requests,
        // quality rules engine
        list_quality_rules, create_quality_rule, update_quality_rule, delete_quality_rule,
        reorder_quality_rules, run_quality_rules,
        list_quality_violations, resolve_quality_violation, bulk_resolve_violations,
        // AI suggestions (approval-gated LLM proposals)
        list_ai_suggestions, approve_ai_suggestion, reject_ai_suggestion,
        trigger_address_parse, trigger_anomaly_detection, trigger_enrichment,
        // Cross-reference / ID mapping
        proxy_list_entity_xrefs, proxy_upsert_entity_xref,
        proxy_delete_entity_xref, proxy_lookup_by_xref,
        // Entity comments
        proxy_list_entity_comments, proxy_add_entity_comment,
        proxy_edit_entity_comment, proxy_delete_entity_comment,
        // Unmerge / entity split
        proxy_unmerge_entity, proxy_get_unmerge_history,
        // Bulk operations
        proxy_bulk_update_status, proxy_bulk_export, proxy_bulk_tag,
        // Quality analytics & scorecards
        proxy_quality_trends, proxy_quality_dimensions,
        proxy_source_quality, proxy_trigger_quality_snapshot,
        // Hierarchy management
        proxy_hierarchy_roots, proxy_entity_children, proxy_entity_ancestors,
        proxy_entity_subtree, proxy_set_entity_parent,
        // Temporal / bitemporal records
        proxy_entity_history, proxy_entity_as_of, proxy_entity_bitemporal,
        // Data profiling
        proxy_get_profile, proxy_run_profile,
        // Task assignment & SLA
        proxy_list_tasks, proxy_create_task, proxy_update_task, proxy_check_sla,
        // Reference data management
        proxy_list_reference_lists, proxy_create_reference_list,
        proxy_get_reference_values, proxy_upsert_reference_value,
        proxy_bulk_import_ref_values, proxy_delete_reference_value,
        // Transformation rules DSL
        proxy_list_transformation_rules, proxy_create_transformation_rule,
        proxy_preview_transformation, proxy_toggle_transformation_rule,
        proxy_delete_transformation_rule,
        // Party role management
        proxy_list_party_roles, proxy_upsert_party_role,
        proxy_delete_party_role, proxy_entities_by_role,
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

    // Guard: reject known dev default JWT secret in non-dev environments.
    const KNOWN_DEV_JWT_SECRET: &str = "nexus-local-dev-jwt-secret-min-32-chars!!";
    let jwt_secret = std::env::var("JWT_SECRET").unwrap_or_default();
    if jwt_secret.is_empty()
        && !auth_disabled
        && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage")
    {
        panic!(
            "SECURITY: JWT_SECRET is not set in APP_ENV={}. \
             All JWT validation will fail. \
             Generate a secret: openssl rand -hex 32",
            app_env
        );
    }
    if jwt_secret == KNOWN_DEV_JWT_SECRET
        && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage")
    {
        panic!(
            "SECURITY: JWT_SECRET is the well-known dev default. \
             Rotate it before deploying to APP_ENV={}. \
             Generate a new secret: openssl rand -hex 32",
            app_env
        );
    }

    // Guard: API_BEARER_TOKEN must be set and must not be the known dev default in
    // non-development environments. mdm_service_auth() sends this as the
    // service-to-service Authorization header on every proxied write to mdm-core.
    const KNOWN_DEV_API_TOKEN: &str = "nexus-local-dev-token";
    let api_bearer_token = std::env::var("API_BEARER_TOKEN").unwrap_or_default();
    if api_bearer_token == KNOWN_DEV_API_TOKEN
        && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage")
    {
        panic!(
            "SECURITY: API_BEARER_TOKEN is the well-known dev default in APP_ENV={}. \
             Rotate it before deploying.",
            app_env
        );
    }
    if api_bearer_token.is_empty()
        && matches!(app_env.as_str(), "production" | "staging" | "prod" | "stage")
    {
        panic!(
            "SECURITY: API_BEARER_TOKEN is not set in APP_ENV={}. \
             Service-to-service calls to mdm-core will be unauthenticated.",
            app_env
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
    let (redis_rate_limiter, session_store, token_blocklist) =
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
                    pool.clone(),
                    redis_cfg.key_prefix.clone(),
                ));
                let blocklist = Arc::new(nexus_redis::TokenBlocklist::new(
                    pool,
                    redis_cfg.key_prefix.clone(),
                ));
                (Some(limiter), Some(sessions), Some(blocklist))
            }
            Err(e) => {
                tracing::warn!(error=%e, "Redis unavailable; using in-memory fallbacks");
                (None, None, None)
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
        license_cache:      Arc::new(dashmap::DashMap::new()),
        http_client:        Arc::new(
            reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(5))
                .build()
                .expect("http client"),
        ),
        ws_manager:         ws::manager::WsManager::new(),
        // Trip after 5 consecutive failures; recover after 30 s.
        cb_mdm:             Arc::new(crate::proxy::circuit_breaker::CircuitBreaker::new(5, 30)),
        cb_ai:              Arc::new(crate::proxy::circuit_breaker::CircuitBreaker::new(5, 30)),
        token_blocklist,
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
    //   request_id → logging → rate_limit → auth → tenant → rbac → handler
    //
    // Routes are split into three groups with different RBAC rules:
    //
    //  1. platform_admin_routes  — SuperAdmin ONLY (Product Admin / IT team)
    //     Tenant management, platform users.  Data operators are blocked.
    //
    //  2. tenant_data_routes     — Any tenant role EXCEPT SuperAdmin
    //     Entities, match, merge, ingest.  IT admin is blocked.
    //
    //  3. shared_routes          — Any authenticated role
    //     Dashboard, search, entity-type config, source systems, AI copilot.
    //     These are accessible to both IT admin and tenant users.

    let common_layers = |router: Router<AppState>| {
        router
            // Layer application order: last .layer() = outermost = executes first on the request.
            // Desired execution order:
            //   request_id → logging → rate_limit → auth → tenant → license_guard → rbac → handler
            //
            // license_guard is added first (innermost of the middleware stack) so it executes
            // after both auth and tenant_middleware have already run and populated extensions.
            .layer(axum_middleware::from_fn_with_state(state.clone(), license_guard))
            .layer(axum_middleware::from_fn(inject_user_context))
            .layer(axum_middleware::from_fn_with_state(state.clone(), auth_middleware))
            .layer(axum_middleware::from_fn_with_state(state.clone(), tenant_middleware))
            .layer(axum_middleware::from_fn_with_state(state.clone(), rate_limit_middleware))
            .layer(axum_middleware::from_fn(logging_middleware))
            .layer(axum_middleware::from_fn(request_id_middleware))
    };

    // Platform-level routes skip tenant_middleware — SuperAdmins are not scoped to a tenant.
    // license_guard passes through safely when TenantContext is absent.
    let platform_layers = |router: Router<AppState>| {
        router
            .layer(axum_middleware::from_fn_with_state(state.clone(), license_guard))
            .layer(axum_middleware::from_fn_with_state(state.clone(), auth_middleware))
            .layer(axum_middleware::from_fn_with_state(state.clone(), rate_limit_middleware))
            .layer(axum_middleware::from_fn(logging_middleware))
            .layer(axum_middleware::from_fn(request_id_middleware))
    };

    // ── 1. Platform admin routes — SuperAdmin only ────────────────────────────
    let platform_admin_routes = platform_layers(
        Router::new()
            .route("/admin/tenants",                get(admin_list_tenants).post(admin_create_tenant))
            .route("/admin/tenants/:id/admin-user", post(admin_create_admin_user))
            .layer(axum_middleware::from_fn(require_super_admin))
    );

    // ── 1b. Tenant admin routes — Admin role (tenant admins managing their own tenant) ──
    let tenant_admin_routes = common_layers(
        Router::new()
            .route("/admin/users",         get(admin_list_users))
            .route("/admin/users/invite",  post(admin_invite_user))
            .route("/admin/users/:id/role", patch(admin_update_user_role))
            .layer(axum_middleware::from_fn(require_admin))
    );

    // ── 2a. Steward-only routes — require Steward role ─────────────────────────
    // Merge and defer permanently alter or postpone master-data decisions.
    // BusinessAdmin, Viewers, and Analysts cannot perform these operations.
    // SuperAdmin (IT Admin) has full access — they can perform any data operation
    // within the tenant they are logged into.
    let steward_routes = common_layers(
        Router::new()
            .route("/merge",                                             post(execute_merge))
            .route("/match/:request_id/candidates/:candidate_id/defer", post(defer_match))
            .layer(axum_middleware::from_fn_with_state(state.clone(), operation_cost_middleware))
            .layer(axum_middleware::from_fn(require_steward))
    );

    // ── 2b. Approve/reject routes — Steward or BusinessAdmin ──────────────────
    let approve_routes = common_layers(
        Router::new()
            .route("/match/:rid/candidates/:cid/approve", post(approve_match_candidate))
            .route("/match/:rid/candidates/:cid/reject",  post(reject_match_candidate))
            .route("/match/bulk-approve",                 post(bulk_approve_matches))
            .route("/match/bulk-reject",                  post(bulk_reject_matches))
            .layer(axum_middleware::from_fn(require_approve))
    );

    // ── 2c. Governance assignment config — BusinessAdmin/Admin only ───────────
    let governance_admin_routes = common_layers(
        Router::new()
            .route("/governance/assignments",
                get(list_governance_assignments).post(create_governance_assignment))
            .route("/governance/assignments/:id",
                delete(delete_governance_assignment))
            .layer(axum_middleware::from_fn(require_admin))
    );

    // ── 2d. Governance workflow — Steward+ submit, Approve-role for approve/reject
    let governance_workflow_routes = common_layers(
        Router::new()
            // Any authenticated tenant user can see their own assigned types
            .route("/governance/assignments/my-types",
                get(my_governance_assigned_types))
            // Pending approvals list — Approve role (Steward owner, BusinessAdmin, Admin)
            .route("/entities/pending-approvals",
                get(list_pending_entity_approvals))
            // Bulk approve/reject — same access level as single approve/reject
            .route("/entities/bulk-approve", post(bulk_approve_entities_proxy))
            .route("/entities/bulk-reject",  post(bulk_reject_entities_proxy))
            // Approve/reject — Data Owner or Admin
            .route("/entities/:id/approve",
                post(approve_entity_proxy))
            .route("/entities/:id/reject",
                post(reject_entity_proxy))
            .layer(axum_middleware::from_fn(require_approve))
    );

    // Steward-accessible: submit entity for Data Owner review
    let governance_steward_routes = common_layers(
        Router::new()
            .route("/entities/:id/submit-for-review",
                post(submit_entity_for_review))
            .layer(axum_middleware::from_fn(require_steward))
    );

    // ── 2e. Steward data mutations — create/edit/delete entities, ingest ───────
    // Viewer, Analyst, and BusinessAdmin cannot write entity records.
    let steward_data_routes = common_layers(
        Router::new()
            .route("/entities",                          post(create_entity))
            .route("/entities/:id",                      patch(patch_entity))
            .route("/entities/:id/relationships",        post(create_entity_relationship))
            .route("/relationships/:id",                 delete(delete_entity_relationship))
            .route("/ingest/batch",                      post(ingest_batch))
            .route("/ingest/entities",                   post(ingest_entities))
            .route("/ingest/csv",                        post(ingest_csv))
            .route("/golden-records/:id/attributes",     patch(patch_golden_record_attributes))
            .route("/policy/consent",                    post(record_consent))
            .route("/policy/consent/:id/withdraw",       post(withdraw_consent))
            // AI suggestion triggers + approve/reject (steward minimum)
            .route("/entities/:id/ai-suggestions/address-parse", post(trigger_address_parse))
            .route("/entities/:id/ai-suggestions/anomaly",       post(trigger_anomaly_detection))
            .route("/entities/:id/ai-suggestions/enrichment",    post(trigger_enrichment))
            .route("/ai-suggestions/:id/approve",                patch(approve_ai_suggestion))
            .route("/ai-suggestions/:id/reject",                 patch(reject_ai_suggestion))
            // Cross-reference writes
            .route("/entities/:id/xrefs",                        post(proxy_upsert_entity_xref))
            .route("/entities/:entity_id/xrefs/:xref_id",        delete(proxy_delete_entity_xref))
            // Entity comment writes
            .route("/entities/:id/comments",                     post(proxy_add_entity_comment))
            .route("/entities/:entity_id/comments/:comment_id",  patch(proxy_edit_entity_comment).delete(proxy_delete_entity_comment))
            // Unmerge (write — steward minimum)
            .route("/entities/:id/unmerge",                      post(proxy_unmerge_entity))
            // Bulk operations (steward minimum)
            .route("/entities/bulk/status",                      post(proxy_bulk_update_status))
            .route("/entities/bulk/export",                      post(proxy_bulk_export))
            .route("/entities/bulk/tag",                         post(proxy_bulk_tag))
            // Hierarchy parent assignment (write)
            .route("/entities/:id/parent",                       patch(proxy_set_entity_parent))
            // Task management (steward minimum — create + update own tasks)
            .route("/tasks",                                     post(proxy_create_task))
            .route("/tasks/:id",                                 patch(proxy_update_task))
            // Reference data writes (steward can add values; list creation is admin)
            .route("/reference-data/:list_id/values",            post(proxy_upsert_reference_value))
            .route("/reference-data/:list_id/values/bulk",       post(proxy_bulk_import_ref_values))
            .route("/reference-data/:list_id/values/:value_id",  delete(proxy_delete_reference_value))
            // Transformation rules preview (dry-run — steward minimum)
            .route("/transformation-rules/preview",              post(proxy_preview_transformation))
            // Party role writes (steward minimum)
            .route("/entities/:id/roles",                        post(proxy_upsert_party_role))
            .route("/entities/:id/roles/:role_code",             delete(proxy_delete_party_role))
            .layer(axum_middleware::from_fn(require_steward))
    );

    // ── 2f. Admin config mutations — schema, policies, source systems ─────────
    // Only BusinessAdmin and above may modify tenant configuration.
    let admin_config_routes = common_layers(
        Router::new()
            // Policy rule CRUD
            .route("/policy/rules",              post(create_policy_rule))
            .route("/policy/rules/:id",          put(update_policy_rule).delete(delete_policy_rule))
            .route("/policy/rules/:id/toggle",   patch(toggle_policy_rule))
            // Policy weights update
            .route("/policy/weights",            patch(update_policy_weights))
            // GDPR operations (admin-only — data erasure and access log)
            .route("/policy/gdpr/erasure",       post(gdpr_erasure))
            .route("/policy/gdpr/access",        post(gdpr_access))
            // Distribution (admin-only — controls downstream data distribution)
            .route("/distribution/jobs",         post(enqueue_distribution))
            // Entity type schema management
            .route("/entity-types",              post(create_entity_type))
            .route("/entity-types/:id",          patch(update_entity_type).delete(delete_entity_type))
            .route("/entity-types/:code/attributes",       post(create_attribute))
            .route("/entity-types/:code/attributes/order", put(reorder_attributes))
            .route("/entity-types/:code/attributes/:id",   delete(delete_attribute))
            // /admin/entity-types aliases (Flutter UI uses this prefix)
            .route("/admin/entity-types",              post(create_entity_type))
            .route("/admin/entity-types/:id",          patch(update_entity_type).delete(delete_entity_type))
            .route("/admin/entity-types/:code/attributes",       post(create_attribute))
            .route("/admin/entity-types/:code/attributes/order", put(reorder_attributes))
            .route("/admin/entity-types/:code/attributes/:id",   delete(delete_attribute))
            // Source system management
            .route("/admin/source-systems",            post(create_source_system))
            .route("/admin/source-systems/:id",        put(update_source_system).delete(delete_source_system))
            // Webhook management
            .route("/webhooks",                        post(create_webhook))
            .route("/webhooks/:id",                    delete(delete_webhook))
            // Domain policies (write)
            .route("/domain-policies/:entity_type_code", put(upsert_domain_policy).delete(delete_domain_policy))
            // Relationship types (write)
            .route("/relationship-types",              post(create_relationship_type))
            .route("/relationship-types/:type_id",     delete(delete_relationship_type))
            // Tenant branding (write)
            .route("/tenant/branding",                 put(upsert_tenant_branding))
            // Submasters / reference data (writes)
            .route("/admin/submasters",                post(create_submaster_type))
            .route("/admin/submasters/:code",          patch(update_submaster_type))
            .route("/admin/submasters/:code/values",   post(create_submaster_value))
            .route("/admin/submasters/:code/values/:value_id",
                patch(update_submaster_value).delete(delete_submaster_value))
            // Quality rules engine (writes)
            .route("/admin/quality-rules",                             post(create_quality_rule))
            .route("/admin/quality-rules/reorder",                     post(reorder_quality_rules))
            .route("/admin/quality-rules/run",                         post(run_quality_rules))
            .route("/admin/quality-rules/:id",                         patch(update_quality_rule).delete(delete_quality_rule))
            .route("/admin/quality-violations/:id/resolve",            patch(resolve_quality_violation))
            .route("/admin/quality-violations/bulk-resolve",           post(bulk_resolve_violations))
            // Quality analytics: manual snapshot trigger (admin only)
            .route("/analytics/quality-snapshot",                      post(proxy_trigger_quality_snapshot))
            // Data profiling: run profiling job (admin/steward-lead)
            .route("/data-profiling/:entity_type/run",                 post(proxy_run_profile))
            // Task SLA breach check (admin/scheduled job)
            .route("/tasks/check-sla",                                 post(proxy_check_sla))
            // Reference data list management (admin creates/manages code lists)
            .route("/reference-data",                                  post(proxy_create_reference_list))
            // Transformation rules CRUD (admin manages the DSL rules)
            .route("/transformation-rules",                            post(proxy_create_transformation_rule))
            .route("/transformation-rules/:id/toggle",                 put(proxy_toggle_transformation_rule))
            .route("/transformation-rules/:id",                        delete(proxy_delete_transformation_rule))
            .layer(axum_middleware::from_fn(require_admin))
    );

    // ── 2g. Tenant data routes — read-only, any authenticated tenant role ─────
    let tenant_data_routes = common_layers(
        Router::new()
            // Hierarchy reads — must come BEFORE /:id routes
            .route("/entities/hierarchy/roots",          get(proxy_hierarchy_roots))
            // XRef lookup — must come before /:id
            .route("/xrefs/lookup",                      get(proxy_lookup_by_xref))
            // Entity reads
            .route("/entities",                          get(list_entities))
            .route("/entities/:id",                      get(get_entity_by_id))
            .route("/entities/:id/lineage",              get(get_entity_lineage))
            .route("/lineage",                           get(list_lineage_events))
            .route("/lineage/graph",                     get(get_lineage_graph))
            .route("/lineage/stats",                     get(get_lineage_stats))
            .route("/entities/:id/relationships",        get(list_entity_relationships))
            // Match — execute is read-based (scoring only, no persistence)
            .route("/match",
                post(execute_match)
                    .layer(axum_middleware::from_fn_with_state(state.clone(), operation_cost_middleware))
            )
            .route("/match/review-queue",                get(get_match_review_queue))
            .route("/match/queue-metrics",               get(queue_metrics))
            .route("/match/review-queue/:review_id/assign", patch(assign_review))
            // Ingest reads
            .route("/ingest/jobs",                       get(list_ingest_jobs))
            .route("/ingest/jobs/:id",                   get(get_ingest_job))
            // Golden record reads
            .route("/golden-records",                    get(list_golden_records))
            .route("/golden-records/:id",                get(get_golden_record))
            // Policy reads
            .route("/policy/evaluate",                   post(evaluate_policy))
            .route("/policy/rules",                      get(list_policy_rules))
            .route("/policy/survivorship-suggestions",   get(policy_survivorship_suggestions))
            .route("/policy/gdpr/requests",              get(policy_gdpr_requests))
            .route("/policy/consent",                    get(list_consent))
            // Distribution reads
            .route("/distribution/jobs",                 get(list_distribution_jobs))
            .route("/distribution/jobs/:id",             get(get_distribution_job))
            // Cross-reference reads
            .route("/entities/:id/xrefs",                get(proxy_list_entity_xrefs))
            // Entity comments reads
            .route("/entities/:id/comments",             get(proxy_list_entity_comments))
            // Unmerge history (read)
            .route("/entities/:id/unmerge-history",      get(proxy_get_unmerge_history))
            // Hierarchy reads
            .route("/entities/:id/children",             get(proxy_entity_children))
            .route("/entities/:id/ancestors",            get(proxy_entity_ancestors))
            .route("/entities/:id/subtree",              get(proxy_entity_subtree))
            // Quality analytics reads
            .route("/analytics/quality-trends",          get(proxy_quality_trends))
            .route("/analytics/quality-dimensions",      get(proxy_quality_dimensions))
            .route("/analytics/source-quality",          get(proxy_source_quality))
            // Temporal / bitemporal records (reads — any authenticated user)
            .route("/entities/:id/history",              get(proxy_entity_history))
            .route("/entities/:id/as-of",                get(proxy_entity_as_of))
            .route("/entities/:id/bitemporal",           get(proxy_entity_bitemporal))
            // Data profiling (reads)
            .route("/data-profiling/:entity_type",       get(proxy_get_profile))
            // Tasks (reads — user sees own tasks; admin sees all via query param)
            .route("/tasks",                             get(proxy_list_tasks))
            // Reference data (reads — all authenticated users need for dropdowns)
            .route("/reference-data",                    get(proxy_list_reference_lists))
            .route("/reference-data/:list_id/values",   get(proxy_get_reference_values))
            // Transformation rules (reads)
            .route("/transformation-rules",              get(proxy_list_transformation_rules))
            // Party roles (reads)
            .route("/entities/:id/roles",                get(proxy_list_party_roles))
            .route("/party-roles/by-role",               get(proxy_entities_by_role))
    );

    // ── 3. Shared routes — any authenticated user ─────────────────────────────
    let shared_routes = common_layers(
        Router::new()
            // Dashboard (both IT admin overview and tenant user metrics)
            .route("/dashboard/stats",               get(dashboard_stats))
            .route("/dashboard/activity",            get(dashboard_activity))
            .route("/dashboard/steward-performance",  get(dashboard_steward_performance))
            .route("/dashboard/quality-dimensions",   get(dashboard_quality_dimensions))
            // Search
            .route("/search",             get(search))
            .route("/search/autocomplete", get(autocomplete))
            // AI Copilot
            .route("/copilot",            post(copilot))
            .route("/copilot/stream",     post(copilot_stream))
            .route("/weights/recommend",  get(recommend_weights))
            .route("/anomalies",
                get(scan_anomalies)
                    .layer(axum_middleware::from_fn_with_state(state.clone(), operation_cost_middleware))
            )
            // Policy weights (read; patch is in admin_config_routes)
            .route("/policy/weights",     get(get_policy_weights))
            // Entity type / attribute config reads
            // Both /entity-types and /admin/entity-types are supported (Flutter uses /admin/ prefix)
            // Writes (POST/PATCH/DELETE/PUT) are in admin_config_routes
            .route("/entity-types",                              get(list_entity_types))
            .route("/entity-types/:code/attributes",             get(list_attributes))
            .route("/entity-types/:code/next-sequence",          get(next_sequence))
            // /admin/entity-types aliases (reads)
            .route("/admin/entity-types",                        get(list_entity_types))
            .route("/admin/entity-types/:code/attributes",       get(list_attributes))
            .route("/admin/entity-types/:code/next-sequence",    get(next_sequence))
            // Source systems (reads; writes in admin_config_routes)
            .route("/admin/source-systems",          get(list_source_systems))
            .route("/admin/source-systems/:id/test", post(test_source_system))
            // Audit log
            .route("/audit/events",                  get(list_audit_events))
            // Notification webhook subscriptions (read; writes in admin_config_routes)
            .route("/webhooks",                      get(list_webhooks))
            // Domain policies (reads; writes in admin_config_routes)
            .route("/domain-policies",               get(list_domain_policies))
            .route("/domain-policies/:entity_type_code", get(get_domain_policy))
            // Relationship types (read; writes in admin_config_routes)
            .route("/relationship-types",            get(list_relationship_types))
            // Auth — protected endpoints that require a valid session
            .route("/auth/logout",                   axum::routing::post(logout))
            .route("/auth/change-password",          axum::routing::post(change_password))
            // License — tenant's own license info
            .route("/license",                       get(get_my_license))
            // Tenant branding (read; put in admin_config_routes)
            .route("/tenant/branding",               get(get_tenant_branding))
            // Submasters / reference data (reads — all authenticated users need this for dropdowns)
            .route("/admin/submasters",                        get(list_submaster_types))
            .route("/admin/submasters/:code/values",           get(list_submaster_values))
            // Quality rules engine (reads — available to all authenticated users)
            .route("/admin/quality-rules",                     get(list_quality_rules))
            .route("/admin/quality-violations",                get(list_quality_violations))
            // AI suggestions (read — any authenticated user can view suggestions for their entities)
            .route("/ai-suggestions",                          get(list_ai_suggestions))
            // User notification inbox
            .route("/notifications",                 get(list_notifications))
            .route("/notifications/unread-count",    get(notifications_unread_count))
            .route("/notifications/:id/read",        patch(mark_notification_read))
            .route("/notifications/read-all",        post(mark_all_notifications_read))
    );

    let protected_routes = Router::new()
        .merge(platform_admin_routes)
        .merge(tenant_admin_routes)
        .merge(steward_routes)
        .merge(steward_data_routes)
        .merge(approve_routes)
        .merge(governance_admin_routes)
        .merge(governance_workflow_routes)
        .merge(governance_steward_routes)
        .merge(admin_config_routes)
        .merge(tenant_data_routes)
        .merge(shared_routes);

    // Initialise metrics for Prometheus scraping
    nexus_telemetry::metrics::init_metrics("api-gateway");

    // Public routes — no auth required
    let public_routes = Router::new()
        .route("/health",              get(health))
        .route("/metrics",             get(prometheus_metrics))
        .route("/auth/login",            axum::routing::post(login))
        .route("/auth/refresh",          axum::routing::post(refresh))
        .route("/auth/accept-invite",    axum::routing::post(accept_invite))
        .route("/auth/invite-info",      axum::routing::get(invite_info))
        .route("/auth/forgot-password",  axum::routing::post(forgot_password))
        .route("/auth/reset-password",   axum::routing::post(reset_password))
        .route("/auth/sso-exchange",     axum::routing::post(sso_exchange))
        // Real-time WebSocket — handler validates JWT from ?token= query param
        // (browsers cannot set Authorization header on WebSocket connections)
        .route("/ws/notifications",      get(ws::handler::websocket_handler));

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
            .route("/auth/me",             get(me))
            .route("/auth/login",            axum::routing::post(login))
            .route("/auth/refresh",          axum::routing::post(refresh))
            .route("/auth/accept-invite",    axum::routing::post(accept_invite))
            .route("/auth/invite-info",      axum::routing::get(invite_info))
            .route("/auth/forgot-password",  axum::routing::post(forgot_password))
            .route("/auth/reset-password",   axum::routing::post(reset_password))
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

    // ---- Redis pub/sub → WebSocket broadcast --------------------------------
    // Subscribe to tenant-scoped Redis channels and fan notifications to active
    // WS sessions. The subscriber loop restarts automatically on disconnect.
    {
        let redis_url = std::env::var("REDIS_URL")
            .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
        let ws_mgr = state.ws_manager.clone();
        tokio::spawn(async move {
            ws::subscriber::run(redis_url, ws_mgr).await;
        });
    }

    // ---- WebSocket (legacy TCP) --------------------------------------------
    // Build JwtConfig for first-message auth on the port-4000 TCP WS server.
    // If JWT_SECRET is absent we skip the TCP server (it can't validate tokens).
    if let Ok(jwt_cfg) = nexus_auth::JwtConfig::from_env() {
        let jwt_cfg = Arc::new(jwt_cfg);
        tokio::spawn(async move {
            if let Err(err) = ws::start_ws_server(jwt_cfg).await {
                tracing::error!("TCP WS server failed: {:?}", err);
            }
        });
    } else {
        tracing::warn!(
            "JWT_SECRET not configured — legacy TCP WS server on port 4000 not started"
        );
    }

    // ---- Bind --------------------------------------------------------------
    let addr = SocketAddr::from(([0, 0, 0, 0], settings.gateway_port));
    tracing::info!("API Gateway listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind API Gateway");

    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
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
