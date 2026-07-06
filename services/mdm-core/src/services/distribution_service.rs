use sqlx::{PgPool, Row};
use uuid::Uuid;

pub struct CreateJobRequest {
    pub name:          String,
    pub target_system: String,
    pub filter_config: Option<serde_json::Value>,
}

pub struct DistributionService {
    db: PgPool,
}

impl DistributionService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn create(
        &self,
        tenant_id:  Uuid,
        req:        CreateJobRequest,
        created_by: Option<Uuid>,
    ) -> Result<serde_json::Value, sqlx::Error> {
        let filter = req.filter_config.unwrap_or(serde_json::json!({}));
        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.distribution_jobs
                (tenant_id, name, target_system, filter_config, created_by)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING job_id, name, target_system, filter_config, status, created_at, updated_at
            "#,
        )
        .bind(tenant_id)
        .bind(&req.name)
        .bind(&req.target_system)
        .bind(&filter)
        .bind(created_by)
        .fetch_one(&self.db)
        .await?;

        Ok(row_to_json(&row))
    }

    pub async fn list(
        &self,
        tenant_id: Uuid,
        page:      i64,
        page_size: i64,
    ) -> Result<(Vec<serde_json::Value>, i64), sqlx::Error> {
        let offset = (page - 1) * page_size;
        let rows = sqlx::query(
            r#"
            SELECT job_id, name, target_system, filter_config, status,
                   record_count, error_message, created_by, created_at, started_at,
                   completed_at, updated_at
            FROM   core_mdm.distribution_jobs
            WHERE  tenant_id = $1
            ORDER  BY created_at DESC
            LIMIT  $2 OFFSET $3
            "#,
        )
        .bind(tenant_id)
        .bind(page_size)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        let items: Vec<serde_json::Value> = rows.iter().map(row_to_json).collect();

        let total: i64 = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM core_mdm.distribution_jobs WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0);

        Ok((items, total))
    }

    pub async fn get(
        &self,
        tenant_id: Uuid,
        job_id:    Uuid,
    ) -> Result<Option<serde_json::Value>, sqlx::Error> {
        let row = sqlx::query(
            r#"
            SELECT job_id, name, target_system, filter_config, status,
                   record_count, error_message, created_by, created_at, started_at,
                   completed_at, updated_at
            FROM   core_mdm.distribution_jobs
            WHERE  tenant_id = $1 AND job_id = $2
            "#,
        )
        .bind(tenant_id)
        .bind(job_id)
        .fetch_optional(&self.db)
        .await?;

        Ok(row.as_ref().map(row_to_json))
    }

    /// Move a draft job to the 'queued' state so it can be picked up by a worker.
    pub async fn queue(
        &self,
        tenant_id: Uuid,
        job_id:    Uuid,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE core_mdm.distribution_jobs \
             SET status = 'queued' \
             WHERE tenant_id = $1 AND job_id = $2 AND status = 'draft'",
        )
        .bind(tenant_id)
        .bind(job_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    /// Cancel a job that is still in 'draft' or 'queued' state.
    pub async fn cancel(
        &self,
        tenant_id: Uuid,
        job_id:    Uuid,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE core_mdm.distribution_jobs \
             SET status = 'cancelled' \
             WHERE tenant_id = $1 AND job_id = $2 AND status IN ('draft','queued')",
        )
        .bind(tenant_id)
        .bind(job_id)
        .execute(&self.db)
        .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn row_to_json(r: &sqlx::postgres::PgRow) -> serde_json::Value {
    let created_at: chrono::DateTime<chrono::Utc>         = r.get("created_at");
    let updated_at: chrono::DateTime<chrono::Utc>         = r.get("updated_at");
    let started_at: Option<chrono::DateTime<chrono::Utc>> = r.try_get("started_at").ok().flatten();
    let completed_at: Option<chrono::DateTime<chrono::Utc>> = r.try_get("completed_at").ok().flatten();

    serde_json::json!({
        "job_id":        r.get::<Uuid, _>("job_id").to_string(),
        "name":          r.get::<String, _>("name"),
        "target_system": r.get::<String, _>("target_system"),
        "filter_config": r.get::<serde_json::Value, _>("filter_config"),
        "status":        r.get::<String, _>("status"),
        "record_count":  r.try_get::<Option<i32>, _>("record_count").ok().flatten(),
        "error_message": r.try_get::<Option<String>, _>("error_message").ok().flatten(),
        "created_at":    created_at.to_rfc3339(),
        "started_at":    started_at.map(|t| t.to_rfc3339()),
        "completed_at":  completed_at.map(|t| t.to_rfc3339()),
        "updated_at":    updated_at.to_rfc3339(),
    })
}
