use std::time::Duration;

use anyhow::Result;
use sqlx::{PgPool, Row};
use tracing::{info, instrument, warn};
use uuid::Uuid;

use crate::connectors::build_connector;

const POLL_INTERVAL_SECS: u64 = 5;
const MAX_ATTEMPTS: i32       = 3;

/// Polls `platform.distribution_jobs` for pending jobs and executes them.
///
/// Retry logic: exponential back-off between attempts (5s → 25s → 125s).
/// After `MAX_ATTEMPTS` failures the job is marked `failed` and moved to
/// the dead-letter queue.
pub struct DistributionWorker {
    pool: PgPool,
}

impl DistributionWorker {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Run indefinitely, polling for pending jobs.
    pub async fn run(&self) {
        info!("Distribution worker started");
        loop {
            if let Err(e) = self.process_batch().await {
                warn!(error=%e, "distribution batch error");
            }
            tokio::time::sleep(Duration::from_secs(POLL_INTERVAL_SECS)).await;
        }
    }

    async fn process_batch(&self) -> Result<()> {
        // Fetch up to 50 pending jobs that are ready to run.
        // Pending jobs with a future next_attempt_at are skipped until their
        // backoff window elapses (exponential: 5s → 25s → 125s).
        let rows = sqlx::query(
            r#"
            SELECT
                j.job_id, j.tenant_id, j.connector_id, j.entity_id,
                j.entity_type, j.payload, j.attempts,
                c.connector_type, c.endpoint_url, c.config AS connector_config
            FROM platform.distribution_jobs j
            JOIN platform.distribution_connectors c ON c.connector_id = j.connector_id
            WHERE j.status = 'pending'
              AND j.attempts < $1
              AND (j.next_attempt_at IS NULL OR j.next_attempt_at <= NOW())
            ORDER BY j.created_at ASC
            LIMIT 50
            FOR UPDATE SKIP LOCKED
            "#,
        )
        .bind(MAX_ATTEMPTS)
        .fetch_all(&self.pool)
        .await?;

        for row in rows {
            let job_id:    Uuid   = row.try_get("job_id")?;
            let payload:   serde_json::Value = row.try_get("payload")?;
            let conn_type: String = row.try_get("connector_type")?;
            let endpoint:  Option<String>  = row.try_get("endpoint_url").ok().flatten();
            let config:    serde_json::Value = row.try_get("connector_config").unwrap_or(serde_json::Value::Null);

            self.execute_job(job_id, &payload, &conn_type, endpoint.as_deref(), &config).await;
        }

        Ok(())
    }

    #[instrument(skip(self, payload, config), fields(job_id=%job_id))]
    async fn execute_job(
        &self,
        job_id:     Uuid,
        payload:    &serde_json::Value,
        conn_type:  &str,
        endpoint:   Option<&str>,
        config:     &serde_json::Value,
    ) {
        match build_connector(conn_type, endpoint, config) {
            None => {
                self.mark_failed(job_id, "no connector built for type").await;
            }
            Some(connector) => {
                match connector.send(payload).await {
                    Ok(()) => {
                        self.mark_completed(job_id).await;
                        info!(job_id=%job_id, connector=%conn_type, "distribution job completed");
                    }
                    Err(e) => {
                        warn!(job_id=%job_id, error=%e, "distribution job failed");
                        self.mark_failed(job_id, &e.to_string()).await;
                    }
                }
            }
        }
    }

    async fn mark_completed(&self, job_id: Uuid) {
        let _ = sqlx::query(
            "UPDATE platform.distribution_jobs SET status='completed', completed_at=NOW() WHERE job_id=$1",
        )
        .bind(job_id)
        .execute(&self.pool)
        .await;
    }

    async fn mark_failed(&self, job_id: Uuid, error: &str) {
        // Compute exponential backoff: 5^(attempt+1) seconds (5s → 25s → 125s).
        // After MAX_ATTEMPTS the job is permanently failed and won't be retried.
        let _ = sqlx::query(
            r#"
            UPDATE platform.distribution_jobs
            SET attempts       = attempts + 1,
                error_message  = $3,
                status         = CASE WHEN attempts + 1 >= $2 THEN 'failed' ELSE 'pending' END,
                next_attempt_at = CASE
                    WHEN attempts + 1 >= $2 THEN NULL
                    ELSE NOW() + (POWER(5, attempts + 1) || ' seconds')::INTERVAL
                END
            WHERE job_id = $1
            "#,
        )
        .bind(job_id)
        .bind(MAX_ATTEMPTS as i32)
        .bind(error)
        .execute(&self.pool)
        .await;
    }
}
