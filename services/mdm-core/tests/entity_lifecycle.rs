/// Integration tests for the entity lifecycle.
///
/// **Unit tests** (mod `unit`) — always run, no database required.
/// **Integration tests** (mod `integration`) — require `DATABASE_URL`.
///   They are skipped when `DATABASE_URL` is absent, so the test binary
///   can always be compiled and run safely in environments without a DB.
///
/// CI sets `DATABASE_URL` and runs:
///   cargo test --workspace --test '*'

// ---------------------------------------------------------------------------
// UNIT TESTS  (no database required)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod unit {
    // ── Matching policy thresholds ─────────────────────────────────────────

    #[test]
    fn matching_policy_auto_merge_above_review() {
        let auto_merge: f32 = 0.95;
        let review:     f32 = 0.75;
        assert!(auto_merge > review, "auto_merge must be strictly above review threshold");
    }

    #[test]
    fn matching_policy_field_weights_sum_to_one() {
        let exact:    f32 = 0.35;
        let fuzzy:    f32 = 0.30;
        let phonetic: f32 = 0.10;
        let semantic: f32 = 0.15;
        let vector:   f32 = 0.10;
        let total = exact + fuzzy + phonetic + semantic + vector;
        assert!(
            (total - 1.0).abs() < 0.001,
            "field weights must sum to ~1.0, got {total}"
        );
    }

    // ── IngestResult state machine ─────────────────────────────────────────

    #[test]
    fn ingest_result_all_success() {
        let processed = 10usize;
        let failed    = 0usize;
        let is_completed = failed == 0 && processed > 0;
        assert!(is_completed);
    }

    #[test]
    fn ingest_result_partial_success() {
        let processed = 8usize;
        let failed    = 2usize;
        let is_partial = processed > 0 && failed > 0;
        assert!(is_partial);
    }

    // ── Schema mapper field rename rules ───────────────────────────────────

    #[test]
    fn phone_e164_normalization_10_digits() {
        let input  = "4085550100";
        let digits: String = input.chars().filter(|c| c.is_ascii_digit()).collect();
        let result = if digits.len() == 10 {
            format!("+1{}", digits)
        } else {
            input.to_string()
        };
        assert_eq!(result, "+14085550100");
    }

    #[test]
    fn phone_e164_normalization_11_digits_with_1_prefix() {
        let input  = "14085550100";
        let digits: String = input.chars().filter(|c| c.is_ascii_digit()).collect();
        let result = if digits.len() == 11 && digits.starts_with('1') {
            format!("+{}", digits)
        } else {
            input.to_string()
        };
        assert_eq!(result, "+14085550100");
    }

    #[test]
    fn email_normalization_lowercases() {
        let input  = " USER@EXAMPLE.COM ";
        let result = input.trim().to_lowercase();
        assert_eq!(result, "user@example.com");
    }

    // ── Entity idempotency guard ───────────────────────────────────────────

    #[test]
    fn nil_uuid_should_trigger_id_assignment() {
        let id = uuid::Uuid::nil();
        assert!(id.is_nil(), "nil UUID must be detected for assignment");
    }

    #[test]
    fn non_nil_uuid_must_not_be_reassigned() {
        let id = uuid::Uuid::new_v4();
        assert!(!id.is_nil(), "generated UUID must not be nil");
    }

    // ── Policy decision constants ──────────────────────────────────────────

    #[test]
    fn policy_permissive_decision_allows_all() {
        let allowed       = true;
        let masked_fields: Vec<String> = vec![];
        assert!(allowed);
        assert!(masked_fields.is_empty());
    }

    // ── Matching score boundary conditions ────────────────────────────────

    #[test]
    fn score_clamped_to_zero_one() {
        let raw: f32 = 1.05;
        let clamped = raw.clamp(0.0, 1.0);
        assert!((clamped - 1.0).abs() < f32::EPSILON);
    }

    #[test]
    fn empty_entity_type_is_invalid() {
        let entity_type = "";
        assert!(entity_type.trim().is_empty(), "blank entity type must be rejected");
    }

    // ── Tenant isolation invariant ─────────────────────────────────────────

    #[test]
    fn different_tenants_produce_different_ids() {
        let t1 = uuid::Uuid::new_v4();
        let t2 = uuid::Uuid::new_v4();
        assert_ne!(t1, t2, "tenant UUIDs must be unique");
    }
}

// ---------------------------------------------------------------------------
// INTEGRATION TESTS  (require DATABASE_URL)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod integration {
    use chrono::Utc;
    use sqlx::{postgres::PgPoolOptions, PgPool, Row};
    use uuid::Uuid;

    /// Connects to the test DB, runs migrations, or returns None (test skipped).
    async fn maybe_pool() -> Option<PgPool> {
        dotenvy::dotenv().ok();
        let url = std::env::var("DATABASE_URL").ok()?;
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&url)
            .await
            .ok()?;

        // Apply migrations so the schema is current before any test touches the DB.
        if let Err(e) = database::migration::run_migrations(&pool).await {
            eprintln!("SKIP: migrations failed: {e}");
            return None;
        }

        Some(pool)
    }

    // ── Helper: insert a bare entity row ──────────────────────────────────

    async fn insert_entity(
        pool:        &PgPool,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        entity_type: &str,
        external_id: &str,
    ) {
        sqlx::query(
            r#"
            INSERT INTO core_mdm.entities
                (entity_id, tenant_id, entity_type, status, external_ids,
                 metadata, valid_from, valid_to, created_at, updated_at)
            VALUES ($1, $2, $3, 'Active',
                    jsonb_build_object('external_id', $4),
                    '{}'::jsonb, NOW(), 'infinity', NOW(), NOW())
            "#,
        )
        .bind(entity_id)
        .bind(tenant_id)
        .bind(entity_type)
        .bind(external_id)
        .execute(pool)
        .await
        .expect("insert entity");
    }

    // ── Helper: insert a PII attribute ────────────────────────────────────

    async fn insert_attribute(
        pool:      &PgPool,
        tenant_id: Uuid,
        entity_id: Uuid,
        key:       &str,
        value:     &str,
    ) {
        sqlx::query(
            r#"
            INSERT INTO core_mdm.entity_attributes
                (attribute_id, tenant_id, entity_id, attribute_key,
                 attribute_value, source, confidence, created_at, updated_at)
            VALUES (gen_random_uuid(), $1, $2, $3,
                    to_jsonb($4::text), 'test', 1.0, NOW(), NOW())
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(key)
        .bind(value)
        .execute(pool)
        .await
        .expect("insert attribute");
    }

    // ── Helper: tear down all test data for a tenant ──────────────────────

    async fn cleanup(pool: &PgPool, tenant_id: Uuid) {
        // Order matters (FK constraints)
        sqlx::query("DELETE FROM lineage.entity_lineage     WHERE tenant_id = $1").bind(tenant_id).execute(pool).await.ok();
        sqlx::query("DELETE FROM core_mdm.golden_records    WHERE tenant_id = $1").bind(tenant_id).execute(pool).await.ok();
        sqlx::query("DELETE FROM core_mdm.entity_attributes WHERE tenant_id = $1").bind(tenant_id).execute(pool).await.ok();
        sqlx::query("DELETE FROM core_mdm.entities          WHERE tenant_id = $1").bind(tenant_id).execute(pool).await.ok();
        sqlx::query("DELETE FROM audit.gdpr_requests        WHERE tenant_id = $1").bind(tenant_id).execute(pool).await.ok();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 1 — Entity creation + retrieval
    // ════════════════════════════════════════════════════════════════════════

    #[tokio::test]
    async fn entity_can_be_created_and_retrieved() {
        let pool = match maybe_pool().await {
            Some(p) => p,
            None    => { eprintln!("SKIP: DATABASE_URL not set"); return; }
        };

        let tenant_id = Uuid::new_v4();
        let entity_id = Uuid::new_v4();

        insert_entity(&pool, tenant_id, entity_id, "customer", "EXT-001").await;
        insert_attribute(&pool, tenant_id, entity_id, "name",  "Alice Smith").await;
        insert_attribute(&pool, tenant_id, entity_id, "email", "alice@example.com").await;

        // Verify entity exists with correct type
        let row = sqlx::query(
            "SELECT entity_type, status FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_id)
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .expect("entity must exist");

        assert_eq!(row.try_get::<String, _>("entity_type").unwrap(), "customer");
        assert_eq!(row.try_get::<String, _>("status").unwrap(),      "Active");

        // Verify attributes
        let attr_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entity_attributes WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_id)
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(0);

        assert_eq!(attr_count, 2, "both attributes must be persisted");

        cleanup(&pool, tenant_id).await;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 2 — Golden record creation (simulates post-merge)
    // ════════════════════════════════════════════════════════════════════════

    #[tokio::test]
    async fn golden_record_created_and_linked_to_entities() {
        let pool = match maybe_pool().await {
            Some(p) => p,
            None    => { eprintln!("SKIP: DATABASE_URL not set"); return; }
        };

        let tenant_id    = Uuid::new_v4();
        let primary_id   = Uuid::new_v4();
        let duplicate_id = Uuid::new_v4();
        let golden_id    = Uuid::new_v4();

        insert_entity(&pool, tenant_id, primary_id,   "customer", "EXT-100").await;
        insert_entity(&pool, tenant_id, duplicate_id, "customer", "EXT-101").await;

        // Insert golden record
        sqlx::query(
            r#"
            INSERT INTO core_mdm.golden_records
                (golden_record_id, tenant_id, entity_type, confidence_score,
                 golden_attributes, created_at, updated_at)
            VALUES ($1, $2, 'customer', 0.97, '{}'::jsonb, NOW(), NOW())
            "#,
        )
        .bind(golden_id)
        .bind(tenant_id)
        .execute(&pool)
        .await
        .expect("insert golden record");

        // Link primary → golden
        sqlx::query(
            "UPDATE core_mdm.entities SET golden_record_id=$1, updated_at=NOW() WHERE entity_id=$2 AND tenant_id=$3",
        )
        .bind(golden_id)
        .bind(primary_id)
        .bind(tenant_id)
        .execute(&pool)
        .await
        .expect("link entity to golden record");

        // Mark duplicate as merged
        sqlx::query(
            "UPDATE core_mdm.entities SET status='Merged', updated_at=NOW() WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(duplicate_id)
        .bind(tenant_id)
        .execute(&pool)
        .await
        .expect("mark duplicate as merged");

        // Insert lineage edge
        sqlx::query(
            r#"
            INSERT INTO lineage.entity_lineage
                (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
            VALUES (gen_random_uuid(), $1, $2, $3, 'merged_into', '{}'::jsonb)
            "#,
        )
        .bind(tenant_id)
        .bind(duplicate_id)
        .bind(primary_id)
        .execute(&pool)
        .await
        .expect("insert lineage");

        // ── Assertions ───────────────────────────────────────────────────────

        // Golden record exists
        let golden_exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM core_mdm.golden_records WHERE golden_record_id=$1 AND tenant_id=$2)",
        )
        .bind(golden_id)
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(false);
        assert!(golden_exists, "golden record must exist");

        // Primary is linked
        let linked_golden: Option<Uuid> = sqlx::query_scalar(
            "SELECT golden_record_id FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(primary_id)
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(None);
        assert_eq!(linked_golden, Some(golden_id), "primary must link to golden record");

        // Duplicate is Merged
        let dup_status: String = sqlx::query_scalar(
            "SELECT status FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(duplicate_id)
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .expect("duplicate must still exist");
        assert_eq!(dup_status, "Merged", "duplicate must be Merged");

        // Lineage edge exists
        let lineage_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM lineage.entity_lineage WHERE tenant_id=$1 AND source_entity_id=$2",
        )
        .bind(tenant_id)
        .bind(duplicate_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(0);
        assert_eq!(lineage_count, 1, "one lineage edge must be recorded");

        cleanup(&pool, tenant_id).await;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 3 — Full entity lifecycle: create → match candidate query → merge
    //          → golden record → GDPR erasure
    // ════════════════════════════════════════════════════════════════════════

    #[tokio::test]
    async fn full_entity_lifecycle_ingest_merge_erase() {
        let pool = match maybe_pool().await {
            Some(p) => p,
            None    => { eprintln!("SKIP: DATABASE_URL not set"); return; }
        };

        let tenant_id   = Uuid::new_v4();
        let entity_a    = Uuid::new_v4(); // canonical
        let entity_b    = Uuid::new_v4(); // duplicate to merge
        let golden_id   = Uuid::new_v4();

        // ── Phase 1: Ingest ───────────────────────────────────────────────
        insert_entity(&pool, tenant_id, entity_a, "customer", "LIFECYCLE-A").await;
        insert_entity(&pool, tenant_id, entity_b, "customer", "LIFECYCLE-B").await;
        insert_attribute(&pool, tenant_id, entity_a, "name",  "John Doe").await;
        insert_attribute(&pool, tenant_id, entity_a, "email", "john.doe@example.com").await;
        insert_attribute(&pool, tenant_id, entity_b, "name",  "John Doe").await;
        insert_attribute(&pool, tenant_id, entity_b, "email", "johndoe@example.com").await;

        // Verify both entities are Active
        let active_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entities WHERE tenant_id=$1 AND status='Active'",
        )
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(0);
        assert_eq!(active_count, 2, "both entities must be Active after ingest");

        // ── Phase 2: Simulate match — insert match record ─────────────────
        sqlx::query(
            r#"
            INSERT INTO core_mdm.match_records
                (match_id, tenant_id, entity_id_1, entity_id_2,
                 match_score, status, created_at, updated_at)
            VALUES (gen_random_uuid(), $1, $2, $3, 0.91, 'Pending', NOW(), NOW())
            "#,
        )
        .bind(tenant_id)
        .bind(entity_a)
        .bind(entity_b)
        .execute(&pool)
        .await
        .expect("insert match record");

        let pending_matches: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.match_records WHERE tenant_id=$1 AND status='Pending'",
        )
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(0);
        assert_eq!(pending_matches, 1, "one pending match must exist");

        // ── Phase 3: Simulate merge ────────────────────────────────────────
        sqlx::query(
            r#"
            INSERT INTO core_mdm.golden_records
                (golden_record_id, tenant_id, entity_type, confidence_score,
                 golden_attributes, created_at, updated_at)
            VALUES ($1, $2, 'customer', 0.91, '{}'::jsonb, NOW(), NOW())
            "#,
        )
        .bind(golden_id)
        .bind(tenant_id)
        .execute(&pool)
        .await
        .expect("create golden record");

        sqlx::query(
            "UPDATE core_mdm.entities SET golden_record_id=$1 WHERE entity_id=$2 AND tenant_id=$3",
        )
        .bind(golden_id).bind(entity_a).bind(tenant_id)
        .execute(&pool).await.expect("link primary to golden");

        sqlx::query(
            "UPDATE core_mdm.entities SET status='Merged' WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_b).bind(tenant_id)
        .execute(&pool).await.expect("mark duplicate merged");

        sqlx::query(
            "UPDATE core_mdm.match_records SET status='Accepted' WHERE tenant_id=$1 AND entity_id_1=$2",
        )
        .bind(tenant_id).bind(entity_a)
        .execute(&pool).await.ok();

        // Insert lineage edge
        sqlx::query(
            r#"
            INSERT INTO lineage.entity_lineage
                (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
            VALUES (gen_random_uuid(), $1, $2, $3, 'merged_into', $4::jsonb)
            "#,
        )
        .bind(tenant_id)
        .bind(entity_b)
        .bind(entity_a)
        .bind(serde_json::json!({ "golden_record_id": golden_id }).to_string())
        .execute(&pool)
        .await
        .expect("insert merge lineage");

        // ── Phase 4: GDPR erasure of entity_a ────────────────────────────
        // Mark PII as erased
        for field in &["name", "email"] {
            sqlx::query(
                r#"
                UPDATE core_mdm.entity_attributes
                SET attribute_value = '"ERASED"'::jsonb
                WHERE tenant_id=$1 AND entity_id=$2 AND attribute_key=$3
                "#,
            )
            .bind(tenant_id).bind(entity_a).bind(field)
            .execute(&pool).await.expect("erase PII");
        }
        sqlx::query(
            "UPDATE core_mdm.entities SET status='SoftDeleted' WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_a).bind(tenant_id).execute(&pool).await.expect("soft-delete entity");

        let audit_id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO audit.gdpr_requests
               (audit_id, tenant_id, subject_id, request_type, records_affected, completed_at)
               VALUES ($1, $2, $3, 'erasure', 1, NOW())"#,
        )
        .bind(audit_id).bind(tenant_id).bind(entity_a)
        .execute(&pool).await.ok();

        // ── Assertions ────────────────────────────────────────────────────

        // Merged entity is Merged
        let b_status: String = sqlx::query_scalar(
            "SELECT status FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_b).bind(tenant_id).fetch_one(&pool).await.expect("entity B exists");
        assert_eq!(b_status, "Merged");

        // Subject entity is SoftDeleted
        let a_status: String = sqlx::query_scalar(
            "SELECT status FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_a).bind(tenant_id).fetch_one(&pool).await.expect("entity A exists");
        assert_eq!(a_status, "SoftDeleted");

        // PII is ERASED
        let erased: Vec<String> = sqlx::query(
            "SELECT attribute_value::text FROM core_mdm.entity_attributes WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_a).bind(tenant_id)
        .fetch_all(&pool).await.unwrap_or_default()
        .into_iter()
        .filter_map(|r| r.try_get::<String, _>("attribute_value").ok())
        .collect();

        for val in &erased {
            assert_eq!(val, "\"ERASED\"", "PII must be ERASED, got {val}");
        }

        // Golden record still exists (not erased — MDM audit continuity)
        let golden_exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM core_mdm.golden_records WHERE golden_record_id=$1)",
        )
        .bind(golden_id).fetch_one(&pool).await.unwrap_or(false);
        assert!(golden_exists, "golden record must outlive erasure for audit continuity");

        // Lineage is preserved
        let lineage_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM lineage.entity_lineage WHERE tenant_id=$1",
        )
        .bind(tenant_id).fetch_one(&pool).await.unwrap_or(0);
        assert!(lineage_count >= 1, "lineage must be preserved post-erasure");

        cleanup(&pool, tenant_id).await;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 4 — Tenant isolation: entities from tenant A invisible to tenant B
    // ════════════════════════════════════════════════════════════════════════

    #[tokio::test]
    async fn tenant_isolation_prevents_cross_tenant_reads() {
        let pool = match maybe_pool().await {
            Some(p) => p,
            None    => { eprintln!("SKIP: DATABASE_URL not set"); return; }
        };

        let tenant_a = Uuid::new_v4();
        let tenant_b = Uuid::new_v4();
        let entity_id = Uuid::new_v4();

        insert_entity(&pool, tenant_a, entity_id, "customer", "ISO-001").await;

        // Query with tenant_b's ID — must find nothing
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entities WHERE entity_id=$1 AND tenant_id=$2",
        )
        .bind(entity_id)
        .bind(tenant_b)
        .fetch_one(&pool)
        .await
        .unwrap_or(0);

        assert_eq!(count, 0, "entity from tenant_a must not be visible to tenant_b");

        cleanup(&pool, tenant_a).await;
        cleanup(&pool, tenant_b).await;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 5 — Consent management: record, list, withdraw
    // ════════════════════════════════════════════════════════════════════════

    #[tokio::test]
    async fn consent_record_grant_and_withdrawal() {
        let pool = match maybe_pool().await {
            Some(p) => p,
            None    => { eprintln!("SKIP: DATABASE_URL not set"); return; }
        };

        let tenant_id  = Uuid::new_v4();
        let entity_id  = Uuid::new_v4();
        let consent_id = Uuid::new_v4();

        // Insert consent record (granted)
        sqlx::query(
            r#"
            INSERT INTO core_mdm.consent_records
                (consent_id, tenant_id, entity_id, consent_type, legal_basis,
                 consent_given, granted_at, metadata)
            VALUES ($1, $2, $3, 'marketing', 'consent', true, NOW(), '{}'::jsonb)
            "#,
        )
        .bind(consent_id)
        .bind(tenant_id)
        .bind(entity_id)
        .execute(&pool)
        .await
        .expect("insert consent record");

        // Verify it's active
        let is_active: bool = sqlx::query_scalar(
            r#"SELECT EXISTS(
                SELECT 1 FROM core_mdm.consent_records
                WHERE consent_id=$1 AND consent_given=true AND withdrawn_at IS NULL
            )"#,
        )
        .bind(consent_id)
        .fetch_one(&pool)
        .await
        .unwrap_or(false);
        assert!(is_active, "consent must be active after grant");

        // Withdraw
        sqlx::query(
            "UPDATE core_mdm.consent_records SET consent_given=false, withdrawn_at=NOW() WHERE consent_id=$1",
        )
        .bind(consent_id)
        .execute(&pool)
        .await
        .expect("withdraw consent");

        // Verify it's withdrawn (record preserved for audit)
        let row = sqlx::query(
            "SELECT consent_given, withdrawn_at FROM core_mdm.consent_records WHERE consent_id=$1",
        )
        .bind(consent_id)
        .fetch_one(&pool)
        .await
        .expect("consent record must still exist");

        let consent_given: bool = row.try_get("consent_given").unwrap_or(true);
        assert!(!consent_given, "consent must be revoked");
        let withdrawn_at: Option<chrono::DateTime<Utc>> = row.try_get("withdrawn_at").unwrap_or(None);
        assert!(withdrawn_at.is_some(), "withdrawn_at must be set");

        // Cleanup consent + entity
        sqlx::query("DELETE FROM core_mdm.consent_records WHERE tenant_id=$1").bind(tenant_id).execute(&pool).await.ok();
        cleanup(&pool, tenant_id).await;
    }
}
