use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct UnmergeService {
    db: PgPool,
}

impl UnmergeService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Reverse a merge operation on a golden record.
    ///
    /// Strategy:
    ///   1. Look for a completed merge_request record with pre_merge_entity_snapshots (new path).
    ///   2. If none, fall back to re-activating the merged entities still tracked in
    ///      lineage.entity_lineage (merged_into) — their rows are only soft-merged,
    ///      not deleted, so this is always safe.
    pub async fn unmerge_entity(
        &self,
        tenant_id:        Uuid,
        golden_record_id: Uuid,
        initiated_by:     Uuid,
        reason:           Option<String>,
    ) -> Result<Vec<Uuid>, String> {
        let entity_row = sqlx::query(
            "SELECT id, status FROM core_mdm.entities WHERE id=$1 AND tenant_id=$2 AND is_deleted=false",
        )
        .bind(golden_record_id)
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let entity_row = entity_row.ok_or_else(|| "Entity not found".to_string())?;
        let current_status: String = entity_row.get("status");

        if !["Golden", "Merged", "Active"].contains(&current_status.as_str()) {
            return Err(format!("Cannot unmerge entity with status '{}'", current_status));
        }

        // ── Try snapshot-based restore (merge_requests table) ─────────────────
        let merge_row = sqlx::query(
            r#"
            SELECT id, pre_merge_entity_snapshots
            FROM core_mdm.merge_requests
            WHERE golden_record_id = $1 AND tenant_id = $2 AND status = 'Completed'
            ORDER BY completed_at DESC
            LIMIT 1
            "#,
        )
        .bind(golden_record_id)
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await
        .map_err(|e| e.to_string())?;

        let mut tx = self.db.begin().await.map_err(|e| e.to_string())?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;

        let mut restored_ids: Vec<Uuid> = Vec::new();

        if let Some(row) = merge_row {
            // ── Snapshot path: restore from pre_merge_entity_snapshots ─────────
            let merge_request_id: Uuid  = row.get("id");
            let snapshots: Value = row.try_get("pre_merge_entity_snapshots")
                .unwrap_or(Value::Array(vec![]));
            let snapshots_arr = snapshots.as_array().cloned().unwrap_or_default();

            for snapshot in &snapshots_arr {
                let snap_entity_type = snapshot.get("entity_type")
                    .and_then(|v| v.as_str()).unwrap_or("Unknown");
                let snap_attributes  = snapshot.get("attributes").cloned().unwrap_or(json!({}));
                let snap_source      = snapshot.get("source_system").and_then(|v| v.as_str());
                let snap_trust       = snapshot.get("trust_score").and_then(|v| v.as_f64()).unwrap_or(0.5);
                let snap_status      = snapshot.get("status")
                    .and_then(|v| v.as_str()).unwrap_or("Active");

                let restored_id: Uuid = sqlx::query_scalar(
                    r#"
                    INSERT INTO core_mdm.entities
                        (tenant_id, entity_type, status, attributes, source_system, trust_score, is_deleted)
                    VALUES ($1, $2, $3, $4, $5, $6, false)
                    RETURNING id
                    "#,
                )
                .bind(tenant_id)
                .bind(snap_entity_type)
                .bind(snap_status)
                .bind(snap_attributes)
                .bind(snap_source)
                .bind(snap_trust)
                .fetch_one(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;

                restored_ids.push(restored_id);

                let note = format!(
                    "Unmerged by {} — {}",
                    initiated_by,
                    reason.as_deref().unwrap_or("no reason given")
                );
                sqlx::query(
                    r#"
                    INSERT INTO lineage.entity_lineage
                        (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
                    VALUES (gen_random_uuid(), $1, $2, $3, 'unmerged_from', $4)
                    "#,
                )
                .bind(tenant_id)
                .bind(golden_record_id)
                .bind(restored_id)
                .bind(json!({ "reason": note }))
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;
            }

            sqlx::query(
                "UPDATE core_mdm.merge_requests SET status='Unmerged', updated_at=NOW() WHERE id=$1 AND tenant_id=$2",
            )
            .bind(merge_request_id)
            .bind(tenant_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;

        } else {
            // ── Lineage path: re-activate merged source entities ───────────────
            // Find all entities that were merged INTO this golden record.
            let lineage_rows = sqlx::query(
                r#"
                SELECT source_entity_id
                FROM lineage.entity_lineage
                WHERE tenant_id = $1
                  AND target_entity_id = $2
                  AND lineage_type = 'merged_into'
                "#,
            )
            .bind(tenant_id)
            .bind(golden_record_id)
            .fetch_all(&self.db)
            .await
            .map_err(|e| e.to_string())?;

            if lineage_rows.is_empty() {
                return Err(
                    "No merged entities found in lineage — cannot unmerge".to_string()
                );
            }

            let note = json!({
                "reason": format!(
                    "Unmerged by {} — {}",
                    initiated_by,
                    reason.as_deref().unwrap_or("no reason given")
                )
            });

            for row in &lineage_rows {
                let source_id: Uuid = row.get("source_entity_id");

                sqlx::query(
                    "UPDATE core_mdm.entities SET status='Active', golden_record_id=NULL, updated_at=NOW() WHERE id=$1 AND tenant_id=$2",
                )
                .bind(source_id)
                .bind(tenant_id)
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;

                sqlx::query(
                    r#"
                    INSERT INTO lineage.entity_lineage
                        (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
                    VALUES (gen_random_uuid(), $1, $2, $3, 'unmerged_from', $4)
                    "#,
                )
                .bind(tenant_id)
                .bind(golden_record_id)
                .bind(source_id)
                .bind(&note)
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;

                restored_ids.push(source_id);
            }
        }

        sqlx::query(
            "UPDATE core_mdm.entities SET status='Inactive', updated_at=NOW() WHERE id=$1 AND tenant_id=$2",
        )
        .bind(golden_record_id)
        .bind(tenant_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;

        tx.commit().await.map_err(|e| e.to_string())?;

        Ok(restored_ids)
    }

    pub async fn list_unmerge_history(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT lineage_id, target_entity_id AS restored_entity_id, metadata, created_at
            FROM lineage.entity_lineage
            WHERE tenant_id = $1
              AND source_entity_id = $2
              AND lineage_type = 'unmerged_from'
            ORDER BY created_at DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "lineage_id":         r.get::<Uuid, _>("lineage_id"),
            "restored_entity_id": r.get::<Option<Uuid>, _>("restored_entity_id"),
            "metadata":           r.get::<Value, _>("metadata"),
            "created_at":         r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
        })).collect())
    }
}
