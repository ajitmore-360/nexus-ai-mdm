use anyhow::Result;
use sqlx::PgPool;
use uuid::Uuid;

/// Re-insert a single DLQ event back into `outbox_events` with retry_count=0
/// so the worker picks it up on the next poll cycle.
pub async fn replay_dlq_event(pool: &PgPool, event_id: Uuid) -> Result<()> {
    let mut tx = pool.begin().await?;

    let inserted = sqlx::query(
        r#"
        INSERT INTO event_store.outbox_events
            (event_id, tenant_id, aggregate_type, aggregate_id, event_type,
             event_payload, topic_name, published, retry_count, created_at)
        SELECT
            gen_random_uuid(), tenant_id, aggregate_type, aggregate_id, event_type,
            event_payload, topic_name, false, 0, NOW()
        FROM event_store.outbox_dlq
        WHERE event_id = $1
        "#,
    )
    .bind(event_id)
    .execute(&mut *tx)
    .await?;

    if inserted.rows_affected() == 0 {
        return Err(anyhow::anyhow!("DLQ event {} not found", event_id));
    }

    sqlx::query("DELETE FROM event_store.outbox_dlq WHERE event_id = $1")
        .bind(event_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    tracing::info!(event_id=%event_id, "DLQ event replayed to outbox");
    Ok(())
}

/// Replay every event in the DLQ back into `outbox_events`.
/// Returns the number of events re-queued.
pub async fn replay_all_dlq_events(pool: &PgPool) -> Result<usize> {
    let mut tx = pool.begin().await?;

    let result = sqlx::query(
        r#"
        INSERT INTO event_store.outbox_events
            (event_id, tenant_id, aggregate_type, aggregate_id, event_type,
             event_payload, topic_name, published, retry_count, created_at)
        SELECT
            gen_random_uuid(), tenant_id, aggregate_type, aggregate_id, event_type,
            event_payload, topic_name, false, 0, NOW()
        FROM event_store.outbox_dlq
        "#,
    )
    .execute(&mut *tx)
    .await?;

    let count = result.rows_affected() as usize;

    sqlx::query("DELETE FROM event_store.outbox_dlq")
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    tracing::info!(count=%count, "all DLQ events replayed to outbox");
    Ok(count)
}

/// Return the number of events currently in the DLQ.
pub async fn dlq_depth(pool: &PgPool) -> Result<i64> {
    let count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM event_store.outbox_dlq")
        .fetch_one(pool)
        .await?;
    Ok(count)
}
