use anyhow::{anyhow, Result};
use serde_json::json;
use sqlx::{PgPool, Row};
use uuid::Uuid;

// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM TENANT
// ─────────────────────────────────────────────────────────────────────────────

/// The system tenant owns built-in relationship types that are visible to all
/// tenants but cannot be deleted by regular tenant admins.
const SYSTEM_TENANT_ID: &str = "00000000-0000-0000-0000-000000000001";

// ─────────────────────────────────────────────────────────────────────────────
// RelationshipService
// ─────────────────────────────────────────────────────────────────────────────

pub struct RelationshipService {
    db: PgPool,
}

impl RelationshipService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RELATIONSHIP TYPES
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns system types (tenant_id = SYSTEM_TENANT_ID) UNION tenant-specific
    /// types owned by `tenant_id`, ordered by display_name.
    pub async fn list_types(
        &self,
        tenant_id: Uuid,
    ) -> Result<Vec<serde_json::Value>> {
        let system_id = Uuid::parse_str(SYSTEM_TENANT_ID)?;

        let rows = sqlx::query(
            r#"
            SELECT
                type_id,
                tenant_id,
                name,
                display_name,
                from_entity_type,
                to_entity_type,
                is_bidirectional,
                description,
                created_at
            FROM core_mdm.relationship_types
            WHERE tenant_id = $1
               OR tenant_id = $2
            ORDER BY display_name ASC
            "#,
        )
        .bind(tenant_id)
        .bind(system_id)
        .fetch_all(&self.db)
        .await?;

        let types = rows
            .iter()
            .map(|r| {
                json!({
                    "type_id":          r.try_get::<Uuid,   _>("type_id").unwrap_or(Uuid::nil()),
                    "tenant_id":        r.try_get::<Uuid,   _>("tenant_id").unwrap_or(Uuid::nil()),
                    "name":             r.try_get::<String, _>("name").unwrap_or_default(),
                    "display_name":     r.try_get::<String, _>("display_name").unwrap_or_default(),
                    "from_entity_type": r.try_get::<String, _>("from_entity_type").unwrap_or_default(),
                    "to_entity_type":   r.try_get::<String, _>("to_entity_type").unwrap_or_default(),
                    "is_bidirectional": r.try_get::<bool,   _>("is_bidirectional").unwrap_or(false),
                    "description":      r.try_get::<Option<String>, _>("description").unwrap_or(None),
                    "is_system":        r.try_get::<Uuid, _>("tenant_id")
                                            .map(|tid| tid == Uuid::parse_str(SYSTEM_TENANT_ID).unwrap_or(Uuid::nil()))
                                            .unwrap_or(false),
                    "created_at":       r.try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                                            .map(|d| d.to_rfc3339())
                                            .unwrap_or_default(),
                })
            })
            .collect();

        Ok(types)
    }

    /// Inserts a new tenant-owned relationship type and returns the generated
    /// `type_id`.
    pub async fn create_type(
        &self,
        tenant_id:        Uuid,
        name:             &str,
        display_name:     &str,
        from_type:        &str,
        to_type:          &str,
        is_bidirectional: bool,
        description:      Option<&str>,
    ) -> Result<Uuid> {
        let type_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.relationship_types
                (type_id, tenant_id, name, display_name, from_entity_type, to_entity_type,
                 is_bidirectional, description, created_at)
            VALUES
                (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, NOW())
            RETURNING type_id
            "#,
        )
        .bind(tenant_id)
        .bind(name)
        .bind(display_name)
        .bind(from_type)
        .bind(to_type)
        .bind(is_bidirectional)
        .bind(description)
        .fetch_one(&self.db)
        .await?;

        Ok(type_id)
    }

    /// Deletes a relationship type only when it belongs to `tenant_id` (not a
    /// system type).  Returns `true` if a row was deleted, `false` if the type
    /// was not found or is a system type owned by another tenant.
    pub async fn delete_type(
        &self,
        tenant_id: Uuid,
        type_id:   Uuid,
    ) -> Result<bool> {
        let system_id = Uuid::parse_str(SYSTEM_TENANT_ID)?;

        // Reject attempts to delete system types regardless of caller.
        let is_system: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM core_mdm.relationship_types WHERE type_id = $1 AND tenant_id = $2)",
        )
        .bind(type_id)
        .bind(system_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(false);

        if is_system {
            return Err(anyhow!("cannot delete a system relationship type"));
        }

        let affected = sqlx::query(
            "DELETE FROM core_mdm.relationship_types WHERE type_id = $1 AND tenant_id = $2",
        )
        .bind(type_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?
        .rows_affected();

        Ok(affected > 0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RELATIONSHIP INSTANCES
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns all relationships where `entity_id` is either the `from` side or
    /// (for bidirectional types) the `to` side, joined with their type metadata.
    pub async fn list_for_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Vec<serde_json::Value>> {
        let rows = sqlx::query(
            r#"
            SELECT
                er.relationship_id,
                er.type_id,
                er.from_entity_id,
                er.to_entity_id,
                er.strength,
                er.attributes,
                er.created_by,
                er.created_at,
                rt.display_name      AS type_display_name,
                rt.from_entity_type,
                rt.to_entity_type,
                rt.is_bidirectional,
                rt.name              AS type_name
            FROM core_mdm.entity_relationships er
            JOIN core_mdm.relationship_types rt
                ON rt.type_id = er.type_id
            WHERE er.tenant_id = $1
              AND (
                    er.from_entity_id = $2
                 OR (rt.is_bidirectional AND er.to_entity_id = $2)
              )
            ORDER BY er.created_at DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_all(&self.db)
        .await?;

        let relationships = rows
            .iter()
            .map(|r| {
                json!({
                    "relationship_id":   r.try_get::<Uuid,   _>("relationship_id").unwrap_or(Uuid::nil()),
                    "type_id":           r.try_get::<Uuid,   _>("type_id").unwrap_or(Uuid::nil()),
                    "type_name":         r.try_get::<String, _>("type_name").unwrap_or_default(),
                    "type_display_name": r.try_get::<String, _>("type_display_name").unwrap_or_default(),
                    "from_entity_id":    r.try_get::<Uuid,   _>("from_entity_id").unwrap_or(Uuid::nil()),
                    "to_entity_id":      r.try_get::<Uuid,   _>("to_entity_id").unwrap_or(Uuid::nil()),
                    "from_entity_type":  r.try_get::<String, _>("from_entity_type").unwrap_or_default(),
                    "to_entity_type":    r.try_get::<String, _>("to_entity_type").unwrap_or_default(),
                    "is_bidirectional":  r.try_get::<bool,   _>("is_bidirectional").unwrap_or(false),
                    "strength":          r.try_get::<f32,    _>("strength").unwrap_or(1.0),
                    "attributes":        r.try_get::<serde_json::Value, _>("attributes").unwrap_or(json!({})),
                    "created_by":        r.try_get::<Option<Uuid>, _>("created_by").unwrap_or(None),
                    "created_at":        r.try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                                             .map(|d| d.to_rfc3339())
                                             .unwrap_or_default(),
                })
            })
            .collect();

        Ok(relationships)
    }

    /// Inserts a new relationship instance.  Uses `ON CONFLICT DO NOTHING` to
    /// handle duplicate inserts gracefully; when a conflict occurs the existing
    /// `relationship_id` is returned via a follow-up SELECT.
    pub async fn create(
        &self,
        tenant_id:      Uuid,
        type_id:        Uuid,
        from_entity_id: Uuid,
        to_entity_id:   Uuid,
        strength:       f32,
        attributes:     serde_json::Value,
        created_by:     Option<Uuid>,
    ) -> Result<Uuid> {
        // Attempt insert; ON CONFLICT DO NOTHING means RETURNING returns nothing
        // on conflict.
        let inserted: Option<Uuid> = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.entity_relationships
                (relationship_id, tenant_id, type_id, from_entity_id, to_entity_id,
                 strength, attributes, created_by, created_at)
            VALUES
                (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, NOW())
            ON CONFLICT DO NOTHING
            RETURNING relationship_id
            "#,
        )
        .bind(tenant_id)
        .bind(type_id)
        .bind(from_entity_id)
        .bind(to_entity_id)
        .bind(strength)
        .bind(&attributes)
        .bind(created_by)
        .fetch_optional(&self.db)
        .await?;

        if let Some(id) = inserted {
            return Ok(id);
        }

        // Conflict: fetch the existing relationship_id.
        let existing: Uuid = sqlx::query_scalar(
            r#"
            SELECT relationship_id
            FROM core_mdm.entity_relationships
            WHERE tenant_id      = $1
              AND type_id        = $2
              AND from_entity_id = $3
              AND to_entity_id   = $4
            LIMIT 1
            "#,
        )
        .bind(tenant_id)
        .bind(type_id)
        .bind(from_entity_id)
        .bind(to_entity_id)
        .fetch_one(&self.db)
        .await?;

        Ok(existing)
    }

    /// Deletes a relationship scoped to the tenant.  Returns `true` if deleted.
    pub async fn delete(
        &self,
        tenant_id:       Uuid,
        relationship_id: Uuid,
    ) -> Result<bool> {
        let affected = sqlx::query(
            "DELETE FROM core_mdm.entity_relationships WHERE relationship_id = $1 AND tenant_id = $2",
        )
        .bind(relationship_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?
        .rows_affected();

        Ok(affected > 0)
    }

    /// Returns the total count of relationships (either direction) for an entity.
    pub async fn relationship_count_for_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) AS cnt
            FROM core_mdm.entity_relationships er
            JOIN core_mdm.relationship_types rt ON rt.type_id = er.type_id
            WHERE er.tenant_id = $1
              AND (
                    er.from_entity_id = $2
                 OR (rt.is_bidirectional AND er.to_entity_id = $2)
              )
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_one(&self.db)
        .await?;

        Ok(count)
    }
}
