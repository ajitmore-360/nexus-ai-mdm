use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct HierarchyService {
    db: PgPool,
}

impl HierarchyService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn set_parent(
        &self,
        tenant_id:  Uuid,
        entity_id:  Uuid,
        parent_id:  Option<Uuid>,
    ) -> Result<(), String> {
        if let Some(pid) = parent_id {
            if pid == entity_id {
                return Err("Entity cannot be its own parent".to_string());
            }
            // Guard against circular references: is entity_id an ancestor of parent_id?
            let would_cycle: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM core_mdm.entity_hierarchies WHERE ancestor_id=$1 AND descendant_id=$2)",
            )
            .bind(entity_id)
            .bind(pid)
            .fetch_one(&self.db)
            .await
            .unwrap_or(false);

            if would_cycle {
                return Err("Circular hierarchy: the chosen parent is a descendant of this entity".to_string());
            }
        }

        let mut tx = self.db.begin().await.map_err(|e| e.to_string())?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;

        sqlx::query("SELECT core_mdm.set_entity_parent($1, $2, $3)")
            .bind(entity_id)
            .bind(parent_id)
            .bind(tenant_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;

        tx.commit().await.map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn get_children(
        &self,
        tenant_id: Uuid,
        parent_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT e.id, e.entity_type, e.status, e.attributes, h.depth
            FROM core_mdm.entity_hierarchies h
            JOIN core_mdm.entities e ON e.id = h.descendant_id
            WHERE h.ancestor_id = $1 AND h.tenant_id = $2 AND h.depth = 1
              AND e.tenant_id = $2 AND e.is_deleted = false
            ORDER BY e.attributes->>'name' ASC
            "#,
        )
        .bind(parent_id)
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| {
            let attrs: Value = r.try_get("attributes").unwrap_or(Value::Null);
            json!({
                "id":          r.get::<Uuid, _>("id"),
                "entity_type": r.get::<String, _>("entity_type"),
                "status":      r.get::<String, _>("status"),
                "name":        attrs.get("name").and_then(|v| v.as_str()).unwrap_or(""),
                "attributes":  attrs,
                "depth":       r.get::<i32, _>("depth"),
            })
        }).collect())
    }

    pub async fn get_ancestors(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT e.id, e.entity_type, e.status, e.attributes, h.depth
            FROM core_mdm.entity_hierarchies h
            JOIN core_mdm.entities e ON e.id = h.ancestor_id
            WHERE h.descendant_id = $1 AND h.tenant_id = $2 AND h.depth > 0
            ORDER BY h.depth DESC
            "#,
        )
        .bind(entity_id)
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| {
            let attrs: Value = r.try_get("attributes").unwrap_or(Value::Null);
            json!({
                "id":          r.get::<Uuid, _>("id"),
                "entity_type": r.get::<String, _>("entity_type"),
                "status":      r.get::<String, _>("status"),
                "name":        attrs.get("name").and_then(|v| v.as_str()).unwrap_or(""),
                "attributes":  attrs,
                "depth":       r.get::<i32, _>("depth"),
            })
        }).collect())
    }

    pub async fn get_subtree(
        &self,
        tenant_id: Uuid,
        root_id:   Uuid,
        max_depth: i32,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT e.id, e.entity_type, e.status, e.attributes, h.depth, h.ancestor_id AS parent_id
            FROM core_mdm.entity_hierarchies h
            JOIN core_mdm.entities e ON e.id = h.descendant_id
            WHERE h.ancestor_id = $1 AND h.tenant_id = $2
              AND h.depth > 0 AND h.depth <= $3
              AND e.tenant_id = $2 AND e.is_deleted = false
            ORDER BY h.depth ASC, e.attributes->>'name' ASC
            "#,
        )
        .bind(root_id)
        .bind(tenant_id)
        .bind(max_depth)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| {
            let attrs: Value = r.try_get("attributes").unwrap_or(Value::Null);
            json!({
                "id":          r.get::<Uuid, _>("id"),
                "parent_id":   r.get::<Uuid, _>("parent_id"),
                "entity_type": r.get::<String, _>("entity_type"),
                "status":      r.get::<String, _>("status"),
                "name":        attrs.get("name").and_then(|v| v.as_str()).unwrap_or(""),
                "attributes":  attrs,
                "depth":       r.get::<i32, _>("depth"),
            })
        }).collect())
    }

    pub async fn get_roots(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT e.id, e.entity_type, e.status, e.attributes
            FROM core_mdm.entities e
            WHERE e.tenant_id = $1
              AND e.parent_entity_id IS NULL
              AND e.is_deleted = false
              AND ($2::text IS NULL OR e.entity_type = $2)
            ORDER BY e.entity_type ASC, e.attributes->>'name' ASC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| {
            let attrs: Value = r.try_get("attributes").unwrap_or(Value::Null);
            json!({
                "id":          r.get::<Uuid, _>("id"),
                "entity_type": r.get::<String, _>("entity_type"),
                "status":      r.get::<String, _>("status"),
                "name":        attrs.get("name").and_then(|v| v.as_str()).unwrap_or(""),
                "attributes":  attrs,
                "parent_id":   Option::<Uuid>::None,
            })
        }).collect())
    }
}
