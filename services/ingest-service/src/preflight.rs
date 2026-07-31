use sqlx::PgPool;
use uuid::Uuid;

pub struct ConfigurationIssue {
    pub message: String,
}

/// Verify that the entity type, attribute schemas, and reference-data (submaster)
/// values are fully configured for the given tenant before allowing ingest to proceed.
///
/// Returns a list of human-readable issues.  An empty list means the system is
/// ready; a non-empty list means the caller should reject the request and direct
/// the operator to configure the MDM system first.
///
/// A database error is treated as "pass-through" (issues = empty) so a transient
/// DB hiccup never permanently blocks ingest — the error is only logged.
pub async fn check_ingest_readiness(
    pool:        &PgPool,
    tenant_id:   Uuid,
    entity_type: &str,
) -> Result<Vec<ConfigurationIssue>, sqlx::Error> {
    let mut issues = Vec::new();

    // Use a short-lived read-only transaction to scope the RLS tenant setting.
    // entity_type_configs and attribute_schemas have RLS policies that gate on
    // app.current_tenant; without setting it the queries return zero rows even
    // when records exist.
    let mut txn = pool.begin().await?;

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *txn)
        .await?;

    // ── 1. Entity type must be configured and active for this tenant ──────
    let et_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) \
         FROM core_mdm.entity_type_configs \
         WHERE tenant_id = $1 \
           AND LOWER(code) = LOWER($2) \
           AND is_active = TRUE",
    )
    .bind(tenant_id)
    .bind(entity_type)
    .fetch_one(&mut *txn)
    .await?;

    if et_count == 0 {
        issues.push(ConfigurationIssue {
            message: format!(
                "Entity type '{}' is not configured for this tenant. \
                 Go to Admin → Entity Types to create it.",
                entity_type
            ),
        });
        // Attribute and submaster checks are irrelevant when the type itself
        // is missing — return early so the error message stays focused.
        txn.rollback().await.ok();
        return Ok(issues);
    }

    // ── 2. At least one attribute schema must be defined ──────────────────
    let attr_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) \
         FROM core_mdm.attribute_schemas \
         WHERE LOWER(entity_type) = LOWER($1) \
           AND (tenant_id = $2 OR tenant_id IS NULL)",
    )
    .bind(entity_type)
    .bind(tenant_id)
    .fetch_one(&mut *txn)
    .await?;

    if attr_count == 0 {
        issues.push(ConfigurationIssue {
            message: format!(
                "No attribute schemas are defined for entity type '{}'. \
                 Go to Admin → Entity Types → {} → Attributes to add fields.",
                entity_type, entity_type
            ),
        });
    }

    // ── 3. Reference-data lists (submasters) must have active values ──────
    // Find submaster types used by this entity type's attribute schemas that
    // have no active values — those enum fields can never be populated.
    let empty_submasters: Vec<(String, String)> = sqlx::query_as(
        "SELECT DISTINCT s.code, s.name \
         FROM core_mdm.attribute_schemas a \
         JOIN core_mdm.submaster_types s \
              ON s.code = a.submaster_code \
             AND s.tenant_id = $2 \
         WHERE LOWER(a.entity_type) = LOWER($1) \
           AND (a.tenant_id = $2 OR a.tenant_id IS NULL) \
           AND a.submaster_code IS NOT NULL \
           AND NOT EXISTS ( \
               SELECT 1 \
               FROM core_mdm.submaster_values sv \
               WHERE sv.submaster_type_id = s.id \
                 AND sv.is_active = TRUE \
           )",
    )
    .bind(entity_type)
    .bind(tenant_id)
    .fetch_all(&mut *txn)
    .await?;

    for (code, name) in empty_submasters {
        issues.push(ConfigurationIssue {
            message: format!(
                "Reference data list '{}' ({}) has no active values. \
                 Go to Admin → Reference Data → {} to add options.",
                name, code, code
            ),
        });
    }

    txn.rollback().await.ok();
    Ok(issues)
}
