use anyhow::Result;
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

use crate::models::{IngestBatch, IngestResult, IngestStatus};

/// Persist the result of a completed batch to `ingest.ingest_jobs`.
/// Returns the newly created `job_id`.
pub async fn persist_job(
    pool:   &PgPool,
    batch:  &IngestBatch,
    result: &IngestResult,
) -> Result<Uuid> {
    let job_id = Uuid::new_v4();
    let status = match result.status {
        IngestStatus::Completed      => "completed",
        IngestStatus::Failed         => "failed",
        IngestStatus::PartialSuccess => "partial_success",
        IngestStatus::Processing     => "processing",
        IngestStatus::Pending        => "pending",
    };

    sqlx::query(
        r#"
        INSERT INTO ingest.ingest_jobs (
            job_id, batch_id, tenant_id, source_system, status,
            total_records, processed, failed, skipped,
            entity_ids, errors, duration_ms, file_name, completed_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
        "#,
    )
    .bind(job_id)
    .bind(batch.batch_id)
    .bind(batch.tenant_id)
    .bind(&batch.source_system)
    .bind(status)
    .bind(batch.records.len() as i32)
    .bind(result.processed as i32)
    .bind(result.failed as i32)
    .bind(result.skipped as i32)
    .bind(&result.entity_ids)
    .bind(&result.errors)
    .bind(result.duration_ms as i64)
    .bind(batch.file_name.as_deref())
    .bind(Utc::now())
    .execute(pool)
    .await?;

    Ok(job_id)
}

/// Fetch a single job by id, scoped to the calling tenant.
pub async fn get_job(
    pool:      &PgPool,
    job_id:    Uuid,
    tenant_id: Uuid,
) -> Result<Option<serde_json::Value>> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"
        SELECT job_id, batch_id, tenant_id, source_system, status,
               total_records, processed, failed, skipped,
               entity_ids, errors, duration_ms, file_name, created_at, completed_at
        FROM ingest.ingest_jobs
        WHERE job_id = $1 AND tenant_id = $2
        "#,
    )
    .bind(job_id)
    .bind(tenant_id)
    .fetch_optional(pool)
    .await?;

    let Some(row) = row else { return Ok(None) };

    Ok(Some(serde_json::json!({
        "job_id":        row.get::<Uuid,   _>("job_id"),
        "batch_id":      row.get::<Uuid,   _>("batch_id"),
        "tenant_id":     row.get::<Uuid,   _>("tenant_id"),
        "source_system": row.get::<String, _>("source_system"),
        "status":        row.get::<String, _>("status"),
        "total_records": row.get::<i32,    _>("total_records"),
        "processed":     row.get::<i32,    _>("processed"),
        "failed":        row.get::<i32,    _>("failed"),
        "skipped":       row.get::<i32,    _>("skipped"),
        "entity_ids":    row.get::<Vec<Uuid>,    _>("entity_ids"),
        "errors":        row.get::<Vec<String>,  _>("errors"),
        "duration_ms":   row.get::<i64,    _>("duration_ms"),
        "file_name":     row.get::<Option<String>, _>("file_name"),
        "created_at":    row.get::<chrono::DateTime<Utc>, _>("created_at").to_rfc3339(),
        "completed_at":  row.get::<Option<chrono::DateTime<Utc>>, _>("completed_at")
                             .map(|d| d.to_rfc3339()),
    })))
}

/// Paginated list of jobs for a tenant, newest first.
pub async fn list_jobs(
    pool:      &PgPool,
    tenant_id: Uuid,
    page:      i64,
    page_size: i64,
) -> Result<(Vec<serde_json::Value>, i64)> {
    use sqlx::Row;

    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM ingest.ingest_jobs WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await?;

    let offset = (page - 1) * page_size;

    let rows = sqlx::query(
        r#"
        SELECT job_id, batch_id, source_system, status,
               total_records, processed, failed, duration_ms, file_name, created_at, completed_at
        FROM ingest.ingest_jobs
        WHERE tenant_id = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(tenant_id)
    .bind(page_size)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let items = rows
        .iter()
        .map(|row| {
            serde_json::json!({
                "job_id":        row.get::<Uuid,   _>("job_id"),
                "batch_id":      row.get::<Uuid,   _>("batch_id"),
                "source_system": row.get::<String, _>("source_system"),
                "status":        row.get::<String, _>("status"),
                "total_records": row.get::<i32,    _>("total_records"),
                "processed":     row.get::<i32,    _>("processed"),
                "failed":        row.get::<i32,    _>("failed"),
                "duration_ms":   row.get::<i64,    _>("duration_ms"),
                "file_name":     row.get::<Option<String>, _>("file_name"),
                "created_at":    row.get::<chrono::DateTime<Utc>, _>("created_at").to_rfc3339(),
                "completed_at":  row.get::<Option<chrono::DateTime<Utc>>, _>("completed_at")
                                     .map(|d| d.to_rfc3339()),
            })
        })
        .collect();

    Ok((items, total))
}
