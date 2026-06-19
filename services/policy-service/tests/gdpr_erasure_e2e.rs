/// GDPR Erasure E2E test.
///
/// Requires a live PostgreSQL database with all Nexus MDM migrations applied.
/// Set `TEST_DATABASE_URL` to run; the test is skipped when the var is absent.
///
/// The test spins up a GdprEngine against the test DB, inserts a scratch entity
/// with PII attributes under an isolated tenant UUID, runs process_erasure, then
/// asserts every PII field is `"ERASED"`, the entity is `SoftDeleted`, and an
/// audit record exists.

use chrono::Utc;
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

use policy_service::{
    engine::GdprEngine,
    models::{GdprRequest, GdprRequestType},
};

/// Connect to the test database, or return None to skip the test.
/// Prefers TEST_DATABASE_URL, falls back to DATABASE_URL (CI sets the latter).
async fn maybe_pool() -> Option<sqlx::PgPool> {
    dotenvy::dotenv().ok();
    let url = std::env::var("TEST_DATABASE_URL")
        .or_else(|_| std::env::var("DATABASE_URL"))
        .ok()?;
    PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .ok()
}

#[tokio::test]
async fn gdpr_erasure_erases_pii_and_soft_deletes_entity() {
    let pool = match maybe_pool().await {
        Some(p) => p,
        None    => {
            eprintln!("SKIP: TEST_DATABASE_URL not set");
            return;
        }
    };

    // ── Isolation: use a fresh tenant + entity UUID per test run ─────────────
    let tenant_id   = Uuid::new_v4();
    let entity_id   = Uuid::new_v4();
    let entity_type = "customer";

    // ── Insert test entity ────────────────────────────────────────────────────
    sqlx::query(
        r#"
        INSERT INTO core_mdm.entities
            (entity_id, tenant_id, entity_type, status, external_ids,
             metadata, valid_from, valid_to, created_at, updated_at)
        VALUES ($1, $2, $3, 'Active', '{}'::jsonb, '{}'::jsonb,
                NOW(), 'infinity', NOW(), NOW())
        "#,
    )
    .bind(entity_id)
    .bind(tenant_id)
    .bind(entity_type)
    .execute(&pool)
    .await
    .expect("insert test entity");

    // ── Insert PII attribute values ───────────────────────────────────────────
    let pii_fields = [
        ("name",  r#""Alice Test""#),
        ("email", r#""alice@example.com""#),
        ("phone", r#""+1-555-0100""#),
    ];

    for (key, val) in &pii_fields {
        sqlx::query(
            r#"
            INSERT INTO core_mdm.entity_attributes
                (attribute_id, tenant_id, entity_id, attribute_key, attribute_value,
                 source, confidence, created_at, updated_at)
            VALUES (gen_random_uuid(), $1, $2, $3, $4::jsonb, 'test', 1.0, NOW(), NOW())
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(key)
        .bind(val)
        .execute(&pool)
        .await
        .unwrap_or_else(|e| panic!("insert attribute {}: {}", key, e));
    }

    // ── Run GDPR erasure ──────────────────────────────────────────────────────
    let engine = GdprEngine::new(pool.clone());
    let req = GdprRequest {
        tenant_id,
        subject_id:   entity_id,
        request_type: GdprRequestType::Erasure,
        requested_at: Utc::now(),
        reason:       Some("e2e test run".to_string()),
        requested_by: Some("test-harness".to_string()),
    };

    let result = engine.process_erasure(&req).await
        .expect("process_erasure must succeed");

    assert_eq!(result.records_affected, 1, "exactly one entity should be affected");
    assert!(!result.audit_id.is_nil(), "audit_id must be populated");

    // ── Verify PII is erased ──────────────────────────────────────────────────
    for (key, _) in &pii_fields {
        let row: Option<serde_json::Value> = sqlx::query_scalar(
            r#"
            SELECT attribute_value
            FROM core_mdm.entity_attributes
            WHERE tenant_id     = $1
              AND entity_id     = $2
              AND attribute_key = $3
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(key)
        .fetch_optional(&pool)
        .await
        .unwrap_or_else(|e| panic!("query attribute {}: {}", key, e));

        let val = row.unwrap_or(serde_json::Value::Null);
        assert_eq!(
            val,
            serde_json::Value::String("ERASED".to_string()),
            "attribute '{}' should be ERASED, got {:?}",
            key,
            val
        );
    }

    // ── Verify entity is soft-deleted ─────────────────────────────────────────
    let status: String = sqlx::query_scalar(
        "SELECT status FROM core_mdm.entities WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_id)
    .fetch_one(&pool)
    .await
    .expect("entity must still exist after erasure");

    assert_eq!(status, "SoftDeleted", "entity status must be SoftDeleted");

    // ── Verify audit record exists ────────────────────────────────────────────
    let audit_exists: bool = sqlx::query_scalar(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM audit.gdpr_requests
            WHERE audit_id  = $1
              AND tenant_id = $2
              AND subject_id = $3
        )
        "#,
    )
    .bind(result.audit_id)
    .bind(tenant_id)
    .bind(entity_id)
    .fetch_one(&pool)
    .await
    .unwrap_or(false);

    assert!(audit_exists, "audit record must exist in audit.gdpr_requests");

    // ── Cleanup: remove test data so re-runs are clean ────────────────────────
    sqlx::query("DELETE FROM audit.gdpr_requests WHERE tenant_id = $1")
        .bind(tenant_id)
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM core_mdm.entity_attributes WHERE tenant_id = $1")
        .bind(tenant_id)
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM core_mdm.entities WHERE tenant_id = $1")
        .bind(tenant_id)
        .execute(&pool)
        .await
        .ok();
}
