use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::matching::SemanticMatcher;

#[derive(Debug, Deserialize)]
pub struct ExplainMatchArgs {
    pub source_entity_id:    Uuid,
    pub candidate_entity_id: Uuid,
    pub match_score:         f32,
}

#[derive(Debug, Serialize)]
pub struct ExplainMatchResult {
    pub explanation:    String,
    pub source_name:    String,
    pub candidate_name: String,
    pub match_score:    f32,
}

pub async fn explain_match(
    pool:      &PgPool,
    matcher:   &SemanticMatcher,
    tenant_id: Uuid,
    args:      ExplainMatchArgs,
) -> Result<Value> {
    let source    = load_entity_attrs(pool, tenant_id, args.source_entity_id).await?;
    let candidate = load_entity_attrs(pool, tenant_id, args.candidate_entity_id).await?;

    let source_name    = extract_name(&source);
    let candidate_name = extract_name(&candidate);

    let explanation = matcher
        .explain(&source, &candidate, args.match_score, &Value::Null)
        .await?;

    Ok(serde_json::to_value(ExplainMatchResult {
        explanation,
        source_name,
        candidate_name,
        match_score: args.match_score,
    })?)
}

async fn load_entity_attrs(pool: &PgPool, tenant_id: Uuid, entity_id: Uuid) -> Result<Value> {
    let row = sqlx::query(
        "SELECT attributes FROM core_mdm.entities WHERE entity_id = $1 AND tenant_id = $2",
    )
    .bind(entity_id)
    .bind(tenant_id)
    .fetch_optional(pool)
    .await?;

    Ok(row
        .and_then(|r| r.try_get::<Value, _>("attributes").ok())
        .unwrap_or(Value::Object(serde_json::Map::new())))
}

fn extract_name(attrs: &Value) -> String {
    attrs
        .get("legal_name")
        .or_else(|| attrs.get("name"))
        .or_else(|| attrs.get("company_name"))
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string()
}
