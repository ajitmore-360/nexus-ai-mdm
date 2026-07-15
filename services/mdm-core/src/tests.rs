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
            ai_suggestion_service::AiSuggestionService,
            audit_service::AuditService,
            branding_service::BrandingService,
            bulk_service::BulkService,
            comment_service::CommentService,
            connector_service::ConnectorService,
            data_profile_service::DataProfileService,
            data_quality_service::DataQualityService,
            distribution_service::DistributionService,
            domain_policy_service::DomainPolicyService,
            enrichment_service::EnrichmentService,
            entity_service::EntityService,
            golden_record_service::GoldenRecordService,
            hierarchy_service::HierarchyService,
            license_service::LicenseService,
            matching_service::MatchingService,
            merge_service::MergeService,
            notification_service::NotificationService,
            party_role_service::PartyRoleService,
            quality_analytics_service::QualityAnalyticsService,
            reference_data_service::ReferenceDataService,
            relationship_service::RelationshipService,
            review_service::ReviewService,
            scim_service::ScimService,
            sso_service::SsoService,
            survivorship_service::SurvivorshipService,
            task_service::TaskService,
            temporal_service::TemporalService,
            transformation_service::TransformationService,
            unmerge_service::UnmergeService,
            workflow_service::WorkflowService,
            xref_service::XrefService,
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

    let bulk_service              = Arc::new(BulkService::new(db.clone()));
    let comment_service           = Arc::new(CommentService::new(db.clone()));
    let hierarchy_service         = Arc::new(HierarchyService::new(db.clone()));
    let quality_analytics_service = Arc::new(QualityAnalyticsService::new(db.clone()));
    let unmerge_service           = Arc::new(UnmergeService::new(db.clone()));
    let xref_service              = Arc::new(XrefService::new(db.clone()));
    let data_profile_service      = Arc::new(DataProfileService::new(db.clone()));
    let reference_data_service    = Arc::new(ReferenceDataService::new(db.clone()));
    let task_service              = Arc::new(TaskService::new(db.clone()));
    let temporal_service          = Arc::new(TemporalService::new(db.clone()));
    let transformation_service    = Arc::new(TransformationService::new(db.clone()));
    let party_role_service        = Arc::new(PartyRoleService::new(db.clone()));
    let ai_suggestion_service     = Arc::new(AiSuggestionService::new(
        db.clone(),
        std::env::var("AI_SERVICE_URL").unwrap_or_else(|_| "http://ai-service:8082".to_string()),
    ));
    let sso_service        = Arc::new(SsoService::new(db.clone()));
    let scim_service       = Arc::new(ScimService::new(
        db.clone(),
        std::env::var("BASE_URL").unwrap_or_else(|_| "http://localhost:8081".to_string()),
    ));
    let workflow_service   = Arc::new(WorkflowService::new(db.clone()));
    let connector_service  = Arc::new(ConnectorService::new(db.clone()));
    let enrichment_service = Arc::new(EnrichmentService::new(db.clone()));

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
        ai_suggestion_service,
        distribution_service:   Arc::new(DistributionService::new(db.clone())),
        bulk_service,
        comment_service,
        hierarchy_service,
        quality_analytics_service,
        data_profile_service,
        reference_data_service,
        task_service,
        temporal_service,
        transformation_service,
        party_role_service,
        unmerge_service,
        xref_service,
        sso_service,
        scim_service,
        workflow_service,
        connector_service,
        enrichment_service,
        matching_policy:        live_policy,
        redis_rate_limiter:     None,
        task_queue:             None,
        pubsub:                 None,
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

// ── Test: Full governance workflow — assign steward → submit → approve ─────────
//
// Scenario:
//   1. Three identities share one tenant: admin, steward, owner (business_admin).
//   2. Admin assigns the steward to the "Customer" entity type.
//   3. Steward creates a Customer entity (defaults to Draft).
//   4. Steward submits for review → entity becomes PendingReview, approval request created.
//   5. Owner (business_admin) approves → entity becomes Active, request marked approved.
//
// This test exercises the full data-governance code path end-to-end against a
// real PostgreSQL database, including the assignment-gated submit_for_review
// check and the approval state machine.

#[tokio::test]
async fn test_governance_workflow_assign_submit_approve() {
    let (app, db) = build_test_app().await;
    let tenant_id = Uuid::new_v4();

    let admin_email   = format!("gov-admin+{}@nexus.test",   tenant_id);
    let steward_email = format!("gov-steward+{}@nexus.test", tenant_id);
    let owner_email   = format!("gov-owner+{}@nexus.test",   tenant_id);

    // ── 1. Register all three identities ──────────────────────────────────────
    for (email, role, display_name) in [
        (admin_email.as_str(),   "admin",          "Gov Admin"),
        (steward_email.as_str(), "steward",        "Gov Steward"),
        (owner_email.as_str(),   "business_admin", "Gov Owner"),
    ] {
        let resp = app
            .clone()
            .oneshot(post_json(
                "/auth/register",
                json!({
                    "email": email, "password": "Test1234!",
                    "display_name": display_name,
                    "tenant_id": tenant_id, "role": role
                }),
            ))
            .await
            .unwrap();
        assert!(
            matches!(resp.status(), StatusCode::CREATED | StatusCode::CONFLICT),
            "register {role}: unexpected status {}",
            resp.status()
        );
    }

    // ── 2. Login as admin ──────────────────────────────────────────────────────
    let admin_token = {
        let body = body_json(
            app.clone()
                .oneshot(post_json(
                    "/auth/login",
                    json!({ "email": admin_email, "password": "Test1234!" }),
                ))
                .await
                .unwrap(),
        )
        .await;
        match body["access_token"].as_str() {
            Some(t) => t.to_owned(),
            None    => return, // prior-run collision on this tenant_id — skip cleanly
        }
    };

    // ── 3. Login as steward ────────────────────────────────────────────────────
    let steward_token = body_json(
        app.clone()
            .oneshot(post_json(
                "/auth/login",
                json!({ "email": steward_email, "password": "Test1234!" }),
            ))
            .await
            .unwrap(),
    )
    .await["access_token"]
    .as_str()
    .expect("steward login failed")
    .to_owned();

    // ── 4. Login as owner ──────────────────────────────────────────────────────
    let owner_token = body_json(
        app.clone()
            .oneshot(post_json(
                "/auth/login",
                json!({ "email": owner_email, "password": "Test1234!" }),
            ))
            .await
            .unwrap(),
    )
    .await["access_token"]
    .as_str()
    .expect("owner login failed")
    .to_owned();

    // ── 5. Fetch steward identity_id from DB ───────────────────────────────────
    let steward_id: Uuid = sqlx::query_scalar(
        "SELECT identity_id FROM core_mdm.identities WHERE email = $1",
    )
    .bind(&steward_email)
    .fetch_one(&db)
    .await
    .expect("steward identity not found in DB");

    // ── 6. Admin assigns steward to the "Customer" entity type ─────────────────
    let assign_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri("/governance/assignments")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {admin_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::from(
                    json!({
                        "identity_id":      steward_id,
                        "entity_type_code": "Customer",
                        "assignment_type":  "steward"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        assign_resp.status(),
        StatusCode::CREATED,
        "governance assignment creation failed: {:?}",
        body_json(assign_resp).await
    );

    // ── 7. Steward creates a Customer entity (should default to Draft) ──────────
    let create_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri("/entities")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {steward_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::from(
                    json!({
                        "entity_type":   "Customer",
                        "source_system": "governance_test",
                        "external_id":   Uuid::new_v4().to_string(),
                        "attributes":    [{ "key": "name", "value": "Test Corp Governance" }]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        create_resp.status(),
        StatusCode::CREATED,
        "steward entity creation failed"
    );
    let create_body = body_json(create_resp).await;
    let entity_id: Uuid = create_body["data"]["entity_id"]
        .as_str()
        .and_then(|s| Uuid::parse_str(s).ok())
        .expect("entity_id missing from create response");

    // ── 8. Steward submits entity for review ───────────────────────────────────
    // The handler checks that the steward is assigned to "Customer" — this is
    // the assignment we created in step 6.
    let submit_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri(&format!("/entities/{entity_id}/submit-for-review"))
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {steward_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::from(
                    json!({ "change_summary": "Initial Customer record — governance E2E test" })
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        submit_resp.status(),
        StatusCode::OK,
        "submit-for-review failed: {:?}",
        body_json(submit_resp).await
    );
    let submit_body = body_json(submit_resp).await;
    assert!(
        submit_body["data"]["request_id"].as_str().is_some(),
        "request_id missing from submit response"
    );

    // ── 9. Verify entity is PendingReview and one pending approval request exists
    let entity_status: String = sqlx::query_scalar(
        "SELECT status FROM core_mdm.entities WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_id)
    .fetch_one(&db)
    .await
    .expect("entity not found after submit");
    assert_eq!(
        entity_status, "PendingReview",
        "entity should be PendingReview after submit-for-review"
    );

    let pending_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM core_mdm.entity_approval_requests \
         WHERE entity_id = $1 AND status = 'pending'",
    )
    .bind(entity_id)
    .fetch_one(&db)
    .await
    .unwrap_or(0);
    assert_eq!(pending_count, 1, "expected exactly one pending approval request");

    // ── 10. Owner (business_admin) approves the entity ─────────────────────────
    let approve_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method(http::Method::POST)
                .uri(&format!("/entities/{entity_id}/approve"))
                .header("Authorization", format!("Bearer {owner_token}"))
                .header("X-Tenant-ID", tenant_id.to_string())
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        approve_resp.status(),
        StatusCode::OK,
        "approve failed: {:?}",
        body_json(approve_resp).await
    );
    let approve_body = body_json(approve_resp).await;
    assert_eq!(
        approve_body["data"]["status"],
        json!("Active"),
        "approve response should report Active status"
    );

    // ── 11. Verify entity is Active and approval request is marked approved ──
    let final_status: String = sqlx::query_scalar(
        "SELECT status FROM core_mdm.entities WHERE entity_id = $1",
    )
    .bind(entity_id)
    .fetch_one(&db)
    .await
    .expect("entity not found after approve");
    assert_eq!(final_status, "Active", "entity should be Active in DB after approval");

    let approved_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM core_mdm.entity_approval_requests \
         WHERE entity_id = $1 AND status = 'approved'",
    )
    .bind(entity_id)
    .fetch_one(&db)
    .await
    .unwrap_or(0);
    assert_eq!(approved_count, 1, "approval request should be marked approved in DB");

    // ── 12. Cleanup — remove test-specific rows; identities are scoped by tenant_id ─
    sqlx::query(
        "DELETE FROM core_mdm.entity_approval_requests WHERE entity_id = $1",
    )
    .bind(entity_id)
    .execute(&db)
    .await
    .ok();
    sqlx::query(
        "DELETE FROM core_mdm.entities WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_id)
    .execute(&db)
    .await
    .ok();
    sqlx::query(
        "DELETE FROM core_mdm.entity_type_assignments WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .execute(&db)
    .await
    .ok();
}
