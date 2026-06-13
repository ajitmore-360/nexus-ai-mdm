use std::time::Duration;

use anyhow::Result;
use rdkafka::producer::FutureProducer;
use sqlx::PgPool;
use tracing::{debug, error, info, warn};

use crate::outbox::{
    publisher::publish_outbox_event,
    repository::{
        fetch_unpublished_events, mark_event_failed,
        mark_event_published, move_to_dlq,
    },
};

/// Maximum publish attempts before moving an event to the DLQ.
const MAX_RETRIES: i32 = 3;

/// Retry back-off durations per attempt (0-indexed).
const RETRY_BACKOFF: [Duration; 3] = [
    Duration::from_secs(5),
    Duration::from_secs(25),
    Duration::from_secs(125),
];

/// Poll the outbox and publish pending events to Kafka.
///
/// Events that fail after `MAX_RETRIES` attempts are moved to the dead-letter
/// queue (`event_store.outbox_dlq`) so they can be inspected and replayed
/// without blocking healthy events.
pub async fn poll_outbox(pool: &PgPool, producer: &FutureProducer) -> Result<()> {
    let events = fetch_unpublished_events(pool).await?;

    if events.is_empty() {
        debug!("outbox is empty — nothing to publish");
        return Ok(());
    }

    info!(batch_size = events.len(), "outbox poll started");

    let mut published_count = 0usize;
    let mut failed_count    = 0usize;
    let mut dlq_count       = 0usize;

    for event in events {
        let event_id   = event.event_id;
        let topic      = event.topic_name.clone();
        let retry_count = event.retry_count;

        // If this event has already exceeded max retries, send straight to DLQ.
        if retry_count >= MAX_RETRIES {
            warn!(
                event_id  = %event_id,
                topic     = %topic,
                retries   = retry_count,
                "event exceeded max retries — moving to DLQ"
            );
            if let Err(e) = move_to_dlq(pool, event_id, "exceeded max retries").await {
                error!(event_id=%event_id, error=%e, "failed to move event to DLQ");
            }
            dlq_count += 1;
            continue;
        }

        match publish_outbox_event(pool, producer, event).await {
            Ok(()) => {
                if let Err(e) = mark_event_published(pool, event_id).await {
                    error!(event_id=%event_id, error=%e, "published to Kafka but failed to mark as published");
                }
                info!(event_id=%event_id, topic=%topic, "event published");
                published_count += 1;
            }
            Err(e) => {
                warn!(
                    event_id = %event_id,
                    topic    = %topic,
                    attempt  = retry_count + 1,
                    max      = MAX_RETRIES,
                    error    = %e,
                    "failed to publish event — will retry"
                );

                // Back off proportional to attempt number
                let backoff = RETRY_BACKOFF.get(retry_count as usize)
                    .copied()
                    .unwrap_or(Duration::from_secs(125));

                tokio::time::sleep(backoff).await;

                if let Err(e) = mark_event_failed(pool, event_id).await {
                    error!(event_id=%event_id, error=%e, "failed to increment retry count");
                }
                failed_count += 1;
            }
        }
    }

    if published_count > 0 || failed_count > 0 || dlq_count > 0 {
        info!(
            published = published_count,
            failed    = failed_count,
            dlq       = dlq_count,
            "outbox poll complete"
        );
    }

    Ok(())
}
