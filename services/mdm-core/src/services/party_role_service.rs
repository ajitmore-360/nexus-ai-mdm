use anyhow::{anyhow, Result};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

pub struct PartyRoleService {
    db: PgPool,
}

#[derive(Debug, serde::Deserialize)]
pub struct UpsertRoleInput {
    pub role_code:    String,
    pub role_status:  Option<String>,
    pub external_id:  Option<String>,
    pub source_system: Option<String>,
    pub valid_from:   Option<chrono::NaiveDate>,
    pub valid_to:     Option<chrono::NaiveDate>,
    pub metadata:     Option<Value>,
}

impl PartyRoleService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn upsert_role(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        input:     UpsertRoleInput,
    ) -> Result<Value> {
        use sqlx::Row;
        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.party_roles
                (tenant_id, entity_id, role_code, role_status, external_id,
                 source_system, valid_from, valid_to, metadata)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
            ON CONFLICT (tenant_id, entity_id, role_code)
            DO UPDATE SET
                role_status   = EXCLUDED.role_status,
                external_id   = COALESCE(EXCLUDED.external_id, core_mdm.party_roles.external_id),
                source_system = COALESCE(EXCLUDED.source_system, core_mdm.party_roles.source_system),
                valid_from    = COALESCE(EXCLUDED.valid_from, core_mdm.party_roles.valid_from),
                valid_to      = COALESCE(EXCLUDED.valid_to, core_mdm.party_roles.valid_to),
                metadata      = COALESCE(EXCLUDED.metadata, core_mdm.party_roles.metadata),
                updated_at    = NOW()
            RETURNING id, role_code, role_status, external_id, source_system,
                      valid_from, valid_to, metadata, created_at, updated_at
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(&input.role_code)
        .bind(input.role_status.as_deref().unwrap_or("Active"))
        .bind(input.external_id.as_deref())
        .bind(input.source_system.as_deref())
        .bind(input.valid_from)
        .bind(input.valid_to)
        .bind(input.metadata.unwrap_or_else(|| json!({})))
        .fetch_one(&self.db)
        .await
        .map_err(|e| anyhow!(e))?;

        Ok(json!({
            "id":           row.get::<Uuid, _>("id"),
            "role_code":    row.get::<String, _>("role_code"),
            "role_status":  row.get::<String, _>("role_status"),
            "external_id":  row.get::<Option<String>, _>("external_id"),
            "source_system":row.get::<Option<String>, _>("source_system"),
            "valid_from":   row.get::<Option<chrono::NaiveDate>, _>("valid_from").map(|d| d.to_string()),
            "valid_to":     row.get::<Option<chrono::NaiveDate>, _>("valid_to").map(|d| d.to_string()),
            "metadata":     row.get::<Value, _>("metadata"),
            "created_at":   row.get::<chrono::DateTime<chrono::Utc>, _>("created_at"),
            "updated_at":   row.get::<chrono::DateTime<chrono::Utc>, _>("updated_at"),
        }))
    }

    pub async fn list_roles(&self, tenant_id: Uuid, entity_id: Uuid) -> Result<Vec<Value>> {
        use sqlx::Row;
        let rows = sqlx::query(
            r#"
            SELECT id, role_code, role_status, external_id, source_system,
                   valid_from, valid_to, metadata, created_at, updated_at
            FROM core_mdm.party_roles
            WHERE tenant_id = $1 AND entity_id = $2
            ORDER BY role_code
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":           r.get::<Uuid, _>("id"),
            "role_code":    r.get::<String, _>("role_code"),
            "role_status":  r.get::<String, _>("role_status"),
            "external_id":  r.get::<Option<String>, _>("external_id"),
            "source_system":r.get::<Option<String>, _>("source_system"),
            "valid_from":   r.get::<Option<chrono::NaiveDate>, _>("valid_from").map(|d| d.to_string()),
            "valid_to":     r.get::<Option<chrono::NaiveDate>, _>("valid_to").map(|d| d.to_string()),
            "metadata":     r.get::<Value, _>("metadata"),
        })).collect())
    }

    pub async fn delete_role(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        role_code: &str,
    ) -> Result<bool> {
        let r = sqlx::query(
            "DELETE FROM core_mdm.party_roles WHERE tenant_id=$1 AND entity_id=$2 AND role_code=$3",
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(role_code)
        .execute(&self.db)
        .await?;
        Ok(r.rows_affected() > 0)
    }

    /// Find all entities that hold a given role code.
    pub async fn entities_by_role(
        &self,
        tenant_id: Uuid,
        role_code: &str,
        status:    Option<&str>,
    ) -> Result<Vec<Value>> {
        use sqlx::Row;
        let rows = sqlx::query(
            r#"
            SELECT pr.entity_id, pr.external_id, pr.source_system,
                   pr.valid_from, pr.valid_to, pr.role_status,
                   e.attributes->>'name' AS entity_name
            FROM core_mdm.party_roles pr
            JOIN core_mdm.entities e ON e.id = pr.entity_id
            WHERE pr.tenant_id = $1
              AND pr.role_code  = $2
              AND ($3::text IS NULL OR pr.role_status = $3)
            ORDER BY e.attributes->>'name'
            "#,
        )
        .bind(tenant_id)
        .bind(role_code)
        .bind(status)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "entity_id":    r.get::<Uuid, _>("entity_id"),
            "entity_name":  r.get::<Option<String>, _>("entity_name"),
            "external_id":  r.get::<Option<String>, _>("external_id"),
            "source_system":r.get::<Option<String>, _>("source_system"),
            "role_status":  r.get::<String, _>("role_status"),
            "valid_from":   r.get::<Option<chrono::NaiveDate>, _>("valid_from").map(|d| d.to_string()),
            "valid_to":     r.get::<Option<chrono::NaiveDate>, _>("valid_to").map(|d| d.to_string()),
        })).collect())
    }
}
