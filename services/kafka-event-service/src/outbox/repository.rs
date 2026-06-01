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
    pool: &PgPool,
    event_id: uuid::Uuid,
) -> anyhow::Result<()> {

    sqlx::query(
        r#"
        UPDATE event_store.outbox_events
        SET
            published = true,
            published_at = NOW()
        WHERE event_id = $1
        "#
    )
    .bind(event_id)
    .execute(pool)
    .await?;

    Ok(())
}