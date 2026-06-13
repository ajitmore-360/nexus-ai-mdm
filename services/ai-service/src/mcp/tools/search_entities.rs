use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct SearchEntitiesArgs {
    pub query:       String,
    pub entity_type: Option<String>,
    pub limit:       Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct SearchEntitiesResult {
    pub entities: Vec<EntitySummary>,
    pub count:    usize,
}

#[derive(Debug, Serialize)]
pub struct EntitySummary {
    pub entity_id:   Uuid,
    pub entity_type: String,
    pub status:      String,
    pub attributes:  Value,
    pub trust_score: f32,
}

pub async fn search_entities(
    pool:      &PgPool,
    tenant_id: Uuid,
    args:      SearchEntitiesArgs,
) -> Result<Value> {
    let limit = args.limit.unwrap_or(10).min(50);

    // Use the plainto_tsquery full-text search on the jsonb attributes column
    let rows = if let Some(ref etype) = args.entity_type {
        sqlx::query(
            r#"
            SELECT entity_id, entity_type, status, attributes, trust_score
            FROM core_mdm.entities
            WHERE tenant_id   = $1
              AND entity_type = $2
              AND valid_to    = 'infinity'
              AND to_tsvector('english', attributes::text) @@ plainto_tsquery('english', $3)
            ORDER BY trust_score DESC
            LIMIT $4
            "#,
        )
        .bind(tenant_id)
        .bind(etype)
        .bind(&args.query)
        .bind(limit)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query(
            r#"
            SELECT entity_id, entity_type, status, attributes, trust_score
            FROM core_mdm.entities
            WHERE tenant_id = $1
              AND valid_to  = 'infinity'
              AND to_tsvector('english', attributes::text) @@ plainto_tsquery('english', $2)
            ORDER BY trust_score DESC
            LIMIT $3
            "#,
        )
        .bind(tenant_id)
        .bind(&args.query)
        .bind(limit)
        .fetch_all(pool)
        .await?
    };

    let entities: Vec<EntitySummary> = rows
        .into_iter()
        .map(|r| EntitySummary {
            entity_id:   r.try_get("entity_id").unwrap_or(Uuid::nil()),
            entity_type: r.try_get("entity_type").unwrap_or_default(),
            status:      r.try_get("status").unwrap_or_default(),
            attributes:  r.try_get::<Value, _>("attributes").unwrap_or(Value::Null),
            trust_score: r.try_get::<f32, _>("trust_score").unwrap_or(0.0),
        })
        .collect();

    let count = entities.len();
    Ok(serde_json::to_value(SearchEntitiesResult { entities, count })?)
}
