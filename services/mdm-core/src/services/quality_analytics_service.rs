use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Clone)]
pub struct QualityAnalyticsService {
    db: PgPool,
}

impl QualityAnalyticsService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn get_quality_trends(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
        dimension:   Option<&str>,
        days:        i32,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT snapshot_date, dimension, entity_type, source_system,
                   score, total_entities, violation_count
            FROM core_mdm.quality_snapshots
            WHERE tenant_id   = $1
              AND ($2::text IS NULL OR entity_type = $2)
              AND ($3::text IS NULL OR dimension    = $3)
              AND snapshot_date >= CURRENT_DATE - ($4 * INTERVAL '1 day')
              AND entity_type IS NOT NULL
            ORDER BY snapshot_date ASC, dimension ASC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(dimension)
        .bind(days)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "snapshot_date":   r.get::<chrono::NaiveDate, _>("snapshot_date").to_string(),
            "dimension":       r.get::<String, _>("dimension"),
            "entity_type":     r.get::<Option<String>, _>("entity_type"),
            "source_system":   r.get::<Option<String>, _>("source_system"),
            "score":           r.get::<f64, _>("score"),
            "total_entities":  r.get::<i32, _>("total_entities"),
            "violation_count": r.get::<i32, _>("violation_count"),
        })).collect())
    }

    pub async fn get_dimension_breakdown(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT ON (dimension)
                dimension, score, total_entities, violation_count, snapshot_date
            FROM core_mdm.quality_snapshots
            WHERE tenant_id = $1
              AND ($2::text IS NULL OR entity_type = $2)
              AND source_system IS NULL
            ORDER BY dimension, snapshot_date DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "dimension":       r.get::<String, _>("dimension"),
            "score":           r.get::<f64, _>("score"),
            "total_entities":  r.get::<i32, _>("total_entities"),
            "violation_count": r.get::<i32, _>("violation_count"),
            "snapshot_date":   r.get::<chrono::NaiveDate, _>("snapshot_date").to_string(),
        })).collect())
    }

    pub async fn get_source_quality_ranking(
        &self,
        tenant_id: Uuid,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT
                e.source_system,
                COUNT(DISTINCT e.id)::integer                                               AS entity_count,
                COUNT(CASE WHEN v.id IS NOT NULL THEN 1 END)::integer                       AS violation_count,
                ROUND(
                    100.0 * (1.0 - COUNT(CASE WHEN v.id IS NOT NULL THEN 1 END)::decimal
                                 / NULLIF(COUNT(DISTINCT e.id), 0)
                    ), 2
                )                                                                           AS quality_score
            FROM core_mdm.entities e
            LEFT JOIN core_mdm.quality_violations v
                ON v.entity_id = e.id AND v.status = 'open' AND v.tenant_id = e.tenant_id
            WHERE e.tenant_id = $1 AND e.is_deleted = false
            GROUP BY e.source_system
            ORDER BY quality_score ASC
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "source_system":   r.get::<Option<String>, _>("source_system"),
            "entity_count":    r.get::<i32, _>("entity_count"),
            "violation_count": r.get::<i32, _>("violation_count"),
            "quality_score":   r.get::<Option<f64>, _>("quality_score").unwrap_or(100.0),
        })).collect())
    }

    // Computes today's quality scores from live data and upserts into quality_snapshots.
    // Returns the number of snapshot rows written.
    pub async fn take_daily_snapshot(
        &self,
        tenant_id: Uuid,
    ) -> Result<i32, sqlx::Error> {
        let mut tx = self.db.begin().await?;

        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let count: i64 = sqlx::query_scalar(
            r#"
            WITH scores AS (
                SELECT
                    e.entity_type,
                    v.dimension,
                    COUNT(DISTINCT e.id)::integer                                               AS total_entities,
                    COUNT(CASE WHEN v.id IS NOT NULL THEN 1 END)::integer                       AS violation_count,
                    ROUND(
                        100.0 * (1.0 - COUNT(CASE WHEN v.id IS NOT NULL THEN 1 END)::decimal
                                     / NULLIF(COUNT(DISTINCT e.id), 0)
                        ), 2
                    )                                                                           AS score
                FROM core_mdm.entities e
                CROSS JOIN (
                    VALUES ('completeness'),('accuracy'),('uniqueness'),('validity'),('consistency'),('timeliness')
                ) AS dims(dimension)
                LEFT JOIN core_mdm.quality_violations v
                    ON v.entity_id = e.id
                    AND v.dimension = dims.dimension
                    AND v.status    = 'open'
                    AND v.tenant_id = e.tenant_id
                WHERE e.tenant_id = $1 AND e.is_deleted = false
                GROUP BY e.entity_type, dims.dimension
            )
            INSERT INTO core_mdm.quality_snapshots
                (tenant_id, entity_type, dimension, score, total_entities, violation_count, snapshot_date)
            SELECT $1, entity_type, dimension, COALESCE(score, 100.0), total_entities, violation_count, CURRENT_DATE
            FROM scores
            ON CONFLICT (tenant_id, entity_type, source_system, dimension, snapshot_date)
            DO UPDATE SET
                score           = EXCLUDED.score,
                total_entities  = EXCLUDED.total_entities,
                violation_count = EXCLUDED.violation_count
            "#,
        )
        .bind(tenant_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap_or(0_i64);

        tx.commit().await?;
        Ok(count as i32)
    }

    // Convenience: list all distinct tenants with at least one entity.
    pub async fn list_active_tenants(&self) -> Result<Vec<Uuid>, sqlx::Error> {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT tenant_id FROM core_mdm.entities WHERE is_deleted = false",
        )
        .fetch_all(&self.db)
        .await?;
        Ok(ids)
    }
}
