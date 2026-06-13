use std::time::Duration;

use anyhow::Result;
use rdkafka::producer::FutureProducer;
use sqlx::PgPool;
use tracing::{error, info};

use crate::outbox::poller::poll_outbox;

const POLL_INTERVAL: Duration = Duration::from_secs(5);

/// Start the outbox relay worker.
///
/// Polls `event_store.outbox_events` every 5 seconds, publishes pending events
/// to Kafka, and applies exponential back-off + DLQ on repeated failures.
///
/// This function **never returns** unless the process is killed — it handles all
/// errors internally and keeps looping.
pub async fn start_outbox_worker(pool: PgPool, producer: FutureProducer) -> Result<()> {
    info!("Outbox worker started — polling every {}s", POLL_INTERVAL.as_secs());

    loop {
        if let Err(e) = poll_outbox(&pool, &producer).await {
            error!(error=%e, "outbox poll cycle failed — continuing");
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}
