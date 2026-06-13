use sqlx::{
    PgPool,
    Row,
};

use crate::models::outbox_event::OutboxEvent;

pub async fn fetch_unpublished_events(
    pool: &PgPool,
) -> anyhow::Result<Vec<OutboxEvent>> {

    let rows =
        sqlx::query(
            r#"
            SELECT
                event_id,
                tenant_id,
                aggregate_type,
                aggregate_id,
                event_type,
                event_payload,
                topic_name,
                published,
                retry_count,
                created_at
            FROM event_store.outbox_events
            WHERE published = false
            ORDER BY created_at ASC
            LIMIT 100
            FOR UPDATE SKIP LOCKED
            "#
        )
        .fetch_all(pool)
        .await?;

    let events =
        rows
            .into_iter()
            .map(|row| {

                OutboxEvent {

                    event_id:
                        row.get("event_id"),

                    tenant_id:
                        row.get("tenant_id"),

                    aggregate_type:
                        row.get("aggregate_type"),

                    aggregate_id:
                        row.get("aggregate_id"),

                    event_type:
                        row.get("event_type"),

                    event_payload:
                        row.get("event_payload"),

                    topic_name:
                        row.get("topic_name"),

                    published:
                        row.get("published"),

                    retry_count:
                        row.get("retry_count"),

                    created_at:
                        row.get("created_at"),
                }
            })
            .collect();

    Ok(events)
}

pub async fn mark_event_published(
    pool:     &PgPool,
    event_id: uuid::Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        "UPDATE event_store.outbox_events \
         SET published = true, published_at = NOW() \
         WHERE event_id = $1",
    )
    .bind(event_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Increment the retry counter so the next poll picks it up with back-off.
pub async fn mark_event_failed(
    pool:     &PgPool,
    event_id: uuid::Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        "UPDATE event_store.outbox_events \
         SET retry_count = retry_count + 1 \
         WHERE event_id = $1",
    )
    .bind(event_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Move an event to the dead-letter queue and mark it dead in the main table.
///
/// The DLQ table (`event_store.outbox_dlq`) is created by migration 0003.
/// Operators can inspect and replay DLQ events via the admin API.
pub async fn move_to_dlq(
    pool:     &PgPool,
    event_id: uuid::Uuid,
    reason:   &str,
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    // Copy to DLQ
    sqlx::query(
        r#"
        INSERT INTO event_store.outbox_dlq
            (event_id, tenant_id, aggregate_type, aggregate_id, event_type,
             event_payload, topic_name, retry_count, failure_reason, moved_at)
        SELECT
            event_id, tenant_id, aggregate_type, aggregate_id, event_type,
            event_payload, topic_name, retry_count, $2, NOW()
        FROM event_store.outbox_events
        WHERE event_id = $1
        ON CONFLICT (event_id) DO NOTHING
        "#,
    )
    .bind(event_id)
    .bind(reason)
    .execute(&mut *tx)
    .await?;

    // Mark as dead in the main table so it's no longer polled
    sqlx::query(
        "UPDATE event_store.outbox_events \
         SET published = true, published_at = NOW() \
         WHERE event_id = $1",
    )
    .bind(event_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}