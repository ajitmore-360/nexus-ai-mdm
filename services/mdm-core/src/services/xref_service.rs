use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct XrefService {
    db: PgPool,
}

impl XrefService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn list_xrefs(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, entity_id, source_system, external_id, external_type, metadata, created_at, updated_at
            FROM core_mdm.entity_xrefs
            WHERE tenant_id = $1 AND entity_id = $2
            ORDER BY source_system ASC, created_at ASC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":            r.get::<Uuid, _>("id"),
            "entity_id":     r.get::<Uuid, _>("entity_id"),
            "source_system": r.get::<String, _>("source_system"),
            "external_id":   r.get::<String, _>("external_id"),
            "external_type": r.get::<Option<String>, _>("external_type"),
            "metadata":      r.get::<Value, _>("metadata"),
            "created_at":    r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
            "updated_at":    r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
        })).collect())
    }

    pub async fn upsert_xref(
        &self,
        tenant_id:     Uuid,
        entity_id:     Uuid,
        source_system: &str,
        external_id:   &str,
        external_type: Option<&str>,
        metadata:      Value,
    ) -> Result<Uuid, sqlx::Error> {
        let mut tx = self.db.begin().await?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.entity_xrefs
                (tenant_id, entity_id, source_system, external_id, external_type, metadata)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (tenant_id, source_system, external_id)
            DO UPDATE SET
                entity_id     = EXCLUDED.entity_id,
                external_type = EXCLUDED.external_type,
                metadata      = EXCLUDED.metadata,
                updated_at    = NOW()
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(source_system)
        .bind(external_id)
        .bind(external_type)
        .bind(metadata)
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(id)
    }

    pub async fn delete_xref(
        &self,
        tenant_id: Uuid,
        xref_id:   Uuid,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            "DELETE FROM core_mdm.entity_xrefs WHERE id = $1 AND tenant_id = $2 RETURNING 1",
        )
        .bind(xref_id)
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }

    pub async fn find_entity_by_xref(
        &self,
        tenant_id:     Uuid,
        source_system: &str,
        external_id:   &str,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        let id: Option<Uuid> = sqlx::query_scalar(
            "SELECT entity_id FROM core_mdm.entity_xrefs WHERE tenant_id=$1 AND source_system=$2 AND external_id=$3",
        )
        .bind(tenant_id)
        .bind(source_system)
        .bind(external_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(id)
    }
}
