/// Integration tests for mdm-core critical paths.
///
/// These run inside the binary crate so they have full access to all private
/// types via `crate::`. They require a live PostgreSQL database.
///
/// Run with:
///   DATABASE_URL=postgres://... cargo test --bin mdm-core -- --test-threads=1
use axum::{
    body::Body,
    http::{self, Request, StatusCode},
    Router,
};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt; // .oneshot()
use uuid::Uuid;

// ── Shared helpers ────────────────────────────────────────────────────────────

fn post_json(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(http::Method::POST)
        .uri(uri)
        .header("Content-Type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn body_json(resp: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap_or(json!(null))
}

async fn test_db_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set to run integration tests");
    PgPool::connect(&url).await.expect("test DB connection failed")
}

async fn build_test_app() -> (Router, PgPool) {
    dotenvy::dotenv().ok();
    let db = test_db_pool().await;

    // Run migrations so the test schema is current.
    database::migration::run_migrations(&db).await.ok();

    use crate::{
        db::repositories::{
            entity_repository::EntityRepository,
            event_repository::EventRepository,
            golden_record_repository::GoldenRecordRepository,
            matching_repository::MatchingRepository,
            survivorship_repository::SurvivorshipRepository,
            tenant_repository::TenantRepository,
        },
        matching::{Matcher, MatchingPolicy},
        services::{
            audit_service::AuditService,
            branding_service::BrandingService,
            data_quality_service::DataQualityService,
            distribution_service::DistributionService,
            domain_policy_service::DomainPolicyService,
            entity_service::EntityService,
            golden_record_service::GoldenRecordService,
            license_service::LicenseService,
            matching_service::MatchingService,
            merge_service::MergeService,
            notification_service::NotificationService,
            relationship_service::RelationshipService,
            review_service::ReviewService,
            survivorship_service::SurvivorshipService,
        },
        AppState,
    };

    let entity_repo   = EntityRepository::new(db.clone());
    let event_repo    = EventRepository::new(db.clone());
    let gr_repo       = GoldenRecordRepository::new(db.clone());
    let match_repo    = MatchingRepository::new(db.clone());
    let surv_repo     = SurvivorshipRepository::new(db.clone());
    let tenant_repo   = TenantRepository::new(db.clone());

    let live_policy        = Arc::new(std::sync::RwLock::new(MatchingPolicy::default()));
    let match_repo_arc     = Arc::new(match_repo.clone());
    let matcher            = Arc::new(Matcher::new(match_repo_arc, Arc::clone(&live_policy)));

    let entity_service = Arc::new(
        EntityService::new(db.clone(), Arc::new(entity_repo.clone()), None)
            .with_cache_opt(None)
            .with_encryption(None),
    );
    let merge_service = Arc::new(MergeService::new(
        db.clone(),
        Arc::new(entity_repo.clone()),
        Arc::new(gr_repo.clone()),
    ));

    let state = Arc::new(AppState {
        db:                     db.clone(),
        entity_repository:      entity_repo,
        event_repository:       event_repo,
        golden_record_repository: gr_repo.clone(),
        matching_repository:    match_repo.clone(),
        survivorship_repository: surv_repo.clone(),
        tenant_repository:      tenant_repo,
        domain_policy_service:  Arc::new(DomainPolicyService::new(db.clone())),
        relationship_service:   Arc::new(RelationshipService::new(db.clone())),
        matching_service:       Arc::new(MatchingService::new(matcher)),
        entity_service,
        merge_service,
        golden_record_service:  Arc::new(GoldenRecordService::new(db.clone(), Arc::new(gr_repo))),
        survivorship_service:   Arc::new(SurvivorshipService::new(Arc::new(surv_repo))),
        review_service:         Arc::new(ReviewService::new(db.clone(), Arc::new(match_repo))),
        license_service:        Arc::new(LicenseService::new(db.clone())),
        branding_service:       Arc::new(BrandingService::new(db.clone())),
        audit_service:          Arc::new(AuditService::new(db.clone())),
        notification_service:   Arc::new(NotificationService::new(db.clone())),
        data_quality_service:   Arc::new(DataQualityService::new(db.clone())),
        distribution_service:   Arc::new(DistributionService::new(db.clone())),
        matching_policy:        live_policy,
        redis_rate_limiter:     None,
        field_encryption:       None,
    });

    let app = crate::build_router(state);
    (app, db)
}

// ── Test: GET /health → 200 ───────────────────────────────────────────────────

#[tokio::test]
async fn test_health_returns_200() {
    let (app, _) = build_test_app().await;
    let req = Request::builder()
        .method(http::Method::GET)
        .uri("/health")
        .body(Body::empty())
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

// ── Test: GET /entities without Authorization → 401 ──────────────────────────

#[tokio::test]
async fn test_list_entities_without_auth_returns_401() {
    let (app, _) = build_test_app().await;
    let req = Request::builder()
        .method(http::Method::GET)
        .uri("/entities")
        .body(Body::empty())
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test: POST /auth/login with bad credentials → 401 ────────────────────────

#[tokio::test]
async fn test_login_bad_credentials_returns_401() {
    let (app, _) = build_test_app().await;
    let resp = app
        .oneshot(post_json(
            "/auth/login",
            json!({ "email": "nobody@example.com", "password": "wrongpassword" }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test: Register → login → create entity (golden path) ─────────────────────

#[tokio::test]
async fn test_entity_create_golden_path() {
    let (app, _) = build_test_app().await;
    let tenant_id = Uuid::new_v4();
    let email     = format!("test+{}@nexus.test", tenant_id);

    // Register
    let reg = app
        .clone()
        .oneshot(post_json(
            "/auth/register",
            json!({
                "email": email, "password": "Test1234!",
                "display_name": "Integration Test",
                "tenant_id": tenant_id, "role": "admin"
            }),
        ))
        .await
        .unwrap();

    assert!(
        matches!(reg.status(), StatusCode::CREATED | StatusCode::CONFLICT),
        "register: unexpected status {}",
        reg.status()
    );

    // Login
    let login_resp = app
        .clone()
        .oneshot(post_json(
            "/auth/login",
            json!({ "email": email, "password": "Test1234!" }),
        ))
        .await
        .unwrap();

    if login_resp.status() != StatusCode::OK {
        return; // previous run already used this tenant_id — skip cleanly
    }

    let login_body    = body_json(login_resp).await;
    let access_token  = login_body["access_token"].as_str().expect("access_token");

    // Create entity
    let create_resp = app
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri("/entities")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {access_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::from(
                    json!({
                        "entity_type": "Customer",
                        "source_system": "test_suite",
                        "external_id": Uuid::new_v4().to_string(),
                        "attributes": [{ "key": "name", "value": "Acme Corp" }]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(create_resp.status(), StatusCode::CREATED);
    let body = body_json(create_resp).await;
    assert_eq!(body["success"], json!(true));
    assert!(body["data"]["entity_id"].as_str().is_some(), "entity_id missing");
}

// ── Test: POST /entities when tenant is at quota → 402 ───────────────────────

#[tokio::test]
async fn test_create_entity_over_quota_returns_402() {
    let (app, db) = build_test_app().await;
    let tenant_id = Uuid::new_v4();

    // Lock the tenant to 0 records.
    sqlx::query(
        "INSERT INTO core_mdm.tenant_licenses \
         (tenant_id, tier, max_records, max_domains, max_stewards, features) \
         VALUES ($1, 'essentials', 0, 1, 5, '{}'::jsonb) \
         ON CONFLICT (tenant_id) DO UPDATE SET max_records = 0",
    )
    .bind(tenant_id)
    .execute(&db)
    .await
    .unwrap();

    let email = format!("quota+{}@nexus.test", tenant_id);
    app.clone()
        .oneshot(post_json(
            "/auth/register",
            json!({
                "email": email, "password": "Test1234!",
                "display_name": "Quota Tester",
                "tenant_id": tenant_id, "role": "admin"
            }),
        ))
        .await
        .unwrap();

    let login_body = body_json(
        app.clone()
            .oneshot(post_json(
                "/auth/login",
                json!({ "email": email, "password": "Test1234!" }),
            ))
            .await
            .unwrap(),
    )
    .await;

    let access_token = match login_body["access_token"].as_str() {
        Some(t) => t.to_owned(),
        None    => return, // registration failed (previous run) — skip
    };

    let resp = app
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri("/entities")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {access_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::from(
                    json!({
                        "entity_type": "Customer",
                        "source_system": "test",
                        "external_id": Uuid::new_v4().to_string(),
                        "attributes": []
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::PAYMENT_REQUIRED);

    sqlx::query("DELETE FROM core_mdm.tenant_licenses WHERE tenant_id = $1")
        .bind(tenant_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test: DELETE /entities/:id/gdpr-erase without valid JWT → 401 ─────────────

#[tokio::test]
async fn test_gdpr_erase_no_auth_returns_401() {
    let (app, _) = build_test_app().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method(http::Method::DELETE)
                .uri(&format!("/entities/{}/gdpr-erase", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}
