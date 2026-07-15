use std::sync::Arc;
use std::time::Duration;

use azile_redis::queue::task_types;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::jobs;
use crate::models::{IngestBatch, IngestRecord};
use crate::state::AppState;

/// Payload stored in an `ingest.batch` Redis task.
#[derive(serde::Deserialize)]
struct IngestChunkPayload {
    job_id:        Uuid,
    batch_id:      Uuid,
    tenant_id:     Uuid,
    source_system: String,
    records:       Vec<IngestRecord>,
}

/// Runs one worker loop: polls the `ingest.batch` queue and processes chunks.
///
/// Spawned as a Tokio task in `main`. Multiple workers can run in parallel
/// (controlled by `INGEST_WORKER_CONCURRENCY`) — each pops its own chunk
/// from the priority queue, so they do not interfere with each other.
pub async fn run_worker(state: Arc<AppState>, worker_id: usize) {
    info!(worker_id, "ingest worker started");

    loop {
        let task_queue = match &state.task_queue {
            Some(q) => q.clone(),
            None => {
                warn!(worker_id, "no task queue configured — worker exiting");
                return;
            }
        };

        match task_queue.dequeue(task_types::INGEST_BATCH).await {
            Ok(Some(task)) => {
                info!(
                    worker_id,
                    task_id = %task.task_id,
                    "dequeued ingest chunk"
                );
                process_chunk(Arc::clone(&state), task, worker_id).await;
            }
            Ok(None) => {
                // Queue is empty — back off briefly before polling again.
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
            Err(e) => {
                error!(worker_id, error=%e, "failed to dequeue ingest task");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
}

async fn process_chunk(state: Arc<AppState>, task: azile_redis::queue::Task, worker_id: usize) {
    let payload: IngestChunkPayload = match serde_json::from_value(task.payload.clone()) {
        Ok(p)  => p,
        Err(e) => {
            error!(worker_id, error=%e, "malformed ingest chunk payload — dropping task");
            return;
        }
    };

    let batch = IngestBatch {
        batch_id:     payload.batch_id,
        tenant_id:    payload.tenant_id,
        source_system: payload.source_system,
        records:      payload.records,
        file_name:    None,
    };

    let result = match state.processor.process_batch_bulk(&batch, &[]).await {
        Ok(r)  => r,
        Err(e) => {
            error!(
                worker_id,
                job_id = %payload.job_id,
                error  = %e,
                "bulk processing failed for chunk"
            );
            // Count all records as failed and update job progress so the
            // UI reflects partial failure rather than stalling at 0%.
            let _ = jobs::update_job_progress(
                &state.pool,
                payload.job_id,
                0,
                batch.records.len() as i32,
            ).await;
            maybe_complete_job(&state, payload.job_id).await;
            return;
        }
    };

    if let Err(e) = jobs::update_job_progress(
        &state.pool,
        payload.job_id,
        result.processed as i32,
        result.failed    as i32,
    ).await {
        warn!(worker_id, job_id=%payload.job_id, error=%e, "failed to update job progress");
    }

    maybe_complete_job(&state, payload.job_id).await;

    info!(
        worker_id,
        job_id    = %payload.job_id,
        processed = result.processed,
        failed    = result.failed,
        duration_ms = result.duration_ms,
        "chunk processed"
    );
}

/// Check whether all chunks for this job have finished and, if so, mark it
/// as completed/partial_success/failed. Uses a single atomic SQL update so
/// concurrent workers don't race.
async fn maybe_complete_job(state: &AppState, job_id: Uuid) {
    let done: Option<bool> = sqlx::query_scalar(
        "SELECT chunks_done >= chunks_total FROM ingest.ingest_jobs WHERE job_id = $1",
    )
    .bind(job_id)
    .fetch_optional(&state.pool)
    .await
    .unwrap_or(None);

    if done == Some(true) {
        if let Err(e) = jobs::complete_job(&state.pool, job_id).await {
            warn!(job_id=%job_id, error=%e, "failed to mark ingest job complete");
        } else {
            info!(job_id=%job_id, "ingest job complete");
        }
    }
}
