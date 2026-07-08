use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct TemporalService {
    db: PgPool,
}

impl TemporalService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Record a new version snapshot for an entity.
    /// Called after every entity update to maintain bitemporal history.
    pub async fn record_version(
        &self,
        tenant_id:     Uuid,
        entity_id:     Uuid,
        attributes:    &Value,
        status:        &str,
        recorded_by:   Option<Uuid>,
        valid_from:    Option<chrono::DateTime<chrono::Utc>>,
        change_reason: Option<&str>,
        source_system: Option<&str>,
    ) -> Result<Uuid, sqlx::Error> {
        let valid_from = valid_from.unwrap_or_else(chrono::Utc::now);

        // Close the previous open version (valid_to = NULL means currently valid)
        sqlx::query(
            r#"
            UPDATE core_mdm.entity_versions
            SET valid_to = $3
            WHERE tenant_id = $1 AND entity_id = $2 AND valid_to IS NULL
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(valid_from)
        .execute(&self.db)
        .await?;

        // Insert the new version
        let version_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.entity_versions
                (tenant_id, entity_id, recorded_by, valid_from, valid_to,
                 attributes, status, change_reason, source_system)
            VALUES ($1, $2, $3, $4, NULL, $5, $6, $7, $8)
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(recorded_by)
        .bind(valid_from)
        .bind(attributes)
        .bind(status)
        .bind(change_reason)
        .bind(source_system)
        .fetch_one(&self.db)
        .await?;

        Ok(version_id)
    }

    /// Point-in-time query: what did entity E look like at transaction time T?
    pub async fn get_as_of(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        as_of:     chrono::DateTime<chrono::Utc>,
    ) -> Result<Option<Value>, sqlx::Error> {
        let row = sqlx::query(
            r#"
            SELECT id, recorded_at, recorded_by, valid_from, valid_to,
                   attributes, status, change_reason, source_system
            FROM core_mdm.entity_versions
            WHERE tenant_id = $1
              AND entity_id = $2
              AND recorded_at <= $3
            ORDER BY recorded_at DESC
            LIMIT 1
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(as_of)
        .fetch_optional(&self.db)
        .await?;

        Ok(row.map(|r| json!({
            "version_id":    r.get::<Uuid, _>("id"),
            "entity_id":     entity_id,
            "recorded_at":   r.get::<chrono::DateTime<chrono::Utc>, _>("recorded_at").to_rfc3339(),
            "recorded_by":   r.get::<Option<Uuid>, _>("recorded_by"),
            "valid_from":    r.get::<chrono::DateTime<chrono::Utc>, _>("valid_from").to_rfc3339(),
            "valid_to":      r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("valid_to").map(|d| d.to_rfc3339()),
            "attributes":    r.get::<Value, _>("attributes"),
            "status":        r.get::<String, _>("status"),
            "change_reason": r.get::<Option<String>, _>("change_reason"),
            "source_system": r.get::<Option<String>, _>("source_system"),
        })))
    }

    /// Bitemporal query: state of entity E that was valid during period [valid_from, valid_to]
    /// as known at transaction time T.
    pub async fn get_bitemporal(
        &self,
        tenant_id:          Uuid,
        entity_id:          Uuid,
        transaction_time:   chrono::DateTime<chrono::Utc>,
        valid_time:         chrono::DateTime<chrono::Utc>,
    ) -> Result<Option<Value>, sqlx::Error> {
        let row = sqlx::query(
            r#"
            SELECT id, recorded_at, recorded_by, valid_from, valid_to,
                   attributes, status, change_reason, source_system
            FROM core_mdm.entity_versions
            WHERE tenant_id   = $1
              AND entity_id   = $2
              AND recorded_at <= $3
              AND valid_from  <= $4
              AND (valid_to IS NULL OR valid_to > $4)
            ORDER BY recorded_at DESC
            LIMIT 1
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(transaction_time)
        .bind(valid_time)
        .fetch_optional(&self.db)
        .await?;

        Ok(row.map(|r| json!({
            "version_id":         r.get::<Uuid, _>("id"),
            "entity_id":          entity_id,
            "transaction_time":   transaction_time.to_rfc3339(),
            "valid_time":         valid_time.to_rfc3339(),
            "recorded_at":        r.get::<chrono::DateTime<chrono::Utc>, _>("recorded_at").to_rfc3339(),
            "valid_from":         r.get::<chrono::DateTime<chrono::Utc>, _>("valid_from").to_rfc3339(),
            "valid_to":           r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("valid_to").map(|d| d.to_rfc3339()),
            "attributes":         r.get::<Value, _>("attributes"),
            "status":             r.get::<String, _>("status"),
            "change_reason":      r.get::<Option<String>, _>("change_reason"),
        })))
    }

    /// Return the full version history of an entity (transaction-time ordered).
    pub async fn get_version_history(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        limit:     i64,
        offset:    i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, recorded_at, recorded_by, valid_from, valid_to,
                   attributes, status, change_reason, source_system
            FROM core_mdm.entity_versions
            WHERE tenant_id = $1 AND entity_id = $2
            ORDER BY recorded_at DESC
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "version_id":    r.get::<Uuid, _>("id"),
            "recorded_at":   r.get::<chrono::DateTime<chrono::Utc>, _>("recorded_at").to_rfc3339(),
            "recorded_by":   r.get::<Option<Uuid>, _>("recorded_by"),
            "valid_from":    r.get::<chrono::DateTime<chrono::Utc>, _>("valid_from").to_rfc3339(),
            "valid_to":      r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("valid_to").map(|d| d.to_rfc3339()),
            "status":        r.get::<String, _>("status"),
            "change_reason": r.get::<Option<String>, _>("change_reason"),
            "source_system": r.get::<Option<String>, _>("source_system"),
        })).collect())
    }
}
