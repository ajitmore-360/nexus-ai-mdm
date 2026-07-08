use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct ReferenceDataService {
    db: PgPool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateListInput {
    pub list_code:   String,
    pub list_name:   String,
    pub description: Option<String>,
    pub version:     Option<String>,
    pub metadata:    Option<Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpsertValueInput {
    pub code:        String,
    pub label:       String,
    pub description: Option<String>,
    pub parent_code: Option<String>,
    pub sort_order:  Option<i32>,
    pub extra:       Option<Value>,
}

impl ReferenceDataService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn create_list(
        &self,
        tenant_id: Uuid,
        input:     CreateListInput,
    ) -> Result<Uuid, sqlx::Error> {
        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.reference_lists
                (tenant_id, list_code, list_name, description, version, metadata)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (tenant_id, list_code) DO UPDATE SET
                list_name   = EXCLUDED.list_name,
                description = EXCLUDED.description,
                version     = EXCLUDED.version,
                metadata    = EXCLUDED.metadata,
                updated_at  = NOW()
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(&input.list_code)
        .bind(&input.list_name)
        .bind(&input.description)
        .bind(input.version.as_deref().unwrap_or("1.0"))
        .bind(input.metadata.unwrap_or(json!({})))
        .fetch_one(&self.db)
        .await?;

        Ok(id)
    }

    pub async fn list_lists(
        &self,
        tenant_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, list_code, list_name, description, version, is_system, is_active,
                   metadata, created_at, updated_at,
                   (SELECT COUNT(*) FROM core_mdm.reference_values rv
                    WHERE rv.list_id = rl.id AND rv.is_active = true) AS value_count
            FROM core_mdm.reference_lists rl
            WHERE tenant_id = $1 AND is_active = true
            ORDER BY list_name
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":          r.get::<Uuid, _>("id"),
            "list_code":   r.get::<String, _>("list_code"),
            "list_name":   r.get::<String, _>("list_name"),
            "description": r.get::<Option<String>, _>("description"),
            "version":     r.get::<String, _>("version"),
            "is_system":   r.get::<bool, _>("is_system"),
            "value_count": r.get::<i64, _>("value_count"),
            "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
        })).collect())
    }

    pub async fn upsert_value(
        &self,
        tenant_id: Uuid,
        list_id:   Uuid,
        input:     UpsertValueInput,
    ) -> Result<Uuid, sqlx::Error> {
        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.reference_values
                (tenant_id, list_id, code, label, description, parent_code, sort_order, extra)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (tenant_id, list_id, code) DO UPDATE SET
                label       = EXCLUDED.label,
                description = EXCLUDED.description,
                parent_code = EXCLUDED.parent_code,
                sort_order  = EXCLUDED.sort_order,
                extra       = EXCLUDED.extra,
                updated_at  = NOW()
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(list_id)
        .bind(&input.code)
        .bind(&input.label)
        .bind(&input.description)
        .bind(&input.parent_code)
        .bind(input.sort_order.unwrap_or(0))
        .bind(input.extra.unwrap_or(json!({})))
        .fetch_one(&self.db)
        .await?;

        Ok(id)
    }

    pub async fn get_values(
        &self,
        tenant_id:   Uuid,
        list_id:     Uuid,
        search:      Option<&str>,
        parent_code: Option<&str>,
        limit:       i64,
        offset:      i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, code, label, description, parent_code, sort_order, extra, is_active
            FROM core_mdm.reference_values
            WHERE tenant_id = $1 AND list_id = $2 AND is_active = true
              AND ($3::text IS NULL OR label ILIKE '%' || $3 || '%' OR code ILIKE '%' || $3 || '%')
              AND ($4::text IS NULL OR parent_code = $4)
            ORDER BY sort_order, label
            LIMIT $5 OFFSET $6
            "#,
        )
        .bind(tenant_id)
        .bind(list_id)
        .bind(search)
        .bind(parent_code)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":          r.get::<Uuid, _>("id"),
            "code":        r.get::<String, _>("code"),
            "label":       r.get::<String, _>("label"),
            "description": r.get::<Option<String>, _>("description"),
            "parent_code": r.get::<Option<String>, _>("parent_code"),
            "sort_order":  r.get::<i32, _>("sort_order"),
            "extra":       r.get::<Value, _>("extra"),
        })).collect())
    }

    pub async fn delete_value(
        &self,
        tenant_id: Uuid,
        value_id:  Uuid,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE core_mdm.reference_values SET is_active=false, updated_at=NOW() WHERE id=$1 AND tenant_id=$2",
        )
        .bind(value_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Bulk import values from a JSON array [{code, label, ...}]
    pub async fn bulk_import_values(
        &self,
        tenant_id: Uuid,
        list_id:   Uuid,
        values:    Vec<UpsertValueInput>,
    ) -> Result<usize, sqlx::Error> {
        let mut count = 0usize;
        for v in values {
            self.upsert_value(tenant_id, list_id, v).await?;
            count += 1;
        }
        Ok(count)
    }
}
