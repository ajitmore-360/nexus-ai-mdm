use anyhow::Result;
use chrono::Utc;
use deadpool_redis::Pool;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tracing::{debug, warn};
use uuid::Uuid;

/// A task enqueued for async processing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub task_id:    String,
    pub task_type:  String,
    pub tenant_id:  String,
    pub payload:    serde_json::Value,
    pub priority:   u8,             // 0 = low, 255 = critical
    pub enqueued_at: String,
    pub attempts:   u32,
    pub max_attempts: u32,
}

impl Task {
    pub fn new(
        task_type: impl Into<String>,
        tenant_id: impl Into<String>,
        payload: serde_json::Value,
    ) -> Self {
        Self {
            task_id:      Uuid::new_v4().to_string(),
            task_type:    task_type.into(),
            tenant_id:    tenant_id.into(),
            payload,
            priority:     128,
            enqueued_at:  Utc::now().to_rfc3339(),
            attempts:     0,
            max_attempts: 3,
        }
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.priority = priority;
        self
    }
}

/// Known task type constants.
pub mod task_types {
    pub const ENTITY_MATCH:    &str = "entity.match";
    pub const ENTITY_EMBED:    &str = "entity.embed";
    pub const MERGE_EXECUTE:   &str = "merge.execute";
    pub const GOLDEN_PUBLISH:  &str = "golden.publish";
    pub const INGEST_BATCH:    &str = "ingest.batch";
    pub const AI_ENRICH:       &str = "ai.enrich";
    pub const ANOMALY_SCAN:    &str = "anomaly.scan";
    pub const RAG_INDEX:       &str = "rag.index";
}

/// Simple Redis-backed task queue using Redis Lists (LPUSH / BRPOP).
///
/// For priority queuing a sorted set is used — higher priority = higher score.
#[derive(Clone)]
pub struct TaskQueue {
    pool:   Pool,
    prefix: String,
}

impl TaskQueue {
    pub fn new(pool: Pool, prefix: impl Into<String>) -> Self {
        Self {
            pool,
            prefix: prefix.into(),
        }
    }

    /// Enqueue a task for immediate processing.
    pub async fn enqueue(&self, queue: &str, task: &Task) -> Result<()> {
        let key     = self.queue_key(queue);
        let payload = serde_json::to_string(task)?;
        let mut conn = self.pool.get().await?;

        // Use sorted set so workers can dequeue highest priority first.
        let score = task.priority as f64;
        let _: () = conn.zadd(&key, &payload, score).await?;

        debug!(queue=%queue, task_id=%task.task_id, "task enqueued");
        Ok(())
    }

    /// Dequeue the highest-priority task (non-blocking).
    pub async fn dequeue(&self, queue: &str) -> Result<Option<Task>> {
        let key = self.queue_key(queue);
        let mut conn = self.pool.get().await?;

        // ZPOPMAX returns highest score first.
        let result: Vec<(String, f64)> = conn.zpopmax(&key, 1).await?;

        match result.into_iter().next() {
            None => Ok(None),
            Some((payload, _)) => {
                let task: Task = serde_json::from_str(&payload)?;
                debug!(queue=%queue, task_id=%task.task_id, "task dequeued");
                Ok(Some(task))
            }
        }
    }

    /// Dequeue up to `count` tasks.
    pub async fn dequeue_batch(&self, queue: &str, count: usize) -> Result<Vec<Task>> {
        let key = self.queue_key(queue);
        let mut conn = self.pool.get().await?;

        let results: Vec<(String, f64)> = conn.zpopmax(&key, count as isize).await?;

        let tasks = results
            .into_iter()
            .filter_map(|(payload, _)| {
                serde_json::from_str::<Task>(&payload)
                    .map_err(|e| warn!(error=%e, "failed to deserialise queued task"))
                    .ok()
            })
            .collect();

        Ok(tasks)
    }

    /// Return the queue depth.
    pub async fn len(&self, queue: &str) -> Result<u64> {
        let key = self.queue_key(queue);
        let mut conn = self.pool.get().await?;
        let count: u64 = conn.zcard(&key).await?;
        Ok(count)
    }

    /// Move a failed task to the dead-letter queue.
    pub async fn dead_letter(&self, queue: &str, mut task: Task) -> Result<()> {
        task.attempts += 1;
        let dl_queue = format!("{}.dlq", queue);
        if task.attempts < task.max_attempts {
            self.enqueue(queue, &task).await?;
        } else {
            self.enqueue(&dl_queue, &task).await?;
            warn!(
                task_id=%task.task_id,
                task_type=%task.task_type,
                "task moved to DLQ after {} attempts",
                task.attempts
            );
        }
        Ok(())
    }

    fn queue_key(&self, queue: &str) -> String {
        format!("{}:queue:{}", self.prefix, queue)
    }
}
