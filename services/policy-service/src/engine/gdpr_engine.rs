use anyhow::Result;
use chrono::Utc;
use sqlx::{PgPool, Row};
use tracing::{info, instrument};
use uuid::Uuid;

use crate::models::{GdprRequest, GdprResult};

const PII_FIELDS: &[&str] = &[
    "name", "email", "phone", "address", "dob", "date_of_birth",
    "ssn", "tax_id", "passport_number", "national_id", "bank_account",
    "credit_card", "gender", "ethnicity", "religion", "health_data",
];

/// Processes GDPR data subject requests (erasure, access, portability).
pub struct GdprEngine {
    pool: PgPool,
}

impl GdprEngine {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Article 17 — Right to erasure ("right to be forgotten").
    ///
    /// Replaces all PII attribute values with `ERASED` for entities matching
    /// the subject_id and marks the entity status as `soft_deleted`.
    #[instrument(skip(self, req), fields(tenant_id=%req.tenant_id, subject_id=%req.subject_id))]
    pub async fn process_erasure(&self, req: &GdprRequest) -> Result<GdprResult> {
        let mut tx = self.pool.begin().await?;
        let fields_erased: Vec<String> = PII_FIELDS.iter().map(|s| s.to_string()).collect();
        let mut records_affected: i64 = 0;

        // Find entities belonging to this data subject
        let entity_ids: Vec<Uuid> = sqlx::query(
            r#"
            SELECT entity_id
            FROM core_mdm.entities
            WHERE tenant_id = $1
              AND (external_ids->>'subject_id' = $2::text
                   OR entity_id = $2)
              AND valid_to = 'infinity'
            "#,
        )
        .bind(req.tenant_id)
        .bind(req.subject_id)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .filter_map(|r| r.try_get::<Uuid, _>("entity_id").ok())
        .collect();

        for entity_id in &entity_ids {
            // ── 1. Erase PII attribute values (replace with ERASED placeholder)
            for field in &fields_erased {
                sqlx::query(
                    r#"
                    UPDATE core_mdm.entity_attributes
                    SET attribute_value = '"ERASED"'::jsonb
                    WHERE tenant_id     = $1
                      AND entity_id     = $2
                      AND attribute_key = $3
                    "#,
                )
                .bind(req.tenant_id)
                .bind(entity_id)
                .bind(field)
                .execute(&mut *tx)
                .await?;
            }

            // ── 2. Erase entity metadata (may contain PII in free-form fields)
            sqlx::query(
                "UPDATE core_mdm.entities SET metadata = '{}'::jsonb, updated_at = NOW() WHERE entity_id = $1 AND tenant_id = $2",
            )
            .bind(entity_id)
            .bind(req.tenant_id)
            .execute(&mut *tx)
            .await?;

            // ── 3. Delete vector embeddings (derived from PII text)
            // GDPR Art.17: embedding vectors are personal data if they can be
            // reverse-engineered to identify the subject.
            sqlx::query(
                "DELETE FROM ai.entity_embeddings WHERE entity_id = $1 AND tenant_id = $2",
            )
            .bind(entity_id)
            .bind(req.tenant_id)
            .execute(&mut *tx)
            .await
            .ok(); // Non-fatal if table doesn't exist

            // ── 4. Remove from RAG knowledge base
            sqlx::query(
                "DELETE FROM ai.rag_documents WHERE tenant_id = $1 AND metadata->>'entity_id' = $2::text",
            )
            .bind(req.tenant_id)
            .bind(entity_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();

            // ── 5. Purge steward feedback containing entity data
            sqlx::query(
                "DELETE FROM ai.steward_feedback WHERE tenant_id = $1 AND source_entity_id = $2",
            )
            .bind(req.tenant_id)
            .bind(entity_id)
            .execute(&mut *tx)
            .await
            .ok();

            // ── 6. Suppress pending outbox events for this entity
            // Do NOT delete historical events (needed for audit trail), but mark
            // them so downstream processors know the entity is erased.
            sqlx::query(
                r#"
                UPDATE event_store.outbox_events
                SET event_payload = jsonb_set(event_payload, '{_gdpr_erased}', 'true'::jsonb),
                    event_metadata = event_metadata || '{"gdpr_erased": true}'::jsonb
                WHERE tenant_id    = $1
                  AND aggregate_id = $2
                  AND published    = false
                "#,
            )
            .bind(req.tenant_id)
            .bind(entity_id)
            .execute(&mut *tx)
            .await
            .ok();

            // ── 7. Mark entity as soft-deleted (preserves record for audit)
            sqlx::query(
                "UPDATE core_mdm.entities SET status = 'SoftDeleted', updated_at = NOW() WHERE entity_id = $1 AND tenant_id = $2",
            )
            .bind(entity_id)
            .bind(req.tenant_id)
            .execute(&mut *tx)
            .await?;

            records_affected += 1;
        }

        // Write audit record
        let audit_id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO audit.gdpr_requests
            (audit_id, tenant_id, subject_id, request_type, records_affected, completed_at)
            VALUES ($1, $2, $3, $4, $5, NOW())
            "#,
        )
        .bind(audit_id)
        .bind(req.tenant_id)
        .bind(req.subject_id)
        .bind(req.request_type.to_string())
        .bind(records_affected)
        .execute(&mut *tx)
        .await
        .ok(); // Non-fatal if audit table doesn't exist yet

        tx.commit().await?;

        info!(
            subject_id=%req.subject_id,
            records_affected,
            "GDPR erasure completed"
        );

        Ok(GdprResult {
            subject_id:       req.subject_id,
            request_type:     req.request_type.clone(),
            fields_erased,
            records_affected,
            completed_at:     Utc::now(),
            audit_id,
        })
    }

    /// Article 15 — Right of access.
    ///
    /// Returns all non-erased data held for the subject as structured JSON.
    pub async fn process_access(&self, req: &GdprRequest) -> Result<serde_json::Value> {
        let rows = sqlx::query(
            r#"
            SELECT e.entity_id, e.entity_type, e.status,
                   json_agg(json_build_object(
                       'key',   ea.attribute_key,
                       'value', ea.attribute_value
                   )) AS attributes
            FROM core_mdm.entities e
            LEFT JOIN core_mdm.entity_attributes ea
                ON ea.entity_id = e.entity_id AND ea.tenant_id = e.tenant_id
            WHERE e.tenant_id = $1
              AND (e.external_ids->>'subject_id' = $2::text OR e.entity_id = $2)
              AND e.valid_to = 'infinity'
            GROUP BY e.entity_id, e.entity_type, e.status
            "#,
        )
        .bind(req.tenant_id)
        .bind(req.subject_id)
        .fetch_all(&self.pool)
        .await?;

        let entities: Vec<serde_json::Value> = rows
            .into_iter()
            .map(|r| {
                serde_json::json!({
                    "entity_id":   r.try_get::<Uuid, _>("entity_id").unwrap_or(Uuid::nil()),
                    "entity_type": r.try_get::<String, _>("entity_type").unwrap_or_default(),
                    "status":      r.try_get::<String, _>("status").unwrap_or_default(),
                    "attributes":  r.try_get::<serde_json::Value, _>("attributes").unwrap_or(serde_json::Value::Null),
                })
            })
            .collect();

        Ok(serde_json::json!({
            "subject_id":   req.subject_id,
            "tenant_id":    req.tenant_id,
            "request_type": req.request_type.to_string(),
            "entities":     entities,
            "generated_at": Utc::now(),
        }))
    }
}
