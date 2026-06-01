use anyhow::Result;

use sqlx::PgPool;

use rdkafka::producer::FutureProducer;

use crate::{
    kafka::producer::publish_event,
    models::outbox_event::OutboxEvent,
    outbox::repository::mark_event_published,
};

//
// ========================================
// PUBLISH OUTBOX EVENT
// ========================================
//

pub async fn publish_outbox_event(
    pool: &PgPool,
    producer: &FutureProducer,
    event: OutboxEvent,
) -> Result<()> {

    //
    // ====================================
    // SERIALIZE PAYLOAD
    // ====================================
    //

    let payload =
        serde_json::to_string(
            &event.event_payload
        )?;

    //
    // ====================================
    // EVENT KEY
    // ====================================
    //
    // Entity-based partitioning
    // ensures ordering guarantees.
    //

    let event_key =
        event.aggregate_id.to_string();

    //
    // ====================================
    // PUBLISH TO KAFKA
    // ====================================
    //

    publish_event(
        producer,
        &event.topic_name,
        &event_key,
        &payload,
    )
    .await?;

    //
    // ====================================
    // MARK AS PUBLISHED
    // ====================================
    //

    mark_event_published(
        pool,
        event.event_id,
    )
    .await?;

    //
    // ====================================
    // LOGGING
    // ====================================
    //

    println!(
        "Published outbox event successfully. event_id={}, topic={}",
        event.event_id,
        event.topic_name
    );

    Ok(())
}