use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct QualityReportArgs {
    pub entity_type: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct QualityReport {
    pub tenant_id:         String,
    pub entity_type:       Option<String>,
    pub total_entities:    i64,
    pub golden_records:    i64,
    pub avg_trust_score:   f64,
    pub avg_quality_score: f64,
    pub pending_review:    i64,
    pub duplicates_found:  i64,
}

pub async fn quality_report(
    pool:      &PgPool,
    tenant_id: Uuid,
    args:      QualityReportArgs,
) -> Result<Value> {
    let row = if let Some(ref etype) = args.entity_type {
        sqlx::query(
            r#"
            SELECT
                COUNT(*)                                              AS total,
                AVG(trust_score)::FLOAT8                             AS avg_trust,
                AVG(quality_score)::FLOAT8                           AS avg_quality,
                COUNT(*) FILTER (WHERE status = 'pending_review')    AS pending
            FROM core_mdm.entities
            WHERE tenant_id   = $1
              AND entity_type = $2
              AND valid_to    = 'infinity'
            "#,
        )
        .bind(tenant_id)
        .bind(etype)
        .fetch_one(pool)
        .await?
    } else {
        sqlx::query(
            r#"
            SELECT
                COUNT(*)                                              AS total,
                AVG(trust_score)::FLOAT8                             AS avg_trust,
                AVG(quality_score)::FLOAT8                           AS avg_quality,
                COUNT(*) FILTER (WHERE status = 'pending_review')    AS pending
            FROM core_mdm.entities
            WHERE tenant_id = $1
              AND valid_to  = 'infinity'
            "#,
        )
        .bind(tenant_id)
        .fetch_one(pool)
        .await?
    };

    let golden: i64 = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM core_mdm.golden_records WHERE tenant_id = $1 AND valid_to = 'infinity'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await?
    .try_get("cnt")
    .unwrap_or(0);

    let dupes: i64 = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM core_mdm.match_candidates WHERE tenant_id = $1 AND requires_human_review = TRUE",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await?
    .try_get("cnt")
    .unwrap_or(0);

    let report = QualityReport {
        tenant_id:         tenant_id.to_string(),
        entity_type:       args.entity_type,
        total_entities:    row.try_get("total").unwrap_or(0),
        golden_records:    golden,
        avg_trust_score:   row.try_get("avg_trust").unwrap_or(0.0),
        avg_quality_score: row.try_get("avg_quality").unwrap_or(0.0),
        pending_review:    row.try_get("pending").unwrap_or(0),
        duplicates_found:  dupes,
    };

    Ok(serde_json::to_value(report)?)
}
