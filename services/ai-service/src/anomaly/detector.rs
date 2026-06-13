use anyhow::Result;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AnomalySeverity {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Anomaly {
    pub anomaly_id:     Uuid,
    pub tenant_id:      Uuid,
    pub severity:       AnomalySeverity,
    pub category:       String,
    pub field_name:     Option<String>,
    pub entity_type:    Option<String>,
    pub source_system:  Option<String>,
    pub description:    String,
    pub affected_count: i64,
    pub detected_at:    chrono::DateTime<Utc>,
}

impl Anomaly {
    fn new(tenant_id: Uuid, severity: AnomalySeverity, category: &str, description: &str, affected_count: i64) -> Self {
        Self {
            anomaly_id:     Uuid::new_v4(),
            tenant_id,
            severity,
            category:       category.to_string(),
            field_name:     None,
            entity_type:    None,
            source_system:  None,
            description:    description.to_string(),
            affected_count,
            detected_at:    Utc::now(),
        }
    }
}

pub struct AnomalyDetector {
    pool: PgPool,
}

impl AnomalyDetector {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn scan(&self, tenant_id: Uuid) -> Result<Vec<Anomaly>> {
        let mut anomalies = Vec::new();
        anomalies.extend(self.check_duplicate_spike(tenant_id).await?);
        anomalies.extend(self.check_low_quality_sources(tenant_id).await?);
        anomalies.extend(self.check_stale_entities(tenant_id).await?);
        info!(tenant_id=%tenant_id, anomaly_count=anomalies.len(), "anomaly scan complete");
        Ok(anomalies)
    }

    async fn check_duplicate_spike(&self, tenant_id: Uuid) -> Result<Vec<Anomaly>> {
        // Cast AVG to FLOAT8 to avoid NUMERIC type requirement
        let row = sqlx::query(
            r#"
            WITH daily AS (
                SELECT
                    DATE_TRUNC('day', created_at) AS day,
                    COUNT(*)                       AS cnt
                FROM core_mdm.match_candidates
                WHERE tenant_id  = $1
                  AND created_at >= NOW() - INTERVAL '30 days'
                GROUP BY 1
            ),
            stats AS (
                SELECT
                    AVG(cnt)::FLOAT8 AS avg_daily,
                    MAX(CASE WHEN day = CURRENT_DATE THEN cnt END) AS today
                FROM daily
            )
            SELECT avg_daily, today FROM stats
            "#,
        )
        .bind(tenant_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(r) = row {
            let avg:   f64 = r.try_get::<f64, _>("avg_daily").unwrap_or(0.0);
            let today: i64 = r.try_get::<i64, _>("today").unwrap_or(0);

            if avg > 0.0 && today as f64 > avg * 3.0 {
                return Ok(vec![Anomaly {
                    category:      "duplicate_spike".to_string(),
                    description:   format!(
                        "Duplicate detection rate today ({today}) is {:.1}× the 30-day average ({avg:.0}). Check recent ingestion.",
                        today as f64 / avg,
                    ),
                    affected_count: today,
                    ..Anomaly::new(tenant_id, AnomalySeverity::High, "duplicate_spike", "", today)
                }]);
            }
        }
        Ok(vec![])
    }

    async fn check_low_quality_sources(&self, tenant_id: Uuid) -> Result<Vec<Anomaly>> {
        let rows = sqlx::query(
            r#"
            SELECT
                source_system,
                AVG(trust_score)::FLOAT8  AS avg_quality,
                COUNT(*)                  AS entity_count
            FROM core_mdm.entities
            WHERE tenant_id = $1
              AND valid_to  = 'infinity'
              AND source_system IS NOT NULL
            GROUP BY source_system
            HAVING AVG(trust_score) < 0.70
            ORDER BY avg_quality ASC
            LIMIT 5
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.pool)
        .await?;

        let anomalies = rows
            .into_iter()
            .map(|r| {
                let source:  String = r.try_get("source_system").unwrap_or_default();
                let quality: f64    = r.try_get("avg_quality").unwrap_or(0.0);
                let count:   i64    = r.try_get("entity_count").unwrap_or(0);
                let severity = if quality < 0.50 { AnomalySeverity::High } else { AnomalySeverity::Medium };
                Anomaly {
                    source_system:  Some(source.clone()),
                    category:       "low_quality_source".to_string(),
                    description:    format!(
                        "Source '{}' has avg trust score {:.0}% across {} entities.",
                        source, quality * 100.0, count
                    ),
                    affected_count: count,
                    ..Anomaly::new(tenant_id, severity, "low_quality_source", "", count)
                }
            })
            .collect();

        Ok(anomalies)
    }

    async fn check_stale_entities(&self, tenant_id: Uuid) -> Result<Vec<Anomaly>> {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*) AS stale_count
            FROM core_mdm.entities
            WHERE tenant_id = $1
              AND valid_to  = 'infinity'
              AND updated_at < NOW() - INTERVAL '90 days'
            "#,
        )
        .bind(tenant_id)
        .fetch_one(&self.pool)
        .await?;

        let count: i64 = row.try_get("stale_count").unwrap_or(0);
        if count > 1000 {
            return Ok(vec![Anomaly::new(
                tenant_id,
                AnomalySeverity::Low,
                "stale_entities",
                &format!("{count} entities not refreshed in 90+ days. Trigger re-sync from source systems."),
                count,
            )]);
        }
        Ok(vec![])
    }
}
