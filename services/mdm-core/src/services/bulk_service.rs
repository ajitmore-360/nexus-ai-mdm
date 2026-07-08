use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct BulkResult {
    pub updated:    usize,
    pub skipped:    usize,
    pub failed_ids: Vec<Uuid>,
}

#[derive(Clone)]
pub struct BulkService {
    db: PgPool,
}

impl BulkService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn bulk_update_status(
        &self,
        tenant_id:   Uuid,
        entity_ids:  Vec<Uuid>,
        new_status:  &str,
        _updated_by: Uuid,
    ) -> Result<BulkResult, sqlx::Error> {
        let allowed = ["Active", "Inactive", "PendingReview", "Archived"];
        if !allowed.contains(&new_status) {
            return Ok(BulkResult { updated: 0, skipped: entity_ids.len(), failed_ids: entity_ids });
        }

        let mut tx = self.db.begin().await?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let updated_ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            UPDATE core_mdm.entities
            SET status = $1, updated_at = NOW()
            WHERE id = ANY($2) AND tenant_id = $3
            RETURNING id
            "#,
        )
        .bind(new_status)
        .bind(&entity_ids)
        .bind(tenant_id)
        .fetch_all(&mut *tx)
        .await?;

        tx.commit().await?;

        let updated = updated_ids.len();
        let skipped = entity_ids.len().saturating_sub(updated);
        Ok(BulkResult { updated, skipped, failed_ids: vec![] })
    }

    pub async fn bulk_export_csv(
        &self,
        tenant_id:   Uuid,
        entity_ids:  Vec<Uuid>,
    ) -> Result<String, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, entity_type, status, trust_score, attributes, source_system,
                   created_at, updated_at
            FROM core_mdm.entities
            WHERE id = ANY($1) AND tenant_id = $2 AND is_deleted = false
            ORDER BY entity_type ASC, created_at DESC
            "#,
        )
        .bind(&entity_ids)
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        // Collect all unique attribute keys across all rows for the header
        let mut attr_keys: Vec<String> = Vec::new();
        for row in &rows {
            let attrs: Value = row.try_get("attributes").unwrap_or(Value::Null);
            if let Some(obj) = attrs.as_object() {
                for k in obj.keys() {
                    if !attr_keys.contains(k) {
                        attr_keys.push(k.clone());
                    }
                }
            }
        }
        attr_keys.sort();

        // Build CSV header
        let mut csv = String::new();
        let fixed_cols = ["id", "entity_type", "status", "trust_score", "source_system", "created_at", "updated_at"];
        let header: Vec<&str> = fixed_cols.iter().copied()
            .chain(attr_keys.iter().map(|s| s.as_str()))
            .collect();
        csv.push_str(&header.join(","));
        csv.push('\n');

        // Build data rows
        for row in &rows {
            let id:           Uuid                             = row.get("id");
            let entity_type:  String                          = row.get("entity_type");
            let status:       String                          = row.get("status");
            let trust_score:  Option<f64>                     = row.get("trust_score");
            let source_system: Option<String>                 = row.get("source_system");
            let created_at:   chrono::DateTime<chrono::Utc>  = row.get("created_at");
            let updated_at:   chrono::DateTime<chrono::Utc>  = row.get("updated_at");
            let attrs:        Value                           = row.try_get("attributes").unwrap_or(Value::Null);

            let mut cols = vec![
                id.to_string(),
                entity_type,
                status,
                trust_score.map(|v| format!("{:.2}", v)).unwrap_or_default(),
                source_system.unwrap_or_default(),
                created_at.to_rfc3339(),
                updated_at.to_rfc3339(),
            ];
            for key in &attr_keys {
                let val = attrs.get(key).map(|v| match v {
                    Value::String(s) => s.replace(',', ";").replace('\n', " "),
                    Value::Number(n) => n.to_string(),
                    Value::Bool(b)   => b.to_string(),
                    Value::Null      => String::new(),
                    other            => other.to_string().replace(',', ";"),
                }).unwrap_or_default();
                cols.push(val);
            }
            csv.push_str(&cols.join(","));
            csv.push('\n');
        }

        Ok(csv)
    }

    pub async fn bulk_tag(
        &self,
        tenant_id:  Uuid,
        entity_ids: Vec<Uuid>,
        tag:        &str,
        remove:     bool,
    ) -> Result<BulkResult, sqlx::Error> {
        let mut tx = self.db.begin().await?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let updated_ids: Vec<Uuid> = if remove {
            sqlx::query_scalar(
                r#"
                UPDATE core_mdm.entities
                SET attributes = jsonb_set(
                    attributes,
                    '{tags}',
                    COALESCE(attributes->'tags', '[]'::jsonb) - $1::text
                ), updated_at = NOW()
                WHERE id = ANY($2) AND tenant_id = $3
                RETURNING id
                "#,
            )
            .bind(tag)
            .bind(&entity_ids)
            .bind(tenant_id)
            .fetch_all(&mut *tx)
            .await?
        } else {
            sqlx::query_scalar(
                r#"
                UPDATE core_mdm.entities
                SET attributes = jsonb_set(
                    attributes,
                    '{tags}',
                    (COALESCE(attributes->'tags', '[]'::jsonb) || to_jsonb($1::text)) - $1::text
                    || to_jsonb($1::text)
                ), updated_at = NOW()
                WHERE id = ANY($2) AND tenant_id = $3
                  AND NOT (COALESCE(attributes->'tags', '[]'::jsonb) @> to_jsonb($1::text))
                RETURNING id
                "#,
            )
            .bind(tag)
            .bind(&entity_ids)
            .bind(tenant_id)
            .fetch_all(&mut *tx)
            .await?
        };

        tx.commit().await?;

        let updated = updated_ids.len();
        let skipped = entity_ids.len().saturating_sub(updated);
        Ok(BulkResult { updated, skipped, failed_ids: vec![] })
    }

    pub async fn get_entity_ids_for_type(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
        limit:       i64,
    ) -> Result<Vec<Uuid>, sqlx::Error> {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT id FROM core_mdm.entities
            WHERE tenant_id = $1
              AND is_deleted = false
              AND ($2::text IS NULL OR entity_type = $2)
            ORDER BY created_at DESC
            LIMIT $3
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(limit)
        .fetch_all(&self.db)
        .await?;
        Ok(ids)
    }
}
